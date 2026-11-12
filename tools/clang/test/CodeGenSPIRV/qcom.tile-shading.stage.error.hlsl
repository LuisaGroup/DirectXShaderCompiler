// RUN: not %dxc -T vs_6_0 -E main -fcgl -HV 2021 -fspv-extension=SPV_QCOM_tile_shading %s -spirv 2>&1 | FileCheck %s

// G30/L4 gate: tile shading in a stage that cannot have it.
//
// The TileShadingQCOM capability is only legal in a compute or fragment stage
// (SPIRV-Tools: "The TileShadingQCOM capability must not be enabled in any stage
// other than compute or fragment"), so SpirvEmitter::checkTileShadingQCOM refuses
// both the tile built-ins and the two execution modes in every other stage. Doing
// it in the compiler rather than letting the validator do it keeps the diagnostic
// on the source line that caused it, instead of a fatal "generated SPIR-V is
// invalid" with no location.
//
// This is a vertex shader, which has neither tile attachments nor tiles. The
// storage class half of the same rule aborts the module once the global fails, so
// it lives in qcom.tile-shading.stage-attachment.error.hlsl. The positive halves
// are qcom.tile-shading.hlsl (fragment) and qcom.tile-shading.rate.hlsl
// (compute).

#include <vk/qcom/tile_shading.h>

float4 main(float4 pos : POSITION) : SV_Position {
  // CHECK: error: vk::qcom::TileOffset is only available in compute and fragment shaders
  uint2 origin = vk::qcom::TileOffset();
  // CHECK: error: vk::qcom::TileDimension is only available in compute and fragment shaders
  uint3 dimension = vk::qcom::TileDimension();
  // CHECK: error: vk::qcom::TileApronSize is only available in compute and fragment shaders
  uint2 apron = vk::qcom::TileApronSize();
  // CHECK: error: NonCoherentTileAttachmentReadQCOM is only available in compute and fragment shaders
  vk::ext_execution_mode(
      vk::qcom::ExecutionModeNonCoherentTileAttachmentReadQCOM);
  // CHECK: error: TileShadingRateQCOM is only available in compute and fragment shaders
  vk::ext_execution_mode(vk::qcom::ExecutionModeTileShadingRateQCOM, 2, 2, 1);
  return pos + float4(origin.x, dimension.y, apron.y, 0.0);
}
