// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-enable-uniform-buffer-unsized-array %s -spirv 2>&1 | FileCheck %s

// L4: the accessible length of the unsized array is a runtime property of the
// bound buffer object, and VK_EXT_shader_uniform_buffer_unsized_array prohibits
// OpArrayLength on it - so .Length (which for a sized array becomes a constant
// length) is a hard error, not a zero or a runtime query. The application has to
// pass max((bufferSize - offsetOfArray) / arrayStride, 0) in a separate
// uniform buffer member.

struct Data {
  float scale;
  float values[];
};

ConstantBuffer<Data> data;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint n = data.values.Length;
  data.scale = data.values[tid.x % n];
}

// CHECK:      error: cannot query the length of an unsized array: VK_EXT_shader_uniform_buffer_unsized_array prohibits OpArrayLength; pass the length as a separate uniform buffer member
// CHECK-NEXT: uint n = data.values.Length;
// CHECK-NOT:  error:
// CHECK:      ^
