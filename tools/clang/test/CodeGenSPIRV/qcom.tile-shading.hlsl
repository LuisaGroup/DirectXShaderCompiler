// RUN: %dxc -T ps_6_0 -E main -fcgl -HV 2021 -fspv-extension=SPV_QCOM_tile_shading %s -spirv | FileCheck %s

// G30/L1 + G30/L2 gates for SPV_QCOM_tile_shading: the capability, the
// extension, the TileAttachmentQCOM storage class, the three tile built-ins and
// the NonCoherentTileAttachmentReadQCOM execution mode.
//
// The surface is <vk/qcom/tile_shading.h>:
//   [[vk::ext_storage_class(vk::qcom::StorageClassTileAttachmentQCOM)]]
//   vk::qcom::TileAttachment2D<float4> color;   ->  OpVariable TileAttachmentQCOM
//   vk::qcom::TileOffset()                      ->  OpLoad BuiltIn TileOffsetQCOM
//   vk::qcom::TileDimension()                   ->  OpLoad BuiltIn TileDimensionQCOM
//   vk::qcom::TileApronSize()                   ->  OpLoad BuiltIn TileApronSizeQCOM
//   vk::ext_execution_mode(
//       vk::qcom::ExecutionModeNonCoherentTileAttachmentReadQCOM)
//                             ->  OpExecutionMode ... NonCoherentTileAttachmentReadQCOM
//
// The numbers are the ones
// external/SPIRV-Headers/include/spirv/unified1/spirv.core.grammar.json assigns:
// TileShadingQCOM = 4495, TileAttachmentQCOM = 4491, TileOffsetQCOM = 4492,
// TileDimensionQCOM = 4493, TileApronSizeQCOM = 4494,
// NonCoherentTileAttachmentReadQCOM = 4489. Every mnemonic this test asserts is
// the one SPIRV-Tools decodes, so a wrong number would print a different name or
// fail validation - no test here passes -Vd.
//
// The storage class is the whole feature, so this file asserts it by name and
// rules out the storage classes a fallback lowering would plausibly produce.
// SPIRV-Tools requires DescriptorSet and Binding on a TileAttachmentQCOM
// variable ("Any variable in the TileAttachmentQCOM Storage Class must be
// decorated with DescriptorSet and Binding") and a 2D image whose Sampled
// operand is 1 or 2, so the OpTypeImage line is part of the gate too.
//
// The compute half (TileShadingRateQCOM with its three rate operands) is
// qcom.tile-shading.rate.hlsl; the off path is qcom.tile-shading.off.hlsl; the
// post-optimizer path is qcom.tile-shading.opt.hlsl.

// L1: exactly one OpCapability TileShadingQCOM and exactly one
// OpExtension "SPV_QCOM_tile_shading". The CHECK-NOT runs are anchored between
// the surrounding module-level lines so that a duplicate fails here.
// CHECK:      OpCapability Shader
// CHECK:      OpCapability TileShadingQCOM
// CHECK-NOT:  OpCapability TileShadingQCOM
// CHECK:      OpExtension "SPV_QCOM_tile_shading"
// CHECK-NOT:  OpExtension "SPV_QCOM_tile_shading"
// CHECK:      OpMemoryModel Logical GLSL450

// L2: the entry point declares the non-coherent read mode, once, and without
// operands (the mode has none). Both tile-shading execution modes are optional
// and independent, so the rate mode must not appear in this fragment shader.
// CHECK:      OpEntryPoint Fragment
// CHECK:      OpExecutionMode %main NonCoherentTileAttachmentReadQCOM
// CHECK-NOT:  OpExecutionMode %main NonCoherentTileAttachmentReadQCOM
// CHECK-NOT:  OpExecutionMode %main TileShadingRateQCOM

// L2: the three tile built-ins are Input variables decorated with their BuiltIn
// and Flat (SPIRV-Tools requires Flat on an integer stage input of a fragment
// shader), and the tile attachment carries the descriptor decorations the
// extension requires.
// CHECK-DAG:  OpDecorate %[[OFFSET:[0-9]+]] BuiltIn TileOffsetQCOM
// CHECK-DAG:  OpDecorate %[[OFFSET]] Flat
// CHECK-DAG:  OpDecorate %[[DIM:[0-9]+]] BuiltIn TileDimensionQCOM
// CHECK-DAG:  OpDecorate %[[DIM]] Flat
// CHECK-DAG:  OpDecorate %[[APRON:[0-9]+]] BuiltIn TileApronSizeQCOM
// CHECK-DAG:  OpDecorate %[[APRON]] Flat
// CHECK-DAG:  OpDecorate %color DescriptorSet 0
// CHECK-DAG:  OpDecorate %color Binding 0

// L2: a 2D storage image (Dim 2D, MS 0, Sampled 2) in the TileAttachmentQCOM
// storage class. The pointer type is %-named after the storage class, which is
// the anchor that a wrong storage class cannot satisfy.
// CHECK:      %type_2d_image = OpTypeImage %float 2D 2 0 0 2 Rgba32f
// CHECK:      %[[IMG_PTR:[0-9a-zA-Z_]+]] = OpTypePointer TileAttachmentQCOM %type_2d_image

// L2: the tile attachment variable and the three built-in variables, in the
// order CodeGen writes them.
// CHECK:      %color = OpVariable %[[IMG_PTR]] TileAttachmentQCOM
// The near misses: a fallback that lowered the tile attachment to an ordinary
// resource, a private global or a storage buffer would produce one of these.
// CHECK-NOT:  %color = OpVariable %{{[0-9a-zA-Z_]+}} UniformConstant
// CHECK-NOT:  %color = OpVariable %{{[0-9a-zA-Z_]+}} Private
// CHECK-NOT:  %color = OpVariable %{{[0-9a-zA-Z_]+}} StorageBuffer
// CHECK:      %[[OFFSET]] = OpVariable %{{[0-9a-zA-Z_]+}} Input
// CHECK:      %[[DIM]] = OpVariable %{{[0-9a-zA-Z_]+}} Input
// CHECK:      %[[APRON]] = OpVariable %{{[0-9a-zA-Z_]+}} Input

// L2: reading and writing the tile attachment lowers to OpImageRead /
// OpImageWrite on the TileAttachmentQCOM variable, not to OpLoad/OpStore of the
// pixels (the shape a buffer-backed fallback would produce).
// CHECK:      %{{[0-9]+}} = OpLoad %v2uint %[[OFFSET]]
// CHECK:      %{{[0-9]+}} = OpLoad %v3uint %[[DIM]]
// CHECK:      %{{[0-9]+}} = OpLoad %v2uint %[[APRON]]
// CHECK:      %{{[0-9]+}} = OpLoad %type_2d_image %color
// CHECK-NEXT: %{{[0-9]+}} = OpImageRead %v4float
// CHECK:      OpImageWrite %{{[0-9]+}} %{{[0-9]+}} %{{[0-9]+}} None
// CHECK-NOT:  OpStore %color

#include <vk/qcom/tile_shading.h>

[[vk::binding(0, 0)]]
[[vk::ext_storage_class(vk::qcom::StorageClassTileAttachmentQCOM)]]
vk::qcom::TileAttachment2D<float4> color;

float4 main(float4 pos : SV_Position) : SV_Target {
  // The non-coherent read mode is a module-level declaration that a fragment
  // entry point makes once; where the call sits inside the body does not matter.
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
