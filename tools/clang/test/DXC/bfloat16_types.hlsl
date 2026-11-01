// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2018 %s -verify
// RUN: not %dxc -T cs_6_0 -E main -spirv -HV 2016 %s 2>&1 | FileCheck %s --check-prefix=OLD
// expected-no-diagnostics

// Foundational Sema support for bfloat16_t (SPIR-V backend only, HLSL 2018+).
// bfloat16_t is always a native 16-bit type; it does not require
// -enable-16bit-types and is distinct from float16_t/half.

// Scalar and vector/matrix shorthand forms.
static bfloat16_t g_scalar;
static bfloat16_t2 g_vec2;
static bfloat16_t3 g_vec3;
static bfloat16_t4 g_vec4;
static bfloat16_t2x2 g_mat2;
static bfloat16_t3x4 g_mat3x4;

// vector<> and matrix<> template forms.
static vector<bfloat16_t, 4> g_tvec;
static matrix<bfloat16_t, 2, 3> g_tmat;

// Implicit widening to float32/float64 (scalar and vector).
float WidenToFloat(bfloat16_t x) { return x; }
double WidenToDouble(bfloat16_t x) { return x; }
vector<float, 4> WidenVec(bfloat16_t4 x) { return x; }

// Literals and explicit constructors/conversions.
bfloat16_t FromLiteral() { return 1.5; }
bfloat16_t FromFloat(float f) { return bfloat16_t(f); }
bfloat16_t FromInt(int i) { return bfloat16_t(i); }
float ToFloat(bfloat16_t x) { return float(x); }
int ToInt(bfloat16_t x) { return int(x); }
bfloat16_t2 MakeVec(bfloat16_t x) { return bfloat16_t2(x, x); }

// OLD: error: unknown type name 'bfloat16_t'

[numthreads(1, 1, 1)]
void main() {
  bfloat16_t s = 2.5;
  bfloat16_t2 v = bfloat16_t2(s, s);
  float f = v.x;          // component access, implicit widening
  bfloat16_t4 w = g_tvec; // vector copy
  w.y = s;
  bfloat16_t2x2 m = g_mat2;
  m._11 = s;              // matrix element access
  g_scalar = s;
  g_vec2 = v;
  g_mat2 = m;
  g_tvec = w;
  g_mat3x4 = g_mat3x4;
  f += WidenToFloat(g_scalar) + ToFloat(w.y) + (float)m._11;
}
