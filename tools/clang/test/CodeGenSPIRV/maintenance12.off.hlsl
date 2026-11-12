// RUN: %dxc -T vs_6_0 -E pcConstantIndex -fcgl -spirv -fspv-target-env=vulkan1.3 %s | FileCheck %s --check-prefix=PC
// RUN: %dxc -T vs_6_0 -E cbNonUniformIndex -fcgl -spirv -fspv-target-env=vulkan1.3 %s | FileCheck %s --check-prefix=CB

// G33/L5: off-path identity, in the two directions that matter for maintenance12.
//
// VK_KHR_maintenance12 has no switch of its own - it is a Vulkan *device*
// extension whose only SPIR-V-visible effect is whether a non-uniform index into
// a PushConstant variable is allowed to be there at all, and DXC already emits
// the encoding. There is therefore nothing to turn on, and this file states the
// "off" half explicitly, twice:
//
//  PC - an ordinary push-constant access. The block is declared exactly as in the
//       maintenance12 tests, but every index is a literal. With no
//       NonUniformResourceIndex() in the shader the module must be what it always
//       was: no NonUniform decoration anywhere, no ShaderNonUniform capability and
//       no SPV_EXT_descriptor_indexing extension. Declaring a push-constant block
//       must not, by itself, pull any of that in.
//
//  CB - the classic path, unchanged. A ConstantBuffer<> (Uniform storage) indexed
//       with NonUniformResourceIndex() is the pre-existing behaviour this feature
//       must not disturb: the marking still reaches the Uniform-storage access
//       chain, and the module still has exactly one ShaderNonUniform capability
//       and one SPV_EXT_descriptor_indexing extension - no maintenance12 spelling,
//       because there is none to emit. This is the same pattern the existing
//       intrinsics.nonuniform.* and sm6_6.descriptorheap.ext.nonuniform.* tests
//       pin; they are deliberately left unmodified.

//  pcConstantIndex - the block is still a plain PushConstant variable and
//  nothing in the header changes because of it.
// PC:      OpCapability Shader{{$}}
// PC-NOT:  OpCapability ShaderNonUniform
// PC-NOT:  OpExtension "SPV_EXT_descriptor_indexing"
// PC:      OpMemoryModel Logical GLSL450
// PC-NOT:  OpDecorate {{%[0-9]+}} NonUniform
// PC:      %int = OpTypeInt 32 1
// PC:      %pcData = OpVariable %_ptr_PushConstant_type_PushConstant_Data PushConstant
// PC:      [[A:%[0-9]+]] = OpAccessChain %_ptr_PushConstant__arr_v4float_uint_8 %pcData %int_0
// PC:      {{%[0-9]+}} = OpAccessChain %_ptr_PushConstant_v4float [[A]] %int_3
// PC:      [[B:%[0-9]+]] = OpAccessChain %_ptr_PushConstant__arr_v4float_uint_4 %pcData %int_1 %int_2 %int_0
// PC:      {{%[0-9]+}} = OpAccessChain %_ptr_PushConstant_v4float [[B]] %int_1
// PC-NOT:  NonUniform
// PC-NOT:  maintenance12
// PC-NOT:  OpAccessChain
// PC:      OpFunctionEnd

//  cbNonUniformIndex - the classic constant-buffer path, decoration included,
//  unchanged.
// CB:      OpCapability Shader{{$}}
// CB-NEXT: OpCapability ShaderNonUniform
// CB-NOT:  OpCapability ShaderNonUniform
// CB:      OpExtension "SPV_EXT_descriptor_indexing"
// CB-NOT:  maintenance12
// CB:      OpMemoryModel Logical GLSL450
// CB-NOT:  OpDecorate {{%[0-9]+}} NonUniform
// CB:      OpDecorate %type_ConstantBuffer_Data Block
// CB-NEXT: OpDecorate [[IDX:%[0-9]+]] NonUniform
// CB-NEXT: OpDecorate [[AC:%[0-9]+]] NonUniform
// CB-NEXT: OpDecorate [[VAL:%[0-9]+]] NonUniform
// CB-NOT:  OpDecorate {{%[0-9]+}} NonUniform
// CB:      %int = OpTypeInt 32 1
// CB:      [[ARR:%[0-9]+]] = OpAccessChain %_ptr_Uniform__arr_v4float_uint_8 %cbData %int_0
// CB:      [[IDX]] = OpCopyObject %uint {{%[0-9]+}}
// CB:      [[AC]] = OpAccessChain %_ptr_Uniform_v4float [[ARR]] [[IDX]]
// CB:      [[VAL]] = OpLoad %v4float [[AC]]
// CB:      OpFunctionEnd

struct PerMaterial {
  float4 values[4];
};

struct Data {
  float4      values[8];
  PerMaterial materials[4];
};

[[vk::push_constant]] Data pcData;
ConstantBuffer<Data> cbData;

// An ordinary access: literals only, so the module is the one DXC has always
// emitted for a push-constant block.
float4 pcConstantIndex() : SV_Position {
  return pcData.values[3] + pcData.materials[2].values[1];
}

// The classic path: a Uniform-storage block with a declared non-uniform index.
float4 cbNonUniformIndex(uint index : ID) : SV_Position {
  return cbData.values[NonUniformResourceIndex(index)];
}
