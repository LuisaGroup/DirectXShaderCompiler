// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl %s | FileCheck %s
//
// The conversion model of SPV_EXT_ocp_microscaling_types.
//
// A micro-scaled value is produced by OpBitcastExtractEXT (4- and 6-bit
// formats) or by an OpConstant (a literal), never by a conversion: SPIR-V
// forbids OpFConvert, OpConvertSToF and OpConvertUToF from producing an OCP
// micro-scaling type. In the other direction the extension allows consuming a
// micro-scaled value only to produce IEEE 754, Float8E4M3EXT, Float8E5M2EXT or
// BFloat16KHR, so all of the conversions below are OpFConvert with a
// non-micro-scaled result type, and an integer result is reached through float.
//
// The capability order is the emitter's type-discovery order.
// CHECK: OpCapability Float8UnsignedE8M0EXT
// CHECK: OpCapability Float4EXT
// CHECK: OpCapability Float6EXT
// CHECK: OpCapability Float64
// CHECK: OpCapability Float8EXT
// CHECK: OpCapability BitcastExtractEXT
// CHECK: OpExtension "SPV_EXT_ocp_microscaling_types"
// CHECK: OpExtension "SPV_EXT_float8"
// The E8M0 constant for the literal 2.0: 2.0 is 2^(128-127), so the exponent
// field is 128 (0x80), printed back as 0x1p+1.
// CHECK: %fp8e8m0 = OpTypeFloat 8 Float8UnsignedE8M0EXT
// CHECK-NEXT: %fp8e8m0_0x1p_1 = OpConstant %fp8e8m0 0x1p+1
#include <vk/ext/ocp_microscaling.h>

[numthreads(1, 1, 1)]
void main() {
  uint w = 0;
  float4_e2m1_t q = vk::mx::bitcast_extract_e2m1(w, 0);
  float6_e3m2_t e = vk::mx::bitcast_extract_e3m2(w, 0);
  float6_e2m3_t m = vk::mx::bitcast_extract_e2m3(w, 0);

  float f = 1.5;

  // widens to binary32 and binary64 without a cast on the source side
  // CHECK: OpFConvert %float
  float a = float(q);
  // CHECK: OpFConvert %double
  double b = double(e);
  // CHECK: OpFConvert %float
  float c = float(m);

  // A micro-scaled operand widens inside an expression, which is the only
  // implicit conversion the type allows.
  // CHECK: OpFAdd %float
  float sum = q + f;

  // The conversion to one of the two float8 formats is an OpFConvert whose
  // result carries the Float8E4M3EXT / Float8E5M2EXT encoding.
  // CHECK: OpFConvert %fp8e4m3
  float8_e4m3_t f8 = float8_e4m3_t(q);
  // CHECK: OpFConvert %fp8e5m2
  float8_e5m2_t f8b = float8_e5m2_t(e);

  // There is no direct conversion between a micro-scaled and an integer type;
  // the value has to be widened first, which is what these two pairs do.
  // CHECK: OpFConvert %float
  // CHECK: OpConvertFToS %int
  int i = int(float(q));
  // CHECK: OpFConvert %float
  // CHECK: OpConvertFToU %uint
  uint u = uint(float(e));

  // The 8-bit E8M0 scale is one byte wide, so it can be a buffer element and is
  // read with an ordinary load. A literal converts into it and folds to a
  // constant - 2.0 is 2^(128-127), i.e. the exponent field 128 (0x80), which is
  // asserted with the other constants above.
  float8_e8m0_t s = float8_e8m0_t(2.0);
  // CHECK: OpFConvert %float
  float t = float(s);

  // A vector form converts the whole vector at once: one OpFConvert for both
  // lanes.
  float4_e2m1_t2 q2 = vk::mx::bitcast_extract_e2m1(uint2(w, w), 8);
  // CHECK: OpFConvert %v2float
  float2 vv = float2(q2);
  // Converting one lane out of the vector is a scalar conversion again.
  // CHECK: OpFConvert %float
  float lane = float(vv.y);

  float acc = a + float(b) + c + sum + float(f8) + float(f8b) + float(i) +
              float(u) + t + lane + vv.x + vv.y;
}
