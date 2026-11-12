// RUN: %dxc -T ps_6_0 -E main -HV 2021 -fspv-extension=SPV_QCOM_tile_shading %s -spirv | FileCheck %s

// G30/L6 gate: the feature survives the shipped post-processing (legalization,
// spirv-opt and capability trimming) and the resulting module still validates.
//
// This is the same shader as qcom.tile-shading.hlsl without -fcgl, so CodeGen
// runs the optimizer before it writes the module. Two things can go wrong only
// here, and neither is visible in the -fcgl gate:
//
//  - TileAttachmentQCOM is a storage class the optimizer never sees in a
//    conventional module. A pass that assumes UniformConstant for an image
//    variable, or a dead-code pass that does not know the storage class, would
//    drop the variable or rewrite the access; the CHECK lines below require the
//    variable, its pointer type and both image accesses to still be there.
//  - capability trimming ("SPIR-V capability trimming: ...") recomputes
//    OpCapability from what the module uses. If it does not see the storage
//    class, the three built-ins or the execution mode as users of
//    TileShadingQCOM, it removes the capability and the module becomes invalid.
//    The capability and the extension are therefore checked here as well, and a
//    failed validation is fatal (no -Vd).
//
// The numbers are the same as in qcom.tile-shading.hlsl: TileShadingQCOM = 4495,
// TileAttachmentQCOM = 4491, TileOffsetQCOM = 4492, TileDimensionQCOM = 4493,
// TileApronSizeQCOM = 4494, NonCoherentTileAttachmentReadQCOM = 4489.

// L1 after the optimizer: still exactly one capability and one extension. The
// optimizer rewrites the header, so CHECK-NOT runs are anchored around them.
// CHECK:      OpCapability Shader
// CHECK:      OpCapability TileShadingQCOM
// CHECK-NOT:  OpCapability TileShadingQCOM
// CHECK:      OpExtension "SPV_QCOM_tile_shading"
// CHECK-NOT:  OpExtension "SPV_QCOM_tile_shading"
// CHECK:      OpMemoryModel Logical GLSL450

// L2 after the optimizer: the entry point still carries the execution mode and
// still passes the three built-ins as interface variables.
// CHECK:      OpEntryPoint Fragment %main "main"
// CHECK:      OpExecutionMode %main NonCoherentTileAttachmentReadQCOM

// L2 after the optimizer: the built-ins are still decorated, Flat and readable.
// CHECK-DAG:  OpDecorate %[[OFFSET:[0-9]+]] BuiltIn TileOffsetQCOM
// CHECK-DAG:  OpDecorate %[[OFFSET]] Flat
// CHECK-DAG:  OpDecorate %[[DIM:[0-9]+]] BuiltIn TileDimensionQCOM
// CHECK-DAG:  OpDecorate %[[DIM]] Flat
// CHECK-DAG:  OpDecorate %[[APRON:[0-9]+]] BuiltIn TileApronSizeQCOM
// CHECK-DAG:  OpDecorate %[[APRON]] Flat
// CHECK-DAG:  OpDecorate %color DescriptorSet 0
// CHECK-DAG:  OpDecorate %color Binding 0

// L2 after the optimizer: the tile attachment keeps the TileAttachmentQCOM
// storage class, and the reads and writes are still OpImageRead / OpImageWrite
// on that variable.
// CHECK:      %type_2d_image = OpTypeImage %float 2D 2 0 0 2 Rgba32f
// CHECK:      %[[IMG_PTR:[0-9a-zA-Z_]+]] = OpTypePointer TileAttachmentQCOM %type_2d_image
// CHECK:      %color = OpVariable %[[IMG_PTR]] TileAttachmentQCOM
// CHECK-NOT:  %color = OpVariable %{{[0-9a-zA-Z_]+}} UniformConstant
// CHECK:      %{{[0-9]+}} = OpLoad %type_2d_image %color
// CHECK-NEXT: %{{[0-9]+}} = OpImageRead %v4float
// CHECK:      OpImageWrite %{{[0-9]+}} %{{[0-9]+}} %{{[0-9]+}} None

#include <vk/qcom/tile_shading.h>

[[vk::binding(0, 0)]]
[[vk::ext_storage_class(vk::qcom::StorageClassTileAttachmentQCOM)]]
vk::qcom::TileAttachment2D<float4> color;

float4 main(float4 pos : SV_Position) : SV_Target {
  vk::ext_execution_mode(
      vk::qcom::ExecutionModeNonCoherentTileAttachmentReadQCOM);
  uint2 origin = vk::qcom::TileOffset();
  uint3 dimension = vk::qcom::TileDimension();
  uint2 apron = vk::qcom::TileApronSize();
  uint2 at = uint2(pos.xy) - origin;
  float4 value = color[origin + at];
  color[origin + at + apron.xy] = value + float4(1.0, 0.0, 0.0, 0.0);
  return value + float4(float(dimension.z), 0.0, 0.0, 0.0);
}
