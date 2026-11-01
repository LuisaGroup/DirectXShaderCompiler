// RUN: not %dxc -T ps_6_0 -E mainIn -spirv -HV 2018 -fcgl -Vd %s 2>&1 | FileCheck %s
// RUN: not %dxc -T ps_6_0 -E mainOut -spirv -HV 2018 -fcgl -Vd %s 2>&1 | FileCheck %s

// SPV_KHR_bfloat16 does not allow the BFloat16KHR type in Input/Output
// storage classes, so bfloat16_t must be rejected in shader stage interfaces
// (including structs, vectors and matrices containing it) instead of
// requesting the 16-bit stage I/O capabilities.

// CHECK: error: bfloat16_t is not supported in shader stage input/output: SPV_KHR_bfloat16 does not allow the BFloat16KHR type in Input/Output storage classes

struct PSIn {
  bfloat16_t val : TEXCOORD0;
};

float4 mainIn(PSIn input) : SV_Target {
  return 1.0;
}

struct PSOut {
  bfloat16_t2x2 val : TEXCOORD0;
};

PSOut mainOut(float4 pos : SV_Position) {
  PSOut o;
  o.val._11 = bfloat16_t(1.0);
  return o;
}
