// RUN: not %dxc -T ps_6_0 -E mainIn -spirv -HV 2021 -fcgl %s 2>&1 | FileCheck %s --check-prefix=IN
// RUN: not %dxc -T ps_6_0 -E mainOut -spirv -HV 2021 -fcgl %s 2>&1 | FileCheck %s --check-prefix=OUT

// SPV_EXT_float8 does not allow the Float8E4M3EXT / Float8E5M2EXT encodings in
// the Input and Output storage classes, so a float8 value must be rejected in a
// shader stage interface - including inside a struct, a vector, a matrix or an
// array - instead of emitting SPIR-V the validator would reject.

// IN: error: float8_e4m3_t and float8_e5m2_t are not supported in shader stage input/output: SPV_EXT_float8 does not allow the Float8E4M3EXT or Float8E5M2EXT type in Input/Output storage classes
struct PSIn {
  float8_e4m3_t val : TEXCOORD0;
};

float4 mainIn(PSIn input) : SV_Target {
  return 1.0;
}

// OUT: error: float8_e4m3_t and float8_e5m2_t are not supported in shader stage input/output: SPV_EXT_float8 does not allow the Float8E4M3EXT or Float8E5M2EXT type in Input/Output storage classes
struct PSOut {
  float8_e5m2_t2x2 val : TEXCOORD0;
};

PSOut mainOut(float4 pos : SV_Position) {
  PSOut o;
  o.val._11 = float8_e5m2_t(1.0);
  return o;
}
