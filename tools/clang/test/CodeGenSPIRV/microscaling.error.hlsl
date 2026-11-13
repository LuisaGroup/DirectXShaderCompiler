// RUN: not %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl %s 2>&1 | FileCheck %s
//
// SPV_EXT_ocp_microscaling_types defines no arithmetic, comparison, bitwise or
// unary operation on the four micro-scaled types, and no conversion into one
// other than from a literal. Every operation whose computation would be
// performed in a micro-scaled type is rejected with the extension-specific
// diagnostic instead of being emitted as SPIR-V that the validator would
// reject.
//
// Widening to float, simple assignment and the extraction itself stay valid;
// see microscaling.conversion.hlsl and microscaling.bitcast-extract.hlsl.
#include <vk/ext/ocp_microscaling.h>

[numthreads(1, 1, 1)]
void main() {
  uint w = 0;
  float f = 1.0;
  int i = 1;
  float4_e2m1_t a = vk::mx::bitcast_extract_e2m1(w, 0);
  float4_e2m1_t b = vk::mx::bitcast_extract_e2m1(w, 4);
  float6_e3m2_t c = vk::mx::bitcast_extract_e3m2(w, 0);
  float8_e8m0_t s = float8_e8m0_t(1.0);
  float8_e8m0_t t = float8_e8m0_t(2.0);

  // CHECK: error: operator is not supported for float4_e2m1_t, float6_e3m2_t, float6_e2m3_t or float8_e8m0_t; SPV_EXT_ocp_microscaling_types defines no arithmetic, comparison or bitwise operations - convert the operand to float or double explicitly
  float4_e2m1_t add = a + b;
  // CHECK: error: operator is not supported for float4_e2m1_t, float6_e3m2_t, float6_e2m3_t or float8_e8m0_t
  float6_e3m2_t mul = c * c;
  // CHECK: error: operator is not supported for float4_e2m1_t, float6_e3m2_t, float6_e2m3_t or float8_e8m0_t
  float8_e8m0_t scale = s * t;
  // CHECK: error: operator is not supported for float4_e2m1_t, float6_e3m2_t, float6_e2m3_t or float8_e8m0_t
  float4_e2m1_t neg = -a;
  // CHECK: error: operator is not supported for float4_e2m1_t, float6_e3m2_t, float6_e2m3_t or float8_e8m0_t
  bool less = a < b;
  // CHECK: error: operator is not supported for float4_e2m1_t, float6_e3m2_t, float6_e2m3_t or float8_e8m0_t
  bool equal = a == b;

  // The four formats are distinct types: combining two of them in one
  // expression is a type mismatch rather than a silent conversion.
  // CHECK: error: type mismatch
  float4_e2m1_t mixed = a + c;

  // There is no conversion *into* a micro-scaled type: SPIR-V forbids
  // OpFConvert/OpConvertSToF/OpConvertUToF from producing an OCP micro-scaling
  // type, so a value comes from vk::mx::bitcast_extract (4- and 6-bit) or from
  // storage (the 8-bit E8M0 scale).
  // CHECK: error: type mismatch
  // CHECK: error: cannot convert from 'float' to 'float4_e2m1_t'
  float4_e2m1_t narrow = float4_e2m1_t(f);
  // CHECK: error: cannot convert from 'int' to 'float6_e2m3_t'
  float6_e2m3_t narrow_int = float6_e2m3_t(i);
  // CHECK: error: cannot convert from 'float' to 'float8_e8m0_t'
  float8_e8m0_t narrow_scale = float8_e8m0_t(f);

  // No conversion to or from bool exists, not even an explicit one.
  // CHECK: error: cannot initialize a variable of type 'bool' with an lvalue of type 'float4_e2m1_t'
  bool as_bool = a;

  // Widening to a wider float is implicit, so a micro-scaled operand can take
  // part in a float computation - this line must not be diagnosed.
  float ok = a + f;
  float ok2 = float(a) + float(c) + float(s);
}
