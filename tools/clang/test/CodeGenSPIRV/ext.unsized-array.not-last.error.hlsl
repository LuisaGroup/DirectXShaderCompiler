// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-enable-uniform-buffer-unsized-array %s -spirv 2>&1 | FileCheck %s

// L4: an unsized array member must be the last member of its struct. A member
// declared after it has no defined offset, so the frontend rejects it and there
// is no second, generic "field has incomplete type" diagnostic behind it.

struct Data {
  float values[];
  float scale;
};

ConstantBuffer<Data> data;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  data.scale = data.values[tid.x];
}

// CHECK:      error: a member of type 'float' follows an unsized array member; an unsized array must be the last member of its struct
// CHECK-NEXT: float scale;
// CHECK-NOT:  error:
// CHECK:      ^
