// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Image gather modes: VK_QCOM_image_processing3 / SPV_QCOM_image_processing3.
//
// An ordinary texture gather (OpImageGather, what Texture2D::Gather* lowers to)
// always reads the 2x2 footprint that linear minification selects and returns one
// component of its four texels in a fixed lane order. SPV_QCOM_image_processing3
// adds a gather whose footprint is chosen by a mode operand, so an upscaling or
// sharpening kernel can ask for the taps it actually needs and let the texture
// unit do the addressing:
//
//   Gather4x1QCOM (0)  four horizontally adjacent texels - a 4-tap horizontal
//                      kernel, or vectorised loads with linear cache locality,
//   GatherDQCOM   (1)  the four texels of a diamond around the coordinate - with
//                      a point sample of the centre texel, a 5-tap sharpening
//                      kernel (contrast adaptive sharpening),
//   GatherH2QCOM  (2)  two 2x1 pairs, one row above and one row below the
//                      coordinate,
//   GatherV2QCOM  (3)  two 1x2 pairs, one column left and one column right of
//                      the coordinate; with GatherH2QCOM and an ordinary gather
//                      this builds the 12 taps of a separable upscaling filter.
//
// The entry points below lower to OpImageGatherQCOM (4545):
//
//   %r = OpImageGatherQCOM %v4float %sampled_image %coord %int_1 %int_2
//
// The operands are (IdResultType, IdResult, Sampled Image, Coordinate, Component,
// Mode [, Image Operands]). The result type is a four-component vector of the
// image's sampled type; "Sampled Image" must be an OpTypeSampledImage whose
// OpTypeImage has a Dim of 2D - the extension also allows Rect, which this header
// does not cover - and MS = 0; the coordinate is a floating-point vector (two
// components, plus the array layer for an arrayed image); the component selects the
// channel to gather from all four texels (0..3) and the mode the footprint (0..3).
//
// Component and Mode are ids, but both must be 32-bit integer *constants*:
// SPIRV-Tools rejects a non-constant component in a Vulkan environment ("Expected
// Component Operand to be a const object for Vulkan environment"), and the mode
// is what selects the capability. They are therefore not ordinary parameters: the
// component is a template argument (defaulting to 0, the channel GLSL's
// textureGather*QCOM reads when its optional comp argument is omitted) and the
// mode is baked into the declaration, one declaration per mode. The trailing
// `component` and `mode` parameters of each declaration exist only because the
// operands have to be function arguments; their defaults carry those constants
// into the emitted instruction, and a caller has no reason to pass them. Passing a
// runtime value as the component bypasses the guarantee above and produces a module
// SPIRV-Tools rejects ("Expected Component Operand to be a const object for Vulkan
// environment"); the compiler does not diagnose it itself.
//
// Using one of these entry points adds one of two capabilities, selected per call
// shape (see the OpImageGatherQCOM case in CapabilityVisitor):
//
//   Gather4x1QCOM                      ImageGatherLinearQCOM        (4543)
//   GatherDQCOM, GatherH2QCOM,
//   GatherV2QCOM                       ImageGatherExtendedModesQCOM (4544)
//
// plus OpExtension "SPV_QCOM_image_processing3". Both are emitted by SPIR-V
// CodeGen from the instruction itself, not by [[vk::ext_capability]] /
// [[vk::ext_extension]] on the declarations below: those attributes write the
// capability and the extension string unconditionally, so -fspv-extension could
// neither select nor refuse them. The extension is opt-in, like
// SPV_EXT_split_barrier and SPV_NV_cluster_acceleration_structure: without
// -fspv-extension=SPV_QCOM_image_processing3 every call is a compile error
// instead of a module that declares an extension the host never asked for.
//
// Notes and limitations (see docs/SPIR-V.rst):
// - The entry points are declarations without a body: SPIR-V CodeGen emits
//   OpImageGatherQCOM in place of the call (they are dispatched through
//   [[vk::ext_instruction]], not through an HLSL intrinsic table). They must be
//   called directly from the function that should contain the gather.
// - Requires SPIR-V 1.4, so the module needs a target environment of
//   -fspv-target-env=vulkan1.1spirv1.4 or newer (vulkan1.2, vulkan1.3, ...).
//   This compiler does not enforce that; only the validator could, and the
//   vendored SPIRV-Tools does not check the version an extension requires.
// - These are hardware assisted gathers, not filtering: no weights are applied,
//   no derivatives are taken and the level of detail is the base level, exactly as
//   for OpImageGather. A kernel still does its own multiply-accumulate on the four
//   returned texels.
// - The lane order of the result depends on the mode, and the four modes order
//   their texels differently, so the caller has to know the layout of the mode it
//   uses (SPV_QCOM_image_processing3, "Image Instructions"). The compiler cannot
//   check that a kernel reads the lanes in the order it means, and the test suite
//   has no execution coverage for this extension.
// - The image must already be a combined image sampler (vk::SampledTexture2D or
//   vk::SampledTexture2DArray, i.e. an OpTypeSampledImage). A Texture2D plus a
//   separate SamplerState is not accepted: whether an image and a sampler may be
//   combined is a host decision and DXC would otherwise open-code OpSampledImage
//   behind the shader author's back. Only Dim 2D images are covered, arrayed or
//   not; Rect and cube are not, and the arrayed declarations take a three
//   component coordinate whose third component is the array layer.
// - The host has to enable the feature of the capability the mode declares in
//   VkPhysicalDeviceImageProcessing3FeaturesQCOM - imageGatherLinear for
//   Gather4x1QCOM, imageGatherExtendedModes for GatherD/H2/V2 - and create the
//   combined image sampler with what the VK_QCOM_image_processing family requires
//   of image processing samplers
//   (VK_SAMPLER_CREATE_IMAGE_PROCESSING_BIT_QCOM). The compiler cannot check any
//   of that.
// - The gather restrictions of the extension apply and are not diagnosed: no cube
//   map views, no depth comparison (OpImageDrefGather), no ConstOffsets and no
//   sparse residency. A mismatched image view is a validation or runtime problem,
//   not a compile-time one.
// - This is a SPIR-V only surface. There is no DXIL instruction for a gather with
//   a mode operand, and the vk::SampledTexture* types only exist in a SPIR-V
//   compile: including this header in a DXIL compile fails on the type name
//   ("no type named 'SampledTexture2D' in namespace 'vk'") rather than leaving a
//   declaration without a definition.

#ifndef _HLSL_VK_QCOM_IMAGE_PROCESSING3_H_
#define _HLSL_VK_QCOM_IMAGE_PROCESSING3_H_

namespace vk {
namespace qcom {

// The mode operand is one of the GatherModes enumerants of
// SPV_QCOM_image_processing3: Gather4x1QCOM 0, GatherDQCOM 1, GatherH2QCOM 2,
// GatherV2QCOM 3. Each declaration below defaults its `mode` parameter to the
// right one, so the values never appear in shader code. They are written as
// literals rather than as named constants because a file-scope `static const int`
// in this header would be emitted as an unused OpConstant in every module that
// includes it, and a file-scope enum would be lowered to a Private variable and
// loaded at each call, which would make the mode operand non-constant.

// Gather4x1QCOM: four horizontally adjacent texels. Requires the
// ImageGatherLinearQCOM capability.
//
// A call is `ImageGather4x1(image, coord)`; the template argument is the
// component to gather from each texel (absent = 0, i.e. x/red, the channel
// GLSL's textureGather*QCOM reads when its optional comp argument is omitted;
// 1 = y/green, 2 = z/blue, 3 = w/alpha), so `ImageGather4x1<2>(image, coord)`
// gathers blue. The trailing `component` and `mode` parameters are not part of
// the surface: the instruction's operands have to be function arguments, so they
// exist to carry the two constants into it, and no caller has a reason to pass
// them.
template <int gatherComponent = 0, typename T>
[[vk::ext_instruction(/* OpImageGatherQCOM */ 4545)]] T ImageGather4x1(
    vk::SampledTexture2D<T> image, float2 coord, int component = gatherComponent,
    int mode = 0 /* Gather4x1QCOM */);

// Gather4x1QCOM on a 2D arrayed sampled image; the third coordinate component is
// the array layer.
template <int gatherComponent = 0, typename T>
[[vk::ext_instruction(/* OpImageGatherQCOM */ 4545)]] T ImageGather4x1Array(
    vk::SampledTexture2DArray<T> image, float3 coord,
    int component = gatherComponent, int mode = 0 /* Gather4x1QCOM */);

// GatherDQCOM: the four texels of a diamond around the coordinate. Requires the
// ImageGatherExtendedModesQCOM capability.
template <int gatherComponent = 0, typename T>
[[vk::ext_instruction(/* OpImageGatherQCOM */ 4545)]] T ImageGatherD(
    vk::SampledTexture2D<T> image, float2 coord, int component = gatherComponent,
    int mode = 1 /* GatherDQCOM */);

template <int gatherComponent = 0, typename T>
[[vk::ext_instruction(/* OpImageGatherQCOM */ 4545)]] T ImageGatherDArray(
    vk::SampledTexture2DArray<T> image, float3 coord,
    int component = gatherComponent, int mode = 1 /* GatherDQCOM */);

// GatherH2QCOM: two 2x1 pairs, above and below the coordinate. Requires the
// ImageGatherExtendedModesQCOM capability.
template <int gatherComponent = 0, typename T>
[[vk::ext_instruction(/* OpImageGatherQCOM */ 4545)]] T ImageGatherH2(
    vk::SampledTexture2D<T> image, float2 coord, int component = gatherComponent,
    int mode = 2 /* GatherH2QCOM */);

template <int gatherComponent = 0, typename T>
[[vk::ext_instruction(/* OpImageGatherQCOM */ 4545)]] T ImageGatherH2Array(
    vk::SampledTexture2DArray<T> image, float3 coord,
    int component = gatherComponent, int mode = 2 /* GatherH2QCOM */);

// GatherV2QCOM: two 1x2 pairs, left and right of the coordinate. Requires the
// ImageGatherExtendedModesQCOM capability.
template <int gatherComponent = 0, typename T>
[[vk::ext_instruction(/* OpImageGatherQCOM */ 4545)]] T ImageGatherV2(
    vk::SampledTexture2D<T> image, float2 coord, int component = gatherComponent,
    int mode = 3 /* GatherV2QCOM */);

template <int gatherComponent = 0, typename T>
[[vk::ext_instruction(/* OpImageGatherQCOM */ 4545)]] T ImageGatherV2Array(
    vk::SampledTexture2DArray<T> image, float3 coord,
    int component = gatherComponent, int mode = 3 /* GatherV2QCOM */);

} // namespace qcom
} // namespace vk

#endif // _HLSL_VK_QCOM_IMAGE_PROCESSING3_H_
