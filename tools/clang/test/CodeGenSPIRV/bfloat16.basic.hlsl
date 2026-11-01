// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2018 -fcgl -Vd %s | FileCheck %s

// Basic lowering of bfloat16_t scalars, vectors and matrices to
// OpTypeFloat 16 with the BFloat16KHR encoding from SPV_KHR_bfloat16.
// The extension and capability are emitted, but the Float16 capability and
// the 16-bit stage I/O capabilities must NOT be requested for bfloat16_t.

// CHECK: OpCapability BFloat16TypeKHR
// CHECK: OpExtension "SPV_KHR_bfloat16"
// CHECK-NOT: OpCapability Float16
// CHECK-NOT: OpCapability StorageInputOutput16

// CHECK: %bfloat16 = OpTypeFloat 16 BFloat16KHR
// A plain (unencoded) 16-bit float type must not be generated:
// CHECK-NOT: OpTypeFloat 16{{$}}
// CHECK: %v2bfloat16 = OpTypeVector %bfloat16 2
// CHECK: %v3bfloat16 = OpTypeVector %bfloat16 3
// CHECK: %v4bfloat16 = OpTypeVector %bfloat16 4
// CHECK: %mat2v2bfloat16 = OpTypeMatrix %v2bfloat16 2

[numthreads(1, 1, 1)]
void main() {
  bfloat16_t s;
  bfloat16_t2 v2;
  bfloat16_t3 v3;
  bfloat16_t4 v4;
  bfloat16_t2x2 m;

  // CHECK: %s = OpVariable %_ptr_Function_bfloat16 Function
  // CHECK: %v2 = OpVariable %_ptr_Function_v2bfloat16 Function
  // CHECK: %v3 = OpVariable %_ptr_Function_v3bfloat16 Function
  // CHECK: %v4 = OpVariable %_ptr_Function_v4bfloat16 Function
  // CHECK: %m = OpVariable %_ptr_Function_mat2v2bfloat16 Function

  // Scalar load/store.
  // CHECK: [[ld:%[0-9]+]] = OpLoad %bfloat16 %s
  // CHECK-NEXT: OpStore %s [[ld]]
  s = s;

  s = bfloat16_t(1.0);
  v2 = bfloat16_t2(s, s);
  v3 = bfloat16_t3(v2.xy, s);
  v4 = bfloat16_t4(v3.xyz, s);
  m._11 = s;
  m._22 = v4.w;
}
