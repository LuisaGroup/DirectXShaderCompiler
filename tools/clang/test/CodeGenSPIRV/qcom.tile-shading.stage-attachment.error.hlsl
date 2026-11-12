// RUN: not %dxc -T vs_6_0 -E main -fcgl -HV 2021 -fspv-extension=SPV_QCOM_tile_shading %s -spirv 2>&1 | FileCheck %s

// G30/L4 gate, storage class half: a tile attachment in a stage that cannot have
// one.
//
// A tile attachment is tile memory of a render pass (or of a per-tile compute
// dispatch), which a vertex shader has no access to, and the TileShadingQCOM
// capability the storage class implies is only legal in a compute or fragment
// stage. SpirvEmitter::checkTileAttachmentQCOM rejects the declaration, so the
// shader gets a diagnostic on the declaration instead of a fatal
// "generated SPIR-V is invalid: [VUID-StandaloneSpirv-TileShadingQCOM-10686]".
//
// This file holds the storage class on its own because a failed global abandons
// the module: the built-in and execution mode halves of the same rule are in
// qcom.tile-shading.stage.error.hlsl. The positive half is
// qcom.tile-shading.hlsl.

#include <vk/qcom/tile_shading.h>

[[vk::binding(0, 0)]]
// CHECK: error: the TileAttachmentQCOM storage class is only available in compute and fragment shaders
[[vk::ext_storage_class(vk::qcom::StorageClassTileAttachmentQCOM)]]
vk::qcom::TileAttachment2D<float4> color;

float4 main(float4 pos : POSITION) : SV_Position {
  return pos;
}
