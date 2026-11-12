// RUN: %dxc -T cs_6_0 -E main -HV 2021 %s -spirv | FileCheck %s

// L6: the same float8 types as float8.basic.hlsl, but through the shipped
// post-processing (legalization, spirv-opt and the capability trim pass) instead
// of -fcgl. Three things can only break here: the optimizer rewriting OpFConvert
// on an 8-bit float, spirv-opt dropping an OpTypeFloat 8 that it does not
// understand, and the capability trim pass removing Float8EXT or the
// SPV_EXT_float8 extension because it only sees opcodes it knows.
//
// CHECK: OpCapability Float8EXT
// CHECK-NOT: OpCapability Float8EXT
// CHECK-NOT: OpCapability Float8CooperativeMatrixEXT
// CHECK-NOT: OpCapability Int8
// CHECK-NOT: OpCapability Float16
// CHECK: OpExtension "SPV_EXT_float8"
// CHECK-NOT: OpExtension "SPV_EXT_float8"
// CHECK: %fp8e4m3 = OpTypeFloat 8 Float8E4M3EXT
// CHECK: %fp8e5m2 = OpTypeFloat 8 Float8E5M2EXT

RWStructuredBuffer<float8_e4m3_t> E4M3Buf;
RWStructuredBuffer<float8_e5m2_t> E5M2Buf;
RWStructuredBuffer<float> FloatOut;

[numthreads(1, 1, 1)]
void main() {
  float8_e4m3_t a = E4M3Buf[0];
  float8_e5m2_t b = E5M2Buf[0];
  // The results are consumed, so the loads and the conversions must survive
  // optimization with their 8-bit float types.
  // CHECK: OpLoad %fp8e4m3
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  float sum = float(a) + float(b);
  // Writing the value back keeps a live OpTypeFloat 8 of each encoding.
  // CHECK: OpFConvert %fp8e5m2
  // CHECK: OpFConvert %fp8e4m3
  E5M2Buf[1] = float8_e5m2_t(a);
  E4M3Buf[1] = float8_e4m3_t(b);
  FloatOut[0] = sum;
}
