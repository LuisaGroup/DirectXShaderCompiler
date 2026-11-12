// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl %s | FileCheck %s

// Explicit numeric conversions involving the SPV_EXT_float8 types.
//
// Sema allows an implicit conversion only from a float8 type to a wider float
// type; every conversion in this file is therefore written as an explicit cast,
// which lowers to OpFConvert - the width-only conversion SPIR-V allows for 8-bit
// floats. Conversions between the two float8 formats also need OpFConvert even
// though both are 8 bits wide, because the encodings differ.
//
// Conversions to and from float16_t (which needs -enable-16bit-types and a 6.2
// target) are covered by float8.16bit-types.hlsl.

// CHECK-NOT: OpCapability Float16
// CHECK-NOT: OpCapability Int8
// CHECK: OpCapability Float8EXT
// CHECK: OpExtension "SPV_EXT_float8"
// The encoded types, and no plain 8-bit float and no 8-bit integer anywhere.
// CHECK: %fp8e4m3 = OpTypeFloat 8 Float8E4M3EXT
// CHECK-NOT: OpTypeFloat 8{{$}}
// CHECK-NOT: OpTypeInt 8
// CHECK: %fp8e5m2 = OpTypeFloat 8 Float8E5M2EXT
// CHECK-NOT: OpTypeInt 8
// CHECK: %v2fp8e4m3 = OpTypeVector %fp8e4m3 2

// The instruction kinds are what this test pins: one OpFConvert per conversion,
// with the float8 encoding on the correct side. The SSA ids are not captured
// because each conversion appears twice (the declaration and the assignment).

[numthreads(1, 1, 1)]
void main() {
  float f = 1.5;
  float8_e4m3_t e4m3 = float8_e4m3_t(f);
  float8_e5m2_t e5m2 = float8_e5m2_t(f);
  // float -> float8 for both formats.
  // CHECK: OpFConvert %fp8e4m3 {{%[0-9]+}}
  e4m3 = float8_e4m3_t(f);
  // CHECK: OpFConvert %fp8e5m2 {{%[0-9]+}}
  e5m2 = float8_e5m2_t(f);

  // Widening to binary32.
  // CHECK: OpFConvert %float {{%[0-9]+}}
  float g = float(e4m3);
  g = float(e4m3);
  // CHECK: OpFConvert %float {{%[0-9]+}}
  float h = float(e5m2);
  h = float(e5m2);

  // Widening to binary64.
  // CHECK: OpFConvert %double {{%[0-9]+}}
  double d = double(e4m3);
  d = double(e4m3);

  // The two float8 formats convert into each other only through an explicit
  // cast, and still emit OpFConvert because the encodings differ.
  // CHECK: OpFConvert %fp8e5m2 {{%[0-9]+}}
  e5m2 = float8_e5m2_t(e4m3);
  // CHECK: OpFConvert %fp8e4m3 {{%[0-9]+}}
  e4m3 = float8_e4m3_t(e5m2);

  // Conversions to and from integers are ordinary OpConvert*ToF /
  // OpConvertFTo* instructions whose float side is an 8-bit float. No
  // intermediate 8-bit integer may appear because that would require the Int8
  // capability.
  // CHECK: OpConvertFToS %int {{%[0-9]+}}
  int i = int(e4m3);
  i = int(e4m3);
  // CHECK: OpConvertSToF %fp8e4m3 {{%[0-9]+}}
  e4m3 = float8_e4m3_t(i);
  // CHECK: OpConvertFToU %uint {{%[0-9]+}}
  uint u = uint(e5m2);
  u = uint(e5m2);
  // CHECK: OpConvertUToF %fp8e5m2 {{%[0-9]+}}
  e5m2 = float8_e5m2_t(u);

  // Vector conversions convert the whole vector at once.
  float8_e4m3_t2 v =
      float8_e4m3_t2(float8_e4m3_t(f), float8_e4m3_t(f));
  // CHECK: OpFConvert %v2float {{%[0-9]+}}
  float2 vf = float2(v);
  vf = float2(v);
  // CHECK: OpFConvert %v2fp8e4m3 {{%[0-9]+}}
  v = float8_e4m3_t2(vf);

  // Arithmetic is performed in float: the float8 operand is widened first.
  // CHECK: OpFConvert %float {{%[0-9]+}}
  // CHECK: OpFAdd %float
  float sum = float(v.x) + float(e4m3);
  // An implicit widening inside an expression is enough to reach a float
  // operation, and is the only implicit conversion the type allows.
  // CHECK: OpFConvert %float {{%[0-9]+}}
  // CHECK: OpFAdd %float
  float implicit_sum = e4m3 + f;
  float4 o = float4(g, h, d, sum + implicit_sum + float(i) + float(u) + vf.x);
}
