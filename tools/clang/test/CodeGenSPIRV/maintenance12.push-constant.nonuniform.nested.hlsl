// RUN: %dxc -T vs_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.3 %s | FileCheck %s

// G33/L2.array: a non-uniform index into a nested member of a [[vk::push_constant]]
// block - a struct-of-arrays, which is how a per-material table is normally
// declared. maintenance12 is about "values within a variable with a PushConstant
// storage class", so the member depth is irrelevant to the permission; what this
// file pins is the *propagation rule* that can regress silently: the decoration
// has to sit on the access chain whose index is divergent, and only on that one.
//
// The shader indexes the outer array with a literal and the inner array with
// NonUniformResourceIndex(), so it produces two access chains: the outer one,
// whose indices are %int_1 %int_1 %int_0, and the inner one built from it with
// the marked index. The outer chain is defined first, so if NonUniformVisitor
// over-propagated and decorated it as well, its OpDecorate would be the first
// NonUniform line in the module and the enumerated ids below would shift - the
// body cross-checks then fail. That is the whole negative half of this gate, and
// it is the failure mode (over-decoration) that no validation error would report.
//
// The container member is `materials[1]` rather than `materials[NonUniform]` on
// purpose: with the outer index divergent as well, spirv-opt later folds both
// levels into one chain and the outer/inner distinction disappears. The
// pre-legalization module (-fcgl) is the only place the two chains are visible.

// CHECK:      OpCapability Shader{{$}}
// CHECK-NEXT: OpCapability ShaderNonUniform
// CHECK-NOT:  OpCapability ShaderNonUniform
// CHECK:      OpExtension "SPV_EXT_descriptor_indexing"
// CHECK-NOT:  maintenance12
// CHECK:      OpMemoryModel Logical GLSL450

// Still exactly three decorated ids: the marked index, the inner (divergent)
// access chain and the value loaded through it.
// CHECK-NOT:  OpDecorate {{%[0-9]+}} NonUniform
// CHECK:      OpDecorate %type_PushConstant_PushData Block
// CHECK-NEXT: OpDecorate [[IDX:%[0-9]+]] NonUniform
// CHECK-NEXT: OpDecorate [[AC:%[0-9]+]] NonUniform
// CHECK-NEXT: OpDecorate [[VAL:%[0-9]+]] NonUniform
// CHECK-NOT:  OpDecorate {{%[0-9]+}} NonUniform
// CHECK:      %int = OpTypeInt 32 1

struct PerMaterial {
  float4 values[4];
};

struct PushData {
  float4      values[8];
  PerMaterial materials[4];
};

// CHECK: %_ptr_PushConstant__arr_v4float_uint_4 = OpTypePointer PushConstant %_arr_v4float_uint_4
// CHECK: %_ptr_PushConstant_v4float = OpTypePointer PushConstant %v4float
// CHECK: %pc = OpVariable %_ptr_PushConstant_type_PushConstant_PushData PushConstant
[[vk::push_constant]] PushData pc;

float4 main(uint index : ID) : SV_Position {
  return
  // The outer chain: constant indices all the way (member 1, element 1, member 0),
  // so its id is not one of the decorated three and, because it is defined before
  // the marked index, it must not be the first NonUniform decoration either.
  // CHECK:      [[OUTER:%[0-9]+]] = OpAccessChain %_ptr_PushConstant__arr_v4float_uint_4 %pc %int_1 %int_1 %int_0
      // The inner chain is the one built from the marked index, and it is the one
      // that carries the decoration - a driver needs it on the chain, not only on
      // the loaded value.
      // CHECK: [[IDX]] = OpCopyObject %uint {{%[0-9]+}}
      // CHECK: [[AC]] = OpAccessChain %_ptr_PushConstant_v4float [[OUTER]] [[IDX]]
      // CHECK: [[VAL]] = OpLoad %v4float [[AC]]
      pc.materials[1].values[NonUniformResourceIndex(index)];
  // CHECK-NOT: NonUniform
  // CHECK-NOT: maintenance12
  // CHECK-NOT: OpAccessChain
  // CHECK: OpFunctionEnd
}
