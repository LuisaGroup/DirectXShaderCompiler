// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-enable-uniform-buffer-unsized-array %s -spirv | FileCheck %s

// VK_EXT_shader_uniform_buffer_unsized_array: an unsized array is allowed as the
// last member of a uniform buffer block, and lowers to OpTypeRuntimeArray in a
// Block-decorated struct in the Uniform storage class.
//
// The Vulkan extension adds no SPIR-V instruction, so there is no
// SPV_EXT_shader_uniform_buffer_unsized_array OpExtension string and no
// capability: -fspv-extension cannot express it, which is why the relaxation is
// an opt-in flag (-fspv-enable-uniform-buffer-unsized-array) instead of a target
// environment or an extension. The capability block below is byte-identical to
// the one any other compute module gets.

struct Data {
  float scale;
  float values[];
};

struct Count {
  uint n;
};

ConstantBuffer<Data> data;
ConstantBuffer<Count> count;
RWStructuredBuffer<float> results;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // The length of the unsized array is only known at runtime from the size of
  // the bound buffer object, normally
  // max((bufferSize - offsetOfArray) / arrayStride, 0), so the application has
  // to pass it in a separate uniform buffer member: OpArrayLength is prohibited
  // on this array and .Length is a compile error.
  uint i = tid.x % count.n;
  // A runtime index into the unsized member: an OpAccessChain into the runtime
  // array in Uniform storage, followed by a dynamic index.
  results[tid.x] = data.values[i] * data.scale;
}

// L1: no new capability and no OpExtension. The negatives are anchored between
// two positive matches so that they cover exactly the module header: the
// extension reuses OpTypeRuntimeArray, so nothing may be added here.
// CHECK:      OpCapability Shader
// CHECK-NOT:  OpCapability RuntimeDescriptorArray
// CHECK-NOT:  OpCapability UniformAndStorageBuffer8BitAccess
// CHECK-NOT:  OpCapability StorageBuffer8BitAccess
// CHECK-NOT:  OpCapability ShaderNonUniform
// CHECK-NOT:  OpExtension "SPV_EXT_shader_uniform_buffer_unsized_array"
// CHECK-NOT:  OpExtension "SPV_KHR_untyped_pointers"
// CHECK:      OpMemoryModel Logical GLSL450

// L0: the block is a compute-stage interface block, i.e. the unsized member
// reached the module at all.
// CHECK:      OpEntryPoint GLCompute
// CHECK:      LocalSize 64 1 1

// L2: the block is a Uniform-storage-class Block whose last member is an
// OpTypeRuntimeArray with the std140 stride of a float (16 bytes), placed right
// after the sized member (offset 16).
// CHECK:      OpDecorate [[RTA:%[_a-zA-Z0-9]+]] ArrayStride 16
// CHECK:      OpMemberDecorate [[BLOCK:%[_a-zA-Z0-9]+]] 0 Offset 0
// CHECK:      OpMemberDecorate [[BLOCK]] 1 Offset 16
// CHECK:      OpDecorate [[BLOCK]] Block
// CHECK-NOT:  OpDecorate [[BLOCK]] BufferBlock
// CHECK:      [[RTA]] = OpTypeRuntimeArray %float
// CHECK:      [[BLOCK]] = OpTypeStruct %float [[RTA]]
// CHECK:      [[PTR:%[_a-zA-Z0-9]+]] = OpTypePointer Uniform [[BLOCK]]
// CHECK:      [[VAR:%[_a-zA-Z0-9]+]] = OpVariable [[PTR]] Uniform

// L2: indexing the unsized member. The first access chain selects the last
// member (index 1) and yields a pointer to the runtime array; the second one
// applies the dynamic index.
// CHECK:      OpAccessChain %_ptr_Uniform__runtimearr_float [[VAR]] %int_1
// CHECK:      [[IDX:%[_a-zA-Z0-9]+]] = OpLoad %uint
// CHECK:      OpAccessChain %_ptr_Uniform_float {{%[_a-zA-Z0-9]+}} [[IDX]]
