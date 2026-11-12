// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-enable-uniform-buffer-unsized-array %s -spirv 2>&1 | FileCheck %s

// L4: the Vulkan extension states that an unsized array in a uniform buffer
// block "cannot be passed as arguments to functions". The reason is visible in
// the SPIR-V: CodeGen copies a resource parameter into a Function-scope
// temporary, and a runtime array cannot live in Function storage. The same
// restriction covers a local copy of the block, a block returned from a function
// and an array of such blocks.

struct Data {
  float scale;
  float values[];
};

ConstantBuffer<Data> data;
RWStructuredBuffer<float> results;

float fetch(ConstantBuffer<Data> block, uint i) {
  return block.values[i] * block.scale;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  results[tid.x] = fetch(data, tid.x);
}

// CHECK:      error: a constant buffer with an unsized array member cannot be passed as a function argument; VK_EXT_shader_uniform_buffer_unsized_array does not allow the block to be copied
// CHECK-NEXT: float fetch(ConstantBuffer<Data> block, uint i) {
// CHECK-NOT:  error:
// CHECK:      ^
