// RUN: %dxc -T vs_6_0 -E main -spirv -fspv-target-env=vulkan1.3 %s | FileCheck %s

// G33/L6 + G33/L3: the push-constant NonUniform decoration after legalization,
// spirv-opt and capability trimming. No -fcgl, so the module asserted here is the
// final one; validation is left enabled, so a passing compile is itself the
// module-validity statement (spirv-val runs inside dxc with the
// before-HLSL-legalization flag off, i.e. on the module that is actually shipped).
//
// Two things can only go wrong on this path, and only this file catches them:
//  * the optimizer drops or rewrites the marking. The decorated OpCopyObject that
//    NonUniformResourceIndex() produces exists only to carry the decoration, so a
//    DCE pass that does not treat NonUniform as a use would delete it and leave the
//    access chain unmarked - a silently uniform-looking push-constant access on a
//    module whose index is divergent, which is exactly what maintenance12 permits
//    and what a pre-maintenance12 driver must not be handed;
//  * capability trimming removes ShaderNonUniform (or the
//    SPV_EXT_descriptor_indexing extension that defines it) because it is not
//    reachable from anything the pass understands.
//
// What the optimizer does to the shape, and why the assertions look like this: it
// folds the uniform outer index of the struct-of-arrays into a single access chain,
// so the two chains of the -fcgl nested test become one here, with the marked index
// last. It leaves the constant-indexed access next to it completely alone - no
// decoration, no marker - which is this file's negative control: the relaxation is
// per access chain, not per variable.
//
// Four ids are decorated, in definition order: the marked index, the access chain,
// the value loaded through it, and the OpFAdd that consumes that value. The last one
// is pre-existing generic propagation (NonUniformVisitor::visit(SpirvBinaryOp)), not
// anything maintenance12 adds, and it has to survive the optimizer as well because a
// consumer that reads the divergent value is divergent too.

// CHECK:      OpCapability Shader{{$}}
// CHECK-NEXT: OpCapability ShaderNonUniform
// CHECK-NOT:  OpCapability ShaderNonUniform
// CHECK:      OpExtension "SPV_EXT_descriptor_indexing"
// CHECK-NOT:  maintenance12
// CHECK:      OpMemoryModel Logical GLSL450
// CHECK-NOT:  OpDecorate {{%[0-9]+}} NonUniform
// CHECK:      OpDecorate %type_PushConstant_PushData Block
// CHECK-NEXT: OpDecorate [[IDX:%[0-9]+]] NonUniform
// CHECK-NEXT: OpDecorate [[AC:%[0-9]+]] NonUniform
// CHECK-NEXT: OpDecorate [[VAL:%[0-9]+]] NonUniform
// CHECK-NEXT: OpDecorate [[SUM:%[0-9]+]] NonUniform
// CHECK-NOT:  OpDecorate {{%[0-9]+}} NonUniform
// CHECK:      %int = OpTypeInt 32 1

struct PerMaterial {
  float4 values[4];
};

struct PushData {
  float4      values[8];
  PerMaterial materials[4];
};

[[vk::push_constant]] PushData pc;

float4 main(uint index : ID) : SV_Position {
  return
      // The marked index survives as a separate instruction - it is not folded
      // into a constant and not merged into the access chain's operand list as a
      // bare value, so the decoration still has an id to sit on. The index is read
      // from an input, so no pass can prove it uniform.
      // CHECK:      [[LOAD:%[0-9]+]] = OpLoad %uint %in_var_ID
      // CHECK:      [[IDX]] = OpCopyObject %uint [[LOAD]]
      // CHECK:      [[AC]] = OpAccessChain %_ptr_PushConstant_v4float %pc %int_1 %int_1 %int_0 [[IDX]]
      // CHECK:      [[VAL]] = OpLoad %v4float [[AC]]
      pc.materials[1].values[NonUniformResourceIndex(index)] +
      // The negative control: the same block, indexed with a literal, is still a
      // plain undecorated chain and still in the PushConstant storage class.
      // CHECK-NEXT: [[PLAIN:%[0-9]+]] = OpAccessChain %_ptr_PushConstant_v4float %pc %int_0 %int_3
      // CHECK-NEXT: [[PLAINVAL:%[0-9]+]] = OpLoad %v4float [[PLAIN]]
      // CHECK-NEXT: [[SUM]] = OpFAdd %v4float [[VAL]] [[PLAINVAL]]
      pc.values[3];
  // CHECK-NOT:  NonUniform
  // CHECK-NOT:  maintenance12
  // CHECK-NOT:  OpAccessChain
  // CHECK:      OpFunctionEnd
}
