// RUN: not %dxc -T ps_6_0 -E main -fcgl -HV 2021 %s -spirv 2>&1 | FileCheck %s

// G30/L4 gate: SPV_QCOM_tile_shading is opt-in, so a tile attachment cannot be
// declared without -fspv-extension=SPV_QCOM_tile_shading.
//
// FeatureManager::enabledByDefault returns false for Extension::QCOM_tile_shading
// (the module would declare TileShadingQCOM, which a driver without
// VK_QCOM_tile_shading rejects, and the capability is only legal in a compute or
// fragment stage), so the extension is not part of the default allow-list and
// SpirvEmitter::checkTileAttachmentQCOM rejects the storage class instead of
// silently emitting a module with a capability the host never asked for. The
// message names the extension and the flag, in the spelling the other opt-in
// extensions in this tree use.
//
// This file holds the storage class on its own: once the global below fails,
// CodeGen abandons the module, so the built-in and execution mode diagnostics
// live in qcom.tile-shading.builtin.error.hlsl. The positive half is
// qcom.tile-shading.hlsl.

#include <vk/qcom/tile_shading.h>

[[vk::binding(0, 0)]]
// CHECK: error: the TileAttachmentQCOM storage class requires the SPV_QCOM_tile_shading extension; pass -fspv-extension=SPV_QCOM_tile_shading to enable it
[[vk::ext_storage_class(vk::qcom::StorageClassTileAttachmentQCOM)]]
vk::qcom::TileAttachment2D<float4> color;

float4 main(float4 pos : SV_Position) : SV_Target {
  return color[uint2(pos.xy)];
}
