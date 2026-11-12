// RUN: %dxc -T cs_6_0 -E main -fspv-enable-uniform-buffer-unsized-array %s -spirv | FileCheck %s

// L6: the same uniform buffer block without -fcgl, i.e. after HLSL legalization,
// the optimizer pass list and capability trimming. Two things can only go wrong
// here: the optimizer could drop or rewrite the element accesses into the
// runtime array, and capability trimming could decide that the block needs a
// capability that DXC did not request. Neither happens, and the module still
// validates (DXC validates every module it emits; there is no -Vd here).
//
// The extension adds no capability, so after trimming the module keeps exactly
// the capability a plain compute shader with a structured buffer needs.

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
  uint i = tid.x % count.n;
  results[tid.x] = data.values[i] * data.scale;
}

// CHECK:      OpCapability Shader
// CHECK-NOT:  OpCapability
// CHECK:      OpMemoryModel Logical GLSL450
// CHECK:      OpEntryPoint GLCompute

// The block survives: still a Block-decorated Uniform struct whose last member
// is an OpTypeRuntimeArray with the std140 stride of a float.
// CHECK:      OpDecorate [[RTA:%[_a-zA-Z0-9]+]] ArrayStride 16
// CHECK:      OpMemberDecorate [[BLOCK:%[_a-zA-Z0-9]+]] 1 Offset 16
// CHECK:      OpDecorate [[BLOCK]] Block
// CHECK:      [[RTA]] = OpTypeRuntimeArray %float
// CHECK:      [[BLOCK]] = OpTypeStruct %float [[RTA]]
// CHECK:      [[VAR:%[_a-zA-Z0-9]+]] = OpVariable {{%[_a-zA-Z0-9]+}} Uniform

// The optimizer folds the member selection and the dynamic index into a single
// access chain (%int_1 selects "values", the runtime index selects the element);
// it must still be a Uniform pointer to the element type.
// CHECK:      [[IDX:%[_a-zA-Z0-9]+]] = OpUMod %uint
// CHECK:      OpAccessChain %_ptr_Uniform_float [[VAR]] %int_1 [[IDX]]
