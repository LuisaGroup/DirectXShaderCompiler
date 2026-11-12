// RUN: %dxc -T vs_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.3 %s | FileCheck %s

// G33/L0 + G33/L1 + G33/L2: a non-uniform index into a [[vk::push_constant]] block.
//
// VK_KHR_maintenance12 permits non-uniform indexing of values inside a variable
// with the PushConstant storage class. On the SPIR-V side that permission has
// exactly one representation: a NonUniform decoration on the access chain whose
// index is divergent, plus the ShaderNonUniform capability (and, for SPIR-V
// before 1.5, the SPV_EXT_descriptor_indexing extension) that makes the
// decoration legal. The Vulkan extension itself adds no instruction, no
// capability and no OpExtension string: there is no SPV_KHR_maintenance12 in the
// Khronos SPIR-V registry - checked against the vendored grammar
// (external/SPIRV-Headers v2026.08.0, whose only "maintenance" names are
// SPV_EXT_cooperative_matrix_maintenance1) - so
// -fspv-extension=SPV_KHR_maintenance12 is an "unknown SPIR-V extension" error
// on purpose, and nothing in the module header changes for maintenance12. This
// file therefore pins the one thing the feature is about: the decoration.
//
// HLSL marks a divergent index with NonUniformResourceIndex(). That is the only
// thing DXC treats as non-uniform - a plain per-invocation index is not marked,
// see maintenance12.push-constant.uniform.hlsl. The intrinsic is not restricted
// to resource indices: SemaHLSL accepts it around a plain uint, so a
// push-constant subscript is in range. The emitter lowers it to an OpCopyObject
// marked NonUniform (SpirvEmitter::processIntrinsicNonUniformResourceIndex),
// from which NonUniformVisitor::visit(SpirvAccessChain) propagates the marking
// to the access chain and thence to the load. There is no push-constant-specific
// code in NonUniformVisitor, and this file has to stay green if there never is.
//
// The decorated ids are enumerated instead of spot-checked: they are exactly the
// marked index, the access chain built from it and the value loaded through it,
// in that order, and no other id may be decorated before or after them. Each id
// captured from an OpDecorate is then matched against the instruction that
// defines it below, so a decoration that landed on the wrong instruction - only
// on the loaded value, say, which would leave the push-constant access itself
// unmarked - turns this file red.

// The capability that legalises the decoration, declared once. ShaderNonUniform
// is not new for maintenance12: descriptor indexing already needs it, which is
// why the extension that defines it is the pre-existing
// SPV_EXT_descriptor_indexing and not a maintenance12 spelling.
// CHECK:      OpCapability Shader{{$}}
// CHECK-NEXT: OpCapability ShaderNonUniform
// CHECK-NOT:  OpCapability ShaderNonUniform
// CHECK:      OpExtension "SPV_EXT_descriptor_indexing"
// CHECK-NOT:  maintenance12
// CHECK:      OpMemoryModel Logical GLSL450

// Exactly three ids are decorated, and they are the three consecutive decoration
// lines right after the block decoration, in definition order: the CHECK-NEXTs
// leave no room for a NonUniform on anything else (a decoration inserted before
// them shifts every captured id and the body cross-checks below fail), and the
// two negative checks bracket the block on both sides.
// CHECK-NOT:  OpDecorate {{%[0-9]+}} NonUniform
// CHECK:      OpDecorate %type_PushConstant_PushData Block
// CHECK-NEXT: OpDecorate [[IDX:%[0-9]+]] NonUniform
// CHECK-NEXT: OpDecorate [[AC:%[0-9]+]] NonUniform
// CHECK-NEXT: OpDecorate [[VAL:%[0-9]+]] NonUniform
// CHECK-NOT:  OpDecorate {{%[0-9]+}} NonUniform
// CHECK:      %int = OpTypeInt 32 1

struct PushData {
  float4 values[8];
};

// The block is a PushConstant-storage variable, and the pointer types used by the
// access chains below stay in the PushConstant storage class - a decoration on an
// access chain in some other storage class would be the cbuffer path, not this one.
// CHECK: %_ptr_PushConstant_type_PushConstant_PushData = OpTypePointer PushConstant %type_PushConstant_PushData
// CHECK: %_ptr_PushConstant__arr_v4float_uint_8 = OpTypePointer PushConstant %_arr_v4float_uint_8
// CHECK: %_ptr_PushConstant_v4float = OpTypePointer PushConstant %v4float
// CHECK: %pc = OpVariable %_ptr_PushConstant_type_PushConstant_PushData PushConstant
[[vk::push_constant]] PushData pc;

float4 main(uint index : ID) : SV_Position {
  return
  // The container chain that indexes member 0 with a constant is not divergent,
  // so it stays undecorated - the two CHECK-NOTs over the annotation block above
  // bracket it out.
  // CHECK:      [[ARR:%[0-9]+]] = OpAccessChain %_ptr_PushConstant__arr_v4float_uint_8 %pc %int_0
      // The decorated id is this access chain - the PushConstant-storage chain
      // whose index is the decorated id - and not merely the value it loads.
      // CHECK: [[IDX]] = OpCopyObject %uint {{%[0-9]+}}
      // CHECK: [[AC]] = OpAccessChain %_ptr_PushConstant_v4float [[ARR]] [[IDX]]
      // CHECK: [[VAL]] = OpLoad %v4float [[AC]]
      pc.values[NonUniformResourceIndex(index)];
  // Anchored negative over the tail of the module: no maintenance12 spelling may
  // appear anywhere, and no further push-constant access may be emitted.
  // CHECK-NOT: NonUniform
  // CHECK-NOT: maintenance12
  // CHECK-NOT: OpAccessChain
  // CHECK: OpFunctionEnd
}
