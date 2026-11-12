// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl %s | FileCheck %s

// Storage layout of the SPV_EXT_float8 types.
//
// An 8-bit float occupies one byte with a one-byte alignment, so a structured
// buffer of float8_e4m3_t has ArrayStride 1 and a mixed struct packs its members
// at the natural offsets. Neither layout needs an 8-bit *integer* storage
// capability: Float8EXT is what enables the encoded OpTypeFloat 8.
//
// The decoration block precedes the type declarations in the module, so the
// layout is asserted first and the types after it.

// CHECK-NOT: OpCapability Int8
// CHECK-NOT: OpCapability StorageBuffer8BitAccess
// CHECK-NOT: OpCapability UniformAndStorageBuffer8BitAccess
// CHECK-NOT: OpCapability StoragePushConstant8
// CHECK: OpCapability Float8EXT
// CHECK-NOT: OpCapability Float8EXT
// CHECK: OpExtension "SPV_EXT_float8"
// CHECK-NOT: OpExtension "SPV_EXT_float8"

struct S {
  float8_e4m3_t a;
  float8_e5m2_t b;
  float8_e4m3_t2 c;
  float d;
};

// A float8_t element is one byte wide.
// CHECK: OpDecorate %_runtimearr_fp8e4m3 ArrayStride 1
// CHECK: OpDecorate %_runtimearr_fp8e5m2 ArrayStride 1
// CHECK: OpMemberDecorate %S 0 Offset 0
// CHECK: OpMemberDecorate %S 1 Offset 1
// CHECK: OpMemberDecorate %S 2 Offset 2
// CHECK: OpMemberDecorate %S 3 Offset 4
// The struct is 8 bytes wide (one float8, one float8, a float8 vector, a float).
// CHECK: OpDecorate %_runtimearr_S ArrayStride 8

// The encoded types and the packed struct.
// CHECK: %fp8e4m3 = OpTypeFloat 8 Float8E4M3EXT
// CHECK: %fp8e5m2 = OpTypeFloat 8 Float8E5M2EXT
// CHECK: %v2fp8e4m3 = OpTypeVector %fp8e4m3 2
// CHECK-NOT: OpTypeFloat 8{{$}}
// CHECK: %S = OpTypeStruct %fp8e4m3 %fp8e5m2 %v2fp8e4m3 %float

StructuredBuffer<float8_e4m3_t> E4M3Buf;
StructuredBuffer<float8_e5m2_t> E5M2Buf;
RWStructuredBuffer<float8_e4m3_t> E4M3Out;
RWStructuredBuffer<S> StructBuf;

[numthreads(1, 1, 1)]
void main() {
  // CHECK: [[p0:%[0-9]+]] = OpAccessChain %_ptr_Uniform_fp8e4m3 %E4M3Buf %int_0 %uint_0
  // CHECK-NEXT: [[l0:%[0-9]+]] = OpLoad %fp8e4m3 [[p0]]
  // CHECK-NEXT: [[q0:%[0-9]+]] = OpAccessChain %_ptr_Uniform_fp8e4m3 %E4M3Out %int_0 %uint_0
  // CHECK-NEXT: OpStore [[q0]] [[l0]]
  E4M3Out[0] = E4M3Buf[0];

  // CHECK: [[p1:%[0-9]+]] = OpAccessChain %_ptr_Uniform_fp8e5m2 %E5M2Buf %int_0 %uint_2
  // CHECK-NEXT: [[l1:%[0-9]+]] = OpLoad %fp8e5m2 [[p1]]
  // CHECK: OpFConvert %float
  float widened = float(E5M2Buf[2]);

  // CHECK: [[p2:%[0-9]+]] = OpAccessChain %_ptr_Uniform_v2fp8e4m3 %StructBuf %int_0 %uint_1 %int_2
  // CHECK-NEXT: [[l2:%[0-9]+]] = OpLoad %v2fp8e4m3 [[p2]]
  // CHECK: OpFConvert %v2float
  float2 v = float2(StructBuf[1].c);

  // The struct member offsets above are also what OpAccessChain indexes into.
  // CHECK: OpAccessChain %_ptr_Uniform_fp8e5m2 %StructBuf %int_0 %uint_0 %int_1
  float8_e5m2_t b = StructBuf[0].b;
  E4M3Out[1] = float8_e4m3_t(b);

  float4 o = float4(widened, v.x, v.y, float(b));
}
