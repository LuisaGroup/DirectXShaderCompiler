// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-enable-uniform-buffer-unsized-array %s -spirv 2>&1 | FileCheck %s

// L4: the element type of a structured buffer is itself wrapped in an
// OpTypeRuntimeArray, so an unsized array member inside it would be a nested
// runtime array - which no storage class allows. The extension only applies to
// uniform buffer blocks, so this is rejected with the same message as any other
// use of such a struct outside a ConstantBuffer.

struct Data {
  float scale;
  float values[];
};

StructuredBuffer<Data> buffers;
RWStructuredBuffer<float> results;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  results[tid.x] = buffers[tid.x].values[tid.x] * buffers[tid.x].scale;
}

// CHECK:      error: an unsized array member is not supported in a structured buffer element type; VK_EXT_shader_uniform_buffer_unsized_array only applies to uniform buffers (ConstantBuffer)
// CHECK-NEXT: StructuredBuffer<Data> buffers;
// CHECK-NOT:  error:
// CHECK:      ^
