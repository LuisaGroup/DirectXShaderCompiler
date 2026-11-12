// RUN: not %dxc -T ps_6_0 -E main -fcgl -HV 2021 %s -spirv 2>&1 | FileCheck %s

// G30/L4 gate, second half: the three tile built-in accessors and the two
// tile-shading execution modes are opt-in as well.
//
// Each one is gated from the emitter (SpirvEmitter::processTileShadingBuiltinQCOM
// and SpirvEmitter::checkTileShadingExecutionModeQCOM, the latter reached from
// both vk::ext_execution_mode and [[vk::spvexecutionmode]]), because unlike a
// storage class a built-in or an execution mode has no other place to be refused:
// without the gate the module would declare TileShadingQCOM, which a driver
// without VK_QCOM_tile_shading rejects.
//
// All four diagnostics are emitted, in source order, from a single compile - no
// module is written. The storage class half is
// qcom.tile-shading.extension.error.hlsl; the positive halves are
// qcom.tile-shading.hlsl (fragment) and qcom.tile-shading.rate.hlsl (compute).

#include <vk/qcom/tile_shading.h>

float4 main(float4 pos : SV_Position) : SV_Target {
  // CHECK: error: vk::qcom::TileOffset requires the SPV_QCOM_tile_shading extension; pass -fspv-extension=SPV_QCOM_tile_shading to enable it
  uint2 origin = vk::qcom::TileOffset();
  // CHECK: error: vk::qcom::TileDimension requires the SPV_QCOM_tile_shading extension; pass -fspv-extension=SPV_QCOM_tile_shading to enable it
  uint3 dimension = vk::qcom::TileDimension();
  // CHECK: error: vk::qcom::TileApronSize requires the SPV_QCOM_tile_shading extension; pass -fspv-extension=SPV_QCOM_tile_shading to enable it
  uint2 apron = vk::qcom::TileApronSize();
  // CHECK: error: NonCoherentTileAttachmentReadQCOM requires the SPV_QCOM_tile_shading extension; pass -fspv-extension=SPV_QCOM_tile_shading to enable it
  vk::ext_execution_mode(
      vk::qcom::ExecutionModeNonCoherentTileAttachmentReadQCOM);
  return pos + float4(origin.x, dimension.y, apron.y, 0.0);
}
