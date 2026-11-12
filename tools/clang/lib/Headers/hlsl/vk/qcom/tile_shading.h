// Copyright (c) 2026 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Tile shading: VK_QCOM_tile_shading / SPV_QCOM_tile_shading.
//
// A tile-based GPU renders a framebuffer as a grid of rectangular *tiles*, and
// keeps the attachments of the tile it is currently rendering in a fast
// on-chip "tile memory" instead of system memory. VK_QCOM_tile_shading exposes
// that memory to the shader: a *tile attachment* is an image the driver keeps in
// tile memory, so a fragment or compute shader can
//
//  - read the render pass attachments (color, depth/stencil, input
//    attachments) at *any* location inside the tile rather than only at the
//    pixel it was launched for, and
//  - in a compute shader, write the color attachments of the tile, which is how
//    a per-tile compute pass (image processing, a resolve, a post pass) runs
//    without a round trip to memory.
//
// The extension also lets a shader ask to be launched once per tile, at a
// chosen shading rate, and to read where the current tile is and how big it is:
//
//   #include <vk/qcom/tile_shading.h>
//
//   using namespace vk;
//   using namespace vk::qcom;
//
//   [[vk::binding(0, 0)]]
//   [[vk::ext_storage_class(StorageClassTileAttachmentQCOM)]]
//   TileAttachment2D<float4> color;   // OpVariable TileAttachmentQCOM
//
//   // fragment shader: any pixel of the tile can be read or written
//   float4 main(float4 pos : SV_Position) : SV_Target {
//     uint2 tileOrigin = TileOffset();     // OpLoad of BuiltIn TileOffsetQCOM
//     uint2 at = uint2(pos.xy) + uint2(1, 0);
//     return color[at] + TileApronSize().xy;
//   }
//
//   // compute shader: one invocation set per tile, at a shading rate of 2x2
//   [numthreads(1, 1, 1)]
//   void main(uint3 tid : SV_DispatchThreadID) {
//     vk::ext_execution_mode(ExecutionModeTileShadingRateQCOM, 2, 2, 1);
//     ...
//   }
//
// ## The tile attachment variable
//
// HLSL has no tile attachment type, so a tile attachment is an ordinary 2D
// image (`Texture2D<T>` to read, `RWTexture2D<T>` to read and write) whose
// variable is declared in the TileAttachmentQCOM storage class (4491) with
// [[vk::ext_storage_class]]. SPIR-V CodeGen then emits
//
//   %t = OpTypeImage %float 2D 0 0 0 2 Rgba32f
//   %p = OpTypePointer TileAttachmentQCOM %t
//   %v = OpVariable %p TileAttachmentQCOM
//   OpDecorate %v DescriptorSet 0
//   OpDecorate %v Binding 0
//
// and every read or write lowers to OpImageRead / OpImageWrite on that
// variable, so the two `[[vk::binding]]` decorations are required (SPIRV-Tools:
// "Any variable in the TileAttachmentQCOM Storage Class must be decorated with
// DescriptorSet and Binding"). TileAttachment2D<T> names the image type and
// TileAttachmentSpirvPointer<T> names the pointer type, the analogue of
// vk::WorkgroupSpirvPointer in <vk/spirv.h>.
//
// The image has to be a plain 2D image - not an array, cube or multisampled
// one, and not a buffer ("Any OpTypeImage variable in the TileAttachmentQCOM
// Storage Class must have 2D as its dimension"); CodeGen diagnoses the rest.
//
// ## Tile shading rate (compute)
//
// A compute entry point that declares TileShadingRateQCOM is launched per tile
// instead of per workgroup: the rates say how many pixels one invocation
// covers in x, y and z, and the implementation derives the workgroup sizes and
// counts from the tile size. x and y must be powers of 2 (a compile error
// otherwise) and default to 1 when the mode is not declared. The rates replace
// the workgroup size, so [numthreads] - which HLSL still requires on a compute
// entry point - is dropped from the module when the mode is declared: SPIR-V
// forbids LocalSize together with TileShadingRateQCOM.
//
// ## Non-coherent tile attachment reads (fragment)
//
// By default the reads of a tile attachment observe the rasterization order, so
// a fragment that reads a pixel another fragment of the same tile writes gets
// the ordered value. NonCoherentTileAttachmentReadQCOM gives that up in exchange
// for letting the driver keep more of the tile in registers/cache: the reads may
// return the value of the pixel as it was at any point of the tile's lifetime.
// It is fragment-only ("The NonCoherentTileAttachmentQCOM execution mode must not
// be used in any stage other than fragment").
//
// ## Stages
//
// The TileShadingQCOM capability is only valid in a compute or a fragment
// stage, so tile shading is diagnosed in every other stage, and the tile shading
// rate mode only in compute and the non-coherent read mode only in fragment.
//
// ## Host requirements (the compiler cannot check any of these)
//
// The built-ins and the storage class only describe what the shader wants; the
// host has to make the device provide it:
//
//  - VK_QCOM_tile_shading must be enabled, and the corresponding
//    VkPhysicalDeviceTileShadingFeaturesQCOM features must be queried and
//    enabled: `tileShading` plus the per-stage and per-use features the shader
//    relies on (`tileShadingFragmentStage` / `tileShadingComputeStage`,
//    `tileShadingColorAttachments`, `tileShadingDepthAttachments`,
//    `tileShadingStencilAttachments`, `tileShadingInputAttachments`,
//    `tileShadingSampledAttachments`, `tileShadingPerTileDraw` /
//    `tileShadingPerTileDispatch` and `tileShadingBufferStores`).
//  - VkPhysicalDeviceTileShadingPropertiesQCOM (`maxTileShadingRate`,
//    `maxApronSize`, `tileGranularity`, `preferNonCoherent`) bounds the rates
//    and the apron a shader may ask for; a rate above the reported maximum is a
//    run-time failure, not a compile-time one.
//  - A compute shader that declares the tile shading rate is dispatched with
//    vkCmdDispatchTileQCOM, and per-tile draws/dispatches are bracketed with
//    vkCmdBeginPerTileExecutionQCOM / vkCmdEndPerTileExecutionQCOM; a render
//    pass that wants aprons declares them in
//    VkRenderPassTileShadingCreateInfoQCOM.
//  - A tile attachment is bound as an image descriptor (set/binding as declared)
//    through the tile shading image layouts, and the image must have been
//    created with tile shading usage; the shader declaration says nothing about
//    which render pass attachment the descriptor will refer to.
//
// Every entry point below has no definition anywhere: SPIR-V CodeGen emits the
// corresponding instruction in place of the call.

#ifndef _HLSL_VK_QCOM_TILE_SHADING_H_
#define _HLSL_VK_QCOM_TILE_SHADING_H_

namespace vk {
namespace qcom {

// Values from SPV_QCOM_tile_shading, spelled here so that a shader does not have
// to remember them. They are static const rather than an enum so that including
// this header does not add a variable to the module.
// The TileAttachmentQCOM storage class (4491) a tile attachment variable is
// declared in with [[vk::ext_storage_class]].
static const uint StorageClassTileAttachmentQCOM = 4491;
// Execution mode TileShadingRateQCOM (4490), for vk::ext_execution_mode.
static const uint ExecutionModeTileShadingRateQCOM = 4490;
// Execution mode NonCoherentTileAttachmentReadQCOM (4489), for
// vk::ext_execution_mode.
static const uint ExecutionModeNonCoherentTileAttachmentReadQCOM = 4489;

// A tile attachment: a 2D image whose variable is declared in the
// TileAttachmentQCOM storage class. Use RWTexture2D<T> when the shader writes the
// tile (compute) and Texture2D<T> when it only reads it; the binding comes from
// [[vk::binding(set, binding)]], which is required.
//   [[vk::binding(0, 0)]]
//   [[vk::ext_storage_class(vk::qcom::StorageClassTileAttachmentQCOM)]]
//   vk::qcom::TileAttachment2D<float4> color;
template <typename T> using TileAttachment2D = RWTexture2D<T>;

// A pointer to a tile attachment, i.e. the pointer type of a variable in the
// TileAttachmentQCOM storage class. This is the tile shading analogue of
// vk::WorkgroupSpirvPointer in <vk/spirv.h>: OpTypePointer (32) with a literal
// storage class operand and the pointee type, for the cases where a pointer
// rather than the image has to be named - the parameter or return type of a
// [[vk::ext_instruction]] declaration, the way vk::GetGroupSharedAddress names
// the Workgroup pointer type. It is a type, not a value: a tile attachment is
// named by the variable declared with [[vk::ext_storage_class]] above.
// vk::SpirvOpaqueType, vk::Literal and vk::integral_constant are builtin
// templates of the compiler, which is why this header needs no #include.
// clang-format off
template <typename PointeeType>
using TileAttachmentSpirvPointer = const vk::SpirvOpaqueType<
    /* OpTypePointer */ 32,
    vk::Literal<vk::integral_constant<uint, StorageClassTileAttachmentQCOM> >,
    PointeeType>;
// clang-format on

// The tile the current invocation belongs to, in framebuffer coordinates of its
// top-left texel. Lowers to an OpLoad of an Input variable decorated
// BuiltIn TileOffsetQCOM (4492); the result type is uint2.
uint2 TileOffset();

// The size of the tile in pixels (x and y) and the number of layers (z). Every
// tile of a rendering pass reports the same value, including the edge tiles that
// are only partially covered. Lowers to an OpLoad of an Input variable decorated
// BuiltIn TileDimensionQCOM (4493); the result type is uint3.
uint3 TileDimension();

// The width of the apron (the guard band of extra pixels a tile carries when the
// render pass enables tiling aprons) in the x and y directions. Lowers to an
// OpLoad of an Input variable decorated BuiltIn TileApronSizeQCOM (4494); the
// result type is uint2.
uint2 TileApronSize();

} // namespace qcom
} // namespace vk

#endif // _HLSL_VK_QCOM_TILE_SHADING_H_
