// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-enable-uniform-buffer-unsized-array %s -spirv 2>&1 | FileCheck %s

// L4: VK_EXT_shader_uniform_buffer_unsized_array only relaxes *uniform buffer*
// blocks, and the Vulkan SPIR-V environment keeps rejecting an unsized array in
// the PushConstant storage class, so a push constant block carrying the
// ConstantBuffer<T> with an unsized member is refused here instead of producing
// a module the validator would reject.

struct Data {
  float scale;
  float values[];
};

[[vk::push_constant]] ConstantBuffer<Data> data;
RWStructuredBuffer<float> results;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  results[tid.x] = data.values[tid.x] * data.scale;
}

// CHECK:      error: an unsized array member cannot be used in a push constant block; VK_EXT_shader_uniform_buffer_unsized_array only applies to uniform buffers (ConstantBuffer)
// CHECK-NEXT: ConstantBuffer<Data> data;
// CHECK-NOT:  error:
// CHECK:      ^
