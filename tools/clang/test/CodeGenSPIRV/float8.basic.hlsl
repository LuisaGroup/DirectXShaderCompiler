// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl %s | FileCheck %s

// Basic lowering of float8_e4m3_t / float8_e5m2_t scalars, vectors and matrices
// to OpTypeFloat 8 with the Float8E4M3EXT / Float8E5M2EXT encoding from
// SPV_EXT_float8.
//
// Both encodings are exercised in one module on purpose: a single OpTypeFloat 8
// cannot distinguish a correct lowering from one that always selects E4M3.
//
// The capability and the extension are emitted exactly once, and no 8-bit
// integer storage capability (the type is a float) and no Float16 capability
// (the type is 8 bits) may be requested on their behalf.

// CHECK: OpCapability Float8EXT
// CHECK-NOT: OpCapability Float8EXT
// CHECK-NOT: OpCapability Float8CooperativeMatrixEXT
// CHECK-NOT: OpCapability Int8
// CHECK-NOT: OpCapability StorageBuffer8BitAccess
// CHECK-NOT: OpCapability UniformAndStorageBuffer8BitAccess
// CHECK-NOT: OpCapability StoragePushConstant8
// CHECK-NOT: OpCapability Float16
// CHECK-NOT: OpCapability BFloat16TypeKHR
// CHECK: OpExtension "SPV_EXT_float8"
// CHECK-NOT: OpExtension "SPV_EXT_float8"
// CHECK-NOT: OpExtension "SPV_KHR_16bit_storage"
// CHECK-NOT: OpExtension "SPV_KHR_bfloat16"

// CHECK: %fp8e4m3 = OpTypeFloat 8 Float8E4M3EXT
// CHECK: %fp8e5m2 = OpTypeFloat 8 Float8E5M2EXT
// A plain (unencoded) 8-bit float type must not be generated:
// CHECK-NOT: OpTypeFloat 8{{$}}
// CHECK: %v2fp8e4m3 = OpTypeVector %fp8e4m3 2
// CHECK: %v3fp8e4m3 = OpTypeVector %fp8e4m3 3
// CHECK: %v4fp8e5m2 = OpTypeVector %fp8e5m2 4
// CHECK: %mat2v2fp8e4m3 = OpTypeMatrix %v2fp8e4m3 2

[numthreads(1, 1, 1)]
void main() {
  float8_e4m3_t e4m3;
  float8_e5m2_t e5m2;
  float8_e4m3_t2 v2;
  float8_e4m3_t3 v3;
  float8_e5m2_t4 v4;
  float8_e4m3_t2x2 m;

  // CHECK: %e4m3 = OpVariable %_ptr_Function_fp8e4m3 Function
  // CHECK: %e5m2 = OpVariable %_ptr_Function_fp8e5m2 Function
  // CHECK: %v2 = OpVariable %_ptr_Function_v2fp8e4m3 Function
  // CHECK: %v3 = OpVariable %_ptr_Function_v3fp8e4m3 Function
  // CHECK: %v4 = OpVariable %_ptr_Function_v4fp8e5m2 Function
  // CHECK: %m = OpVariable %_ptr_Function_mat2v2fp8e4m3 Function

  // Scalar load/store, no arithmetic: SPV_EXT_float8 defines none.
  // CHECK: [[ld:%[0-9]+]] = OpLoad %fp8e4m3 %e4m3
  // CHECK-NEXT: OpStore %e4m3 [[ld]]
  e4m3 = e4m3;
  // CHECK: [[ld5:%[0-9]+]] = OpLoad %fp8e5m2 %e5m2
  // CHECK-NEXT: OpStore %e5m2 [[ld5]]
  e5m2 = e5m2;

  // Composite construction from components keeps the encoded element type.
  // CHECK: OpCompositeConstruct %v2fp8e4m3
  v2 = float8_e4m3_t2(e4m3, e4m3);
  // CHECK: OpCompositeExtract %fp8e4m3
  // CHECK: OpCompositeExtract %fp8e4m3
  // CHECK-NEXT: OpCompositeConstruct %v3fp8e4m3
  v3 = float8_e4m3_t3(v2.xy, e4m3);
  // CHECK: OpCompositeConstruct %v4fp8e5m2
  v4 = float8_e5m2_t4(e5m2, e5m2, e5m2, e5m2);
  // A matrix element is reached through an access chain, not a composite
  // instruction.
  // CHECK: OpAccessChain %_ptr_Function_fp8e4m3 %m %int_0 %int_0
  m._11 = e4m3;
  // CHECK: OpAccessChain %_ptr_Function_fp8e4m3 %v3 %int_2
  // CHECK-NEXT: OpLoad %fp8e4m3
  e4m3 = v3.z;

  // The values are consumed through a float conversion, which is the only way
  // SPV_EXT_float8 lets a float8 value take part in a computation.
  // CHECK: [[v4ld:%[0-9]+]] = OpLoad %v4fp8e5m2 %v4
  // CHECK-NEXT: OpFConvert %v4float [[v4ld]]
  // CHECK-NEXT: OpStore %o
  float4 o = float4(v4);
  // CHECK: OpStore %sink
  float4 sink = o;
}
