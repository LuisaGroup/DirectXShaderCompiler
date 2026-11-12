// RUN: %dxc -T cs_6_0 -E main -HV 2021 %s -spirv | FileCheck %s

// L6: conversions involving float8 types after the full post-processing chain.
// The optimizer must not fold an OpFConvert to or from an 8-bit float into
// something else, and it must not introduce an intermediate 16-bit float.
//
// CHECK: OpCapability Float8EXT
// CHECK-NOT: OpCapability Float16
// CHECK-NOT: OpCapability Int8
// CHECK: OpExtension "SPV_EXT_float8"
// CHECK: %fp8e4m3 = OpTypeFloat 8 Float8E4M3EXT
// CHECK: %fp8e5m2 = OpTypeFloat 8 Float8E5M2EXT
// CHECK-NOT: OpTypeFloat 16

RWStructuredBuffer<float8_e4m3_t> E4M3Buf;
RWStructuredBuffer<float8_e5m2_t> E5M2Buf;
RWStructuredBuffer<float> FloatOut;
RWStructuredBuffer<int> IntOut;

[numthreads(1, 1, 1)]
void main() {
  float8_e4m3_t a = E4M3Buf[0];
  // Widening to float and narrowing back both survive as OpFConvert.
  // CHECK: OpLoad %fp8e4m3
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %fp8e4m3
  float8_e4m3_t roundtrip = float8_e4m3_t(float(a));
  // float8 -> float8 of the other format is still a conversion.
  // CHECK: OpFConvert %fp8e5m2
  float8_e5m2_t converted = float8_e5m2_t(a);
  // The integer conversions keep the 8-bit float as the float side.
  // CHECK: OpConvertFToS %int
  // CHECK: OpConvertSToF %fp8e4m3
  int i = int(a);
  float8_e4m3_t fromInt = float8_e4m3_t(i);
  FloatOut[0] = float(roundtrip) + float(fromInt);
  IntOut[0] = int(converted);
}
