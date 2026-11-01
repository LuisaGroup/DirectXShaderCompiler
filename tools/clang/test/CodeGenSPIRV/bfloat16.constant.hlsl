// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2018 -fcgl -Vd %s | FileCheck %s

// bfloat16_t constants must be encoded with BFloat16 (binary32-like) semantics:
// 8-bit exponent bias 127 and an 8-bit significand (7 stored bits), NOT IEEE
// half semantics.

// Zero (positive and negative).
// CHECK: OpConstant %bfloat16 0x0p+0
// CHECK: OpConstant %bfloat16 -0x0p+0

// Small normal value 2^-8.
// CHECK: OpConstant %bfloat16 0x1p-8

// Round-to-nearest-even: 1.005859375 is 0.75 ulp above 1.0 and rounds up to
// 1.0078125 (0x3F81). With IEEE half semantics this would round differently.
// CHECK: OpConstant %bfloat16 0x1.02p+0

// Exact halfway cases round to the even significand.
// CHECK: OpConstant %bfloat16 0x1p+0
// CHECK: OpConstant %bfloat16 0x1.04p+0

// 1e30 overflows IEEE half to infinity, but is a finite normal in bfloat16_t
// (same exponent range as float32).
// CHECK: OpConstant %bfloat16 0x1.94p+99
// CHECK-NOT: OpConstant %bfloat16 0x1p+inf

// Near-float32-max rounds to the largest bfloat16_t normal (0x7F7F).
// CHECK: OpConstant %bfloat16 0x1.fep+127

static const bfloat16_t c_zero = 0.0;
static const bfloat16_t c_negzero = -0.0;
static const bfloat16_t c_small = 0.00390625;
static const bfloat16_t c_rne = 1.005859375;
static const bfloat16_t c_tie_even_down = 1.00390625;
static const bfloat16_t c_tie_even_up = 1.01171875;
static const bfloat16_t c_large = 1e30;
static const bfloat16_t c_max = 3.38953139e+38;

[numthreads(1, 1, 1)]
void main() {
  bfloat16_t a = c_zero;
  bfloat16_t b = c_negzero;
  bfloat16_t c = c_small;
  bfloat16_t d = c_rne;
  bfloat16_t e = c_tie_even_down;
  bfloat16_t f = c_tie_even_up;
  bfloat16_t g = c_large;
  bfloat16_t h = c_max;
  float x = float(a) + float(b) + float(c) + float(d) + float(e) + float(f) +
            float(g) + float(h);
  float4 o = float4(x, 0, 0, 0);
}
