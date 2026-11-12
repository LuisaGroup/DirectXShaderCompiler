// RUN: %dxc -T ps_6_0 -E CASSharpen -spirv -fspv-target-env=vulkan1.3 -fspv-extension=SPV_QCOM_image_processing3 %s
// RUN: %dxc -T ps_6_0 -E Load4x1 -spirv -fspv-target-env=vulkan1.3 -fspv-extension=SPV_QCOM_image_processing3 %s

// Mode-selected texture gathers with VK_QCOM_image_processing3 /
// SPV_QCOM_image_processing3.
//
// VK_QCOM_image_processing3 adds OpImageGatherQCOM, a gather whose footprint is
// picked by a mode operand instead of being fixed to the 2x2 quad of
// OpImageGather. The Adreno GPUs the extension was written for implement the four
// footprints as dedicated instructions, so a kernel that has to read exactly those
// texels gets one hardware gather instead of four taps or a reprogrammed
// OpImageGather with ConstOffsets:
//
//   Gather4x1QCOM (0)  four horizontally adjacent texels,
//   GatherDQCOM   (1)  the four cardinal neighbours (a diamond),
//   GatherH2QCOM  (2)  two 2x1 pairs, one row above and one row below,
//   GatherV2QCOM  (3)  two 1x2 pairs, one column left and one column right.
//
// The entry points live in <vk/qcom/image_processing3.h> and lower to
//
//   %r = OpImageGatherQCOM %v4float %sampled_image %coord %int_1 %int_2
//
// i.e. (Result Type, Result, Sampled Image, Coordinate, Component, Mode). The
// component (a template argument of the header's entry points) and the mode (baked
// into them) are constants: SPIRV-Tools requires a constant component in a Vulkan
// environment, and the mode selects the capability:
//
//   Gather4x1QCOM                     -> OpCapability ImageGatherLinearQCOM (4543)
//   GatherDQCOM, GatherH2QCOM,
//   GatherV2QCOM                      -> OpCapability ImageGatherExtendedModesQCOM
//                                        (4544)
//
// plus OpExtension "SPV_QCOM_image_processing3". The two capabilities are separate
// device features, so a module only declares the one its modes need: CASSharpen
// below uses the diamond mode and declares ImageGatherExtendedModesQCOM, Load4x1
// uses the linear mode and declares ImageGatherLinearQCOM.
//
// These are gathers, not filters: no weights, no derivatives, base level only.
// Each mode also returns its four texels in its own lane order, which the kernel
// has to know (the write-up in docs/SPIR-V.rst lists it per mode).
//
// Required from the host (the compiler cannot check any of it):
//  * Vulkan device extension VK_QCOM_image_processing3 (enable
//    VK_QCOM_IMAGE_PROCESSING3_EXTENSION_NAME at vkCreateDevice), on top of the
//    VK_QCOM_image_processing family the image processing samplers come from;
//  * feature bit VkPhysicalDeviceImageProcessing3FeaturesQCOM::imageGatherLinear
//    for the Gather4x1QCOM mode and ::imageGatherExtendedModes for GatherDQCOM /
//    GatherH2QCOM / GatherV2QCOM (query the structure with
//    vkGetPhysicalDeviceFeatures2 and chain it into VkDeviceCreateInfo::pNext
//    with the bit the shader needs set to VK_TRUE);
//  * an image processing capable combined image sampler
//    (VK_SAMPLER_CREATE_IMAGE_PROCESSING_BIT_QCOM), bound as a combined image
//    sampler, which is why the shader declares vk::SampledTexture2D instead of a
//    Texture2D plus a SamplerState;
//  * format support for the view as a sampled image of a gather; the extension
//    restricts the views to Dim 2D (no cube maps, no depth comparison, no
//    ConstOffsets, no sparse residency).
//  * SPIR-V 1.4 or newer (the extension's own requirement), i.e.
//    -fspv-target-env=vulkan1.1spirv1.4 or a newer target environment, and
//    -fspv-extension=SPV_QCOM_image_processing3 in the allow-list - without it
//    every call below is a compile error.
//
// See the "Image gather modes" section of docs/SPIR-V.rst and
// tools/clang/test/CodeGenSPIRV/qcom.image-processing3*.hlsl.

#include <vk/qcom/image_processing3.h>

// A combined image sampler: the extension's gathers only accept an
// OpTypeSampledImage, and the sampler is the image processing one the host built.
vk::SampledTexture2D<float4> Input : register(t0);

// Contrast adaptive sharpening: the four cardinal neighbours come from one
// GatherDQCOM (capability ImageGatherExtendedModesQCOM), the centre texel from a
// point sample. The weight is driven by how much the local contrast differs from
// the neighbourhood's minimum and maximum, which is what makes the kernel
// "adaptive" - flat areas are left alone, edges are sharpened.
float4 CASSharpen(float2 uv : TEXCOORD0) : SV_Target {
  // One instruction, four texels: %neighbours = OpImageGatherQCOM %v4float
  // %input %uv %int_0 %int_1   (component 0, mode 1 = GatherDQCOM).
  float4 neighbours = vk::qcom::ImageGatherD(Input, uv);
  // The centre tap is not a gather: a single filtered sample at the base level.
  float4 centre = Input.SampleLevel(uv, 0.0f);

  float4 localMin = min(centre, min(min(neighbours.x, neighbours.y),
                                  min(neighbours.z, neighbours.w)));
  float4 localMax = max(centre, max(max(neighbours.x, neighbours.y),
                                  max(neighbours.z, neighbours.w)));
  // -1 where the local contrast is low, approaching 1 for a strong edge.
  float4 sharpness = saturate(1.0f - (localMax - localMin) * 4.0f) * -0.25f;
  // Unsharp mask with the adaptive weight.
  return saturate(centre + (centre - (neighbours.x + neighbours.y +
                                      neighbours.z + neighbours.w) * 0.25f) *
                               sharpness);
}

// A horizontal 4-tap kernel, e.g. the derivative an edge detector or a 4-tap
// horizontal upscaling filter needs. Gather4x1QCOM returns four adjacent texels of
// one row in a single instruction (capability ImageGatherLinearQCOM):
//
//   %row = OpImageGatherQCOM %v4float %input %uv %int_0 %int_0
//
// While GatherDQCOM/H2/V2 keep their four texels in the 2x2 quad's lane order,
// Gather4x1QCOM fills the lanes with increasing x, so a horizontal filter reads
// them in order.
float4 Load4x1(float2 uv : TEXCOORD0) : SV_Target {
  float4 row = vk::qcom::ImageGather4x1(Input, uv);
  // A simple horizontal Sobel-like difference: left pair minus right pair.
  float edge = (row.x + row.y) - (row.z + row.w);
  return float4(edge.xxx, 1.0f);
}

// A 12-tap separable upscaler needs no new mode: GatherH2QCOM (two rows) and
// GatherV2QCOM (two columns) plus the ordinary 2x2 gather of the sampled texture
// cover the twelve taps of the two passes, e.g.
//
//   float4 quad = Input.Gather(uv);                     // 4 taps, OpImageGather
//   float4 rows = vk::qcom::ImageGatherH2(Input, uv);   // 4 taps, two rows
//   float4 cols = vk::qcom::ImageGatherV2<1>(Input, uv); // 4 taps, two columns
//
// Note that the ordinary Gather and the QCOM modes order their four lanes
// differently; a real kernel weights each lane individually.
