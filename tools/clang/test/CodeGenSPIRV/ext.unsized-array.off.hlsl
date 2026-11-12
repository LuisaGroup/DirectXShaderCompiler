// RUN: not %dxc -T cs_6_0 -E main -fcgl %s -spirv 2>&1 | FileCheck %s

// L5: without -fspv-enable-uniform-buffer-unsized-array the construct is
// rejected by the frontend exactly as before, so the default output of every
// existing shader is unchanged. The note names the flag (and through it
// VK_EXT_shader_uniform_buffer_unsized_array), because an unsized array member
// is otherwise only a missing array dimension.

struct Data {
  float scale;
  float values[];
};

ConstantBuffer<Data> data;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint i = tid.x;
  data.scale = data.values[i];
}

// CHECK: error: array dimensions of struct/class members must be explicit
// CHECK-NEXT: float values[];
// CHECK: note: unsized arrays in uniform buffer blocks require -fspv-enable-uniform-buffer-unsized-array (VK_EXT_shader_uniform_buffer_unsized_array)
