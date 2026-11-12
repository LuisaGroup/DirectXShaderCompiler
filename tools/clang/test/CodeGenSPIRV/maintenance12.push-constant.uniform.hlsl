// RUN: %dxc -T vs_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.3 %s | FileCheck %s

// G33/L2.uniform: the negative half of the decoration gate, for a push-constant
// block whose indices are uniform.
//
// maintenance12 makes a divergent push-constant index *permitted*; it does not
// make one appear. Nothing may be decorated here:
//  * a constant index (%int_2, and the literal member/element indices of the
//    nested access) is trivially uniform;
//  * `index & 3` is derived from a per-invocation value but is not *declared*
//    divergent - HLSL has no uniformity inference, so DXC must not guess. The
//    eager form of this bug (decorating anything that came from an input) is a
//    silent performance bug rather than a validation failure: drivers take the
//    non-uniform path for access chains marked NonUniform, and nothing in
//    spirv-val would complain.
// Consequently the module also carries no ShaderNonUniform capability and no
// SPV_EXT_descriptor_indexing extension: those are added *only* because a
// NonUniform decoration exists (CapabilityVisitor, on the decoration), so their
// absence here is the check that the decoration really is absent everywhere and
// not merely outside the checked window.
//
// Every CHECK-NOT is bracketed by two CHECKs over a region that can contain the
// excluded text - the whole annotation block for the first pair, the whole
// instruction stream for the second.

// CHECK:      OpCapability Shader{{$}}
// CHECK-NOT:  OpCapability ShaderNonUniform
// CHECK-NOT:  OpExtension "SPV_EXT_descriptor_indexing"
// CHECK:      OpMemoryModel Logical GLSL450

// The annotation block, from OpMemoryModel to the first type declaration: no id
// in it may carry NonUniform.
// CHECK-NOT: OpDecorate {{%[0-9]+}} NonUniform
// CHECK:     %int = OpTypeInt 32 1

struct PerMaterial {
  float4 values[4];
};

struct PushData {
  float4      values[8];
  PerMaterial materials[4];
};

// CHECK: %pc = OpVariable %_ptr_PushConstant_type_PushConstant_PushData PushConstant
[[vk::push_constant]] PushData pc;

float4 main(uint index : ID) : SV_Position {
  return
  // A constant index into the block's own array.
  // CHECK:      [[CARR:%[0-9]+]] = OpAccessChain %_ptr_PushConstant__arr_v4float_uint_8 %pc %int_0
  // CHECK-NEXT: {{%[0-9]+}} = OpAccessChain %_ptr_PushConstant_v4float [[CARR]] %int_2
      pc.values[2] +
      // A constant member/element index into the struct-of-arrays, and a
      // per-invocation index that was never wrapped in NonUniformResourceIndex().
      // The index reaches the access chain as the bare OpBitwiseAnd result: no
      // OpCopyObject is introduced, which is what an unwrapped index looks like.
      // CHECK:      [[NARR:%[0-9]+]] = OpAccessChain %_ptr_PushConstant__arr_v4float_uint_4 %pc %int_1 %int_1 %int_0
      // CHECK:      [[IDX:%[0-9]+]] = OpLoad %uint %index
      // CHECK:      [[MASKED:%[0-9]+]] = OpBitwiseAnd %uint [[IDX]] %uint_3
      // CHECK:      {{%[0-9]+}} = OpAccessChain %_ptr_PushConstant_v4float [[NARR]] [[MASKED]]
      pc.materials[1].values[index & 3];
  // Anchored negative over the whole instruction stream: no decoration marker,
  // no maintenance12 spelling and no NonUniformResourceIndex copy may appear.
  // CHECK-NOT: NonUniform
  // CHECK-NOT: maintenance12
  // CHECK-NOT: OpCopyObject
  // CHECK-NOT: OpAccessChain
  // CHECK: OpFunctionEnd
}
