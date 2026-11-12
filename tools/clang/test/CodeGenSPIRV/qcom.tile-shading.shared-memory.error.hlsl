// RUN: not %dxc -T ps_6_0 -E main -fcgl -HV 2021 -fspv-extension=SPV_QCOM_tile_shading %s -spirv 2>&1 | FileCheck %s

// G30/L4 gate: a tile attachment cannot be placed in shared memory.
//
// VK_QCOM_tile_shading describes a tile attachment as an image the driver keeps
// in tile memory for the duration of a tile - not as workgroup shared memory.
// 'groupshared' asks for the Workgroup storage class, which
// [[vk::ext_storage_class]] would silently replace, so
// SpirvEmitter::checkTileAttachmentQCOM refuses the combination instead of
// dropping one of the two: a shader that wanted workgroup memory would otherwise
// get a descriptor-backed tile attachment, or the other way round.
//
// The variable is deliberately never indexed: a groupshared texture is in address
// space 3 and HLSL has no operator[] for that, so any use would hit a front-end
// type error before CodeGen ever sees the declaration. The declaration alone is
// what this gate is about, and the positive half is qcom.tile-shading.hlsl.

#include <vk/qcom/tile_shading.h>

[[vk::binding(0, 0)]]
// CHECK: error: a tile attachment cannot be declared 'groupshared': the TileAttachmentQCOM storage class is tile memory, not workgroup shared memory
[[vk::ext_storage_class(vk::qcom::StorageClassTileAttachmentQCOM)]]
groupshared vk::qcom::TileAttachment2D<float4> color;

float4 main(float4 pos : SV_Position) : SV_Target {
  return pos;
}
