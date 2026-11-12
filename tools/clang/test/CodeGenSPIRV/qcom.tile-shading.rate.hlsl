// RUN: %dxc -T cs_6_0 -E main -fcgl -HV 2021 -fspv-extension=SPV_QCOM_tile_shading %s -spirv | FileCheck %s

// G30/L2 gate for the compute half of SPV_QCOM_tile_shading: the
// TileShadingRateQCOM execution mode and its three rate operands.
//
//   vk::ext_execution_mode(vk::qcom::ExecutionModeTileShadingRateQCOM, x, y, z)
//     ->  OpExecutionMode %main TileShadingRateQCOM x y z
//
// The operand order is the extension's (x rate, y rate, z rate), and it is the
// one thing a wrong lowering could permute without failing validation, so the
// rates below are all different: x = 2, y = 4, z = 3. SPIRV-Tools only constrains
// x and y ("The TileShadingRateQCOM execution mode's x and y values must be
// powers of 2"), so y = 4 is legal and z = 3 is free.
//
// The rates replace the workgroup size, so [numthreads] - which HLSL still
// requires on a compute entry point - must not reach the module: SPIRV-Tools
// rejects a compute entry point that declares both TileShadingRateQCOM and
// LocalSize/LocalSizeId ("If the TileShadingRateQCOM execution mode is used,
// LocalSize and LocalSizeId must not be specified"). The CHECK-NOT lines below
// are that half of the gate, and the module validating at all is the other half.
//
// The fragment half (TileAttachmentQCOM + the tile built-ins + the non-coherent
// read mode) is qcom.tile-shading.hlsl; the diagnostics for a rate that is not a
// power of 2 and for the mode in the wrong stage are
// qcom.tile-shading.rate.error.hlsl and qcom.tile-shading.stage.error.hlsl.

// L1: the capability and the extension are inferred from the mode, exactly once
// each, and the entry point is the compute one.
// CHECK:      OpCapability Shader
// CHECK:      OpCapability TileShadingQCOM
// CHECK-NOT:  OpCapability TileShadingQCOM
// CHECK:      OpExtension "SPV_QCOM_tile_shading"
// CHECK-NOT:  OpExtension "SPV_QCOM_tile_shading"
// CHECK:      OpEntryPoint GLCompute

// L2: the execution mode with its three operands in order.
// CHECK:      OpExecutionMode %main TileShadingRateQCOM 2 4 3
// CHECK-NOT:  OpExecutionMode %main TileShadingRateQCOM 4 2 3
// CHECK-NOT:  OpExecutionMode %main TileShadingRateQCOM 2 3 4
// CHECK-NOT:  OpExecutionMode %main TileShadingRateQCOM 2 4
// CHECK-NOT:  OpExecutionMode %main TileShadingRateQCOM 2 4 3 1
// CHECK-NOT:  OpExecutionMode %main TileShadingRateQCOM 2 4 3
// CHECK-NOT:  OpExecutionMode %main NonCoherentTileAttachmentReadQCOM

// L2: [numthreads(8, 8, 1)] must not produce LocalSize (or LocalSizeId), and the
// workgroup size must not reappear as a WorkgroupSize decoration either - the
// tile size is what the dispatch is expressed in.
// CHECK-NOT:  LocalSize
// CHECK-NOT:  WorkgroupSize

// L2: the tile attachment is the same TileAttachmentQCOM variable the fragment
// half uses, and a compute shader writes it with OpImageWrite.
// CHECK:      %type_2d_image = OpTypeImage %float 2D 2 0 0 2 Rgba32f
// CHECK:      %[[IMG_PTR:[0-9a-zA-Z_]+]] = OpTypePointer TileAttachmentQCOM %type_2d_image
// CHECK:      %color = OpVariable %[[IMG_PTR]] TileAttachmentQCOM
// CHECK:      %{{[0-9]+}} = OpLoad %type_2d_image %color
// CHECK-NEXT: %{{[0-9]+}} = OpImageRead %v4float
// CHECK:      OpImageWrite %{{[0-9]+}} %{{[0-9]+}} %{{[0-9]+}} None

#include <vk/qcom/tile_shading.h>

[[vk::binding(0, 0)]]
[[vk::ext_storage_class(vk::qcom::StorageClassTileAttachmentQCOM)]]
vk::qcom::TileAttachment2D<float4> color;

// [numthreads] is mandatory for an HLSL compute entry point; the rate mode above
// replaces it, so CodeGen drops the LocalSize it would otherwise emit.
[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  vk::ext_execution_mode(vk::qcom::ExecutionModeTileShadingRateQCOM, 2, 4, 3);
  uint2 at = tid.xy & 3;
  color[at] = color[at] + float4(1.0, 0.0, 0.0, 0.0);
}
