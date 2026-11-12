// RUN: %dxc -T ps_6_0 -E mainPS -spirv -fcgl -HV 2021 -fspv-extension=SPV_QCOM_tile_shading %s
// RUN: %dxc -T cs_6_0 -E mainCS -spirv -fcgl -HV 2021 -fspv-extension=SPV_QCOM_tile_shading %s

// Tile shading with VK_QCOM_tile_shading (SPV_QCOM_tile_shading).
//
// A tile-based GPU renders a framebuffer as a grid of rectangular *tiles* and
// keeps the attachments of the tile it is rendering in an on-chip "tile memory"
// instead of system memory. VK_QCOM_tile_shading lets a shader work on that
// memory directly: instead of being limited to the pixel it was launched for, a
// fragment or compute shader can read the render pass attachments at any location
// inside the current tile, and a compute shader can write the tile's color
// attachments. A pass that runs per tile - a resolve, a post-processing kernel, an
// image-processing step - then never leaves the chip.
//
// The SPIR-V surface is one storage class, three built-ins and two execution
// modes:
//
//   [[vk::ext_storage_class(vk::qcom::StorageClassTileAttachmentQCOM)]]
//   vk::qcom::TileAttachment2D<float4> color;
//       %t = OpTypeImage %float 2D 2 0 0 2 Rgba32f
//       %p = OpTypePointer TileAttachmentQCOM %t
//       %v = OpVariable %p TileAttachmentQCOM
//       OpDecorate %v DescriptorSet 0 / OpDecorate %v Binding 0
//   OpCapability TileShadingQCOM (4495)
//   OpExtension "SPV_QCOM_tile_shading"
//
//   vk::qcom::TileOffset()     -> OpLoad of BuiltIn TileOffsetQCOM (4492), uint2
//   vk::qcom::TileDimension()  -> OpLoad of BuiltIn TileDimensionQCOM (4493), uint3
//   vk::qcom::TileApronSize()  -> OpLoad of BuiltIn TileApronSizeQCOM (4494), uint2
//
//   vk::ext_execution_mode(vk::qcom::ExecutionModeNonCoherentTileAttachmentReadQCOM)
//       -> OpExecutionMode %main NonCoherentTileAttachmentReadQCOM (4489),
//          fragment only
//   vk::ext_execution_mode(vk::qcom::ExecutionModeTileShadingRateQCOM, x, y, z)
//       -> OpExecutionMode %main TileShadingRateQCOM x y z (4490), compute only
//
// What the three built-ins mean:
//   TileOffset    - the framebuffer coordinate of the top-left texel of the tile
//                   the invocation belongs to, so "the pixel next to mine inside
//                   the tile" is pos.xy + delta - TileOffset().
//   TileDimension - the size of every tile of this rendering pass in pixels (x, y)
//                   and the number of layers (z). Edge tiles report the same size
//                   even though they cover fewer pixels.
//   TileApronSize - the width of the apron in x and y: the guard band of extra
//                   pixels a tile carries when the render pass enables tiling
//                   aprons, which is what makes a multi-tap filter at a tile
//                   boundary read the same neighbours it reads in the tile
//                   interior.
//
// NonCoherentTileAttachmentReadQCOM gives up rasterization ordering for the reads
// of the attachments: a fragment that reads a pixel another fragment of the same
// tile writes may see the value from before or after that write, which lets the
// driver keep more of the tile in its own storage. Only the ordered case is
// portable, so the mode is opt-in per shader.
//
// TileShadingRateQCOM makes a compute entry point run per tile instead of per
// workgroup: x, y and z are how many pixels one invocation covers in each
// dimension (x and y must be powers of 2, and default to 1), and the
// implementation derives workgroup sizes and counts from the tile size. The rates
// replace the workgroup size, so the [numthreads] a compute entry point must carry
// is dropped from the module - SPIR-V forbids LocalSize together with
// TileShadingRateQCOM.
//
// Required from the host (the compiler cannot check any of it):
//   * Vulkan device extension VK_QCOM_tile_shading, and the
//     VkPhysicalDeviceTileShadingFeaturesQCOM bits the shader relies on:
//     tileShading, plus tileShadingFragmentStage / tileShadingComputeStage,
//     tileShadingColorAttachments / ...Depth... / ...Stencil... /
//     ...InputAttachments / ...SampledAttachments, tileShadingPerTileDraw /
//     tileShadingPerTileDispatch and tileShadingBufferStores as applicable;
//   * VkPhysicalDeviceTileShadingPropertiesQCOM: maxTileShadingRate bounds the
//     rates above (a larger rate is a run-time failure, not a compile-time one),
//     maxApronSize bounds the apron, and preferNonCoherent hints whether the
//     non-coherent read mode is the faster choice on the device;
//   * a compute entry point that declares TileShadingRateQCOM is dispatched with
//     vkCmdDispatchTileQCOM, and draws/dispatches that must run once per tile are
//     bracketed with vkCmdBeginPerTileExecutionQCOM / vkCmdEndPerTileExecutionQCOM;
//   * a render pass that wants aprons declares them in
//     VkRenderPassTileShadingCreateInfoQCOM;
//   * the tile attachment is bound as an image descriptor at the set/binding the
//     shader declares, laid out with the tile shading image layouts. Which render
//     pass attachment the descriptor refers to is the host's choice: the shader
//     declaration only says "an attachment of the current tile".
//
// A driver without VK_QCOM_tile_shading rejects a module that declares
// TileShadingQCOM, which is why DXC only emits it when
// -fspv-extension=SPV_QCOM_tile_shading is given (see docs/SPIR-V.rst). The tests
// that pin the encoding are
// tools/clang/test/CodeGenSPIRV/qcom.tile-shading*.hlsl.

#include <vk/qcom/tile_shading.h>

// Invocation: one per tile. The attachment is a 2D storage image the driver keeps
// in tile memory; [[vk::binding]] is the descriptor it is bound to, and both
// DescriptorSet and Binding are required by the extension.
[[vk::binding(0, 0)]]
[[vk::ext_storage_class(vk::qcom::StorageClassTileAttachmentQCOM)]]
vk::qcom::TileAttachment2D<float4> color;

// Fragment shader: read the neighbouring texel of the same tile, which a fragment
// shader could not address at all without tile shading, and write the tile back.
// The non-coherent read mode says the read may ignore rasterization order.
float4 mainPS(float4 pos : SV_Position) : SV_Target {
  // OpExecutionMode %main NonCoherentTileAttachmentReadQCOM
  vk::ext_execution_mode(
      vk::qcom::ExecutionModeNonCoherentTileAttachmentReadQCOM);

  // OpLoad of BuiltIn TileOffsetQCOM / TileDimensionQCOM / TileApronSizeQCOM
  uint2 tileOrigin = vk::qcom::TileOffset();
  uint3 tileSize = vk::qcom::TileDimension();
  uint2 apron = vk::qcom::TileApronSize();

  // The offset of this fragment inside its tile, and the tap one texel to the
  // right - the first pixel of the apron when this fragment sits on the tile's
  // right edge.
  uint2 inTile = uint2(pos.xy) - tileOrigin;
  uint2 tap = min(inTile + uint2(1, 0), tileSize.xy + apron.xy - uint2(1, 1));

  // OpImageRead on the TileAttachmentQCOM variable, then OpImageWrite.
  float4 here = color[uint2(pos.xy)];
  float4 neighbour = color[tileOrigin + tap];
  float4 result = 0.25 * here + 0.75 * neighbour;
  color[tileOrigin + tap] = result;

  return result;
}

// Compute shader: one invocation set per tile, four pixels wide and four pixels
// tall per invocation (the z rate is the number of samples). The frame is
// processed entirely out of tile memory.
[[vk::binding(1, 0)]]
RWStructuredBuffer<float4> averages;

[numthreads(1, 1, 1)]
void mainCS(uint3 tid : SV_DispatchThreadID) {
  // OpExecutionMode %main TileShadingRateQCOM 2 4 1
  // x = 2 and y = 4 are powers of 2; z = 1 is the sample count. [numthreads] is
  // required by HLSL but not emitted: the rates replace the workgroup size.
  vk::ext_execution_mode(vk::qcom::ExecutionModeTileShadingRateQCOM, 2, 4, 1);

  uint2 tileOrigin = vk::qcom::TileOffset();
  uint3 tileSize = vk::qcom::TileDimension();

  // A 3x3 box filter over the tile, one invocation per 2x4 block of pixels. Every
  // read is inside the tile, so it is served from tile memory.
  float4 sum = float4(0.0, 0.0, 0.0, 0.0);
  for (int dy = -1; dy <= 1; ++dy) {
    for (int dx = -1; dx <= 1; ++dx) {
      int2 at = int2(tileOrigin + tid.xy * uint2(2, 4)) + int2(dx, dy);
      sum += color[max(at, int2(0, 0))];
    }
  }
  float4 filtered = sum / 9.0;

  // Write the result back into the tile and publish the block average to a buffer
  // the host reads afterwards.
  color[tileOrigin + tid.xy * uint2(2, 4)] = filtered;
  averages[tid.x + tid.y * tileSize.x] = filtered;
}
