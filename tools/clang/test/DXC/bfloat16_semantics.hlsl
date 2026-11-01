// RUN: %dxc -T cs_6_2 -E main -spirv -HV 2018 -enable-16bit-types %s -verify

// Phase 2 semantic rules for bfloat16_t, enforcing the portable
// SPV_KHR_bfloat16 model:
//  - bfloat16_t implicitly widens to float32/float64 (scalar/vector/matrix)
//    and accepts numeric literals, like other HLSL floating point types.
//  - All other conversions to or from bfloat16_t (narrowing, float16_t,
//    integer types) require an explicit cast.
//  - No conversion to or from bool.
//  - float16_t (half with -enable-16bit-types) and bfloat16_t never combine
//    or convert implicitly.
//  - No arithmetic, comparison, or unary arithmetic operations; SPV_KHR_bfloat16
//    defines no such operations, so operands must be explicitly converted to
//    float or double first.

static bfloat16_t g_b;
static bfloat16_t2 g_v;
static bfloat16_t2x2 g_m;

// Implicit widening to float32/float64, scalar and vector.
float WidenScalar(bfloat16_t x) { return x; }
double WidenDouble(bfloat16_t x) { return x; }
vector<float, 4> WidenVector(bfloat16_t4 x) { return x; }
matrix<float, 2, 2> WidenMatrix(bfloat16_t2x2 x) { return x; }
matrix<double, 2, 2> WidenMatrixDouble(bfloat16_t2x2 x) { return x; }

// Numeric literals convert implicitly, as with other HLSL float types.
bfloat16_t FromLiteral() { return 1.5; }
bfloat16_t2 FromLiterals() { return bfloat16_t2(1.5, 2.5); }

// Explicit constructors/conversions to and from floating point and integer
// scalar types.
bfloat16_t FromFloat(float f) { return bfloat16_t(f); }
bfloat16_t FromInt(int i) { return bfloat16_t(i); }
float ToFloat(bfloat16_t x) { return float(x); }
int ToInt(bfloat16_t x) { return int(x); }

// float16_t <-> bfloat16_t is allowed only with an explicit cast.
bfloat16_t FromHalf(half h) { return bfloat16_t(h); }
half ToHalf(bfloat16_t x) { return half(x); }

// Assignments, swizzles and subscripts remain valid.
void StorageOps(bfloat16_t x) {
  g_b = x;
  g_v = bfloat16_t2(x, x);
  g_v.xy = g_v.xy;
  g_m._11 = x;
  g_m._12 = g_v.x;
  float f = g_v.y;
  g_b = g_m._11;
}

[numthreads(1, 1, 1)]
void main() {
  bfloat16_t b = 2.5;
  bfloat16_t b2 = g_b;
  bfloat16_t2 vb = g_v;
  bfloat16_t2x2 mb = g_m;
  float f = 1.0;
  half h = 2.0;
  int i = 3;
  bool bl = false;

  // Valid: widen first, then do arithmetic in float.
  f = float(b) * 2.0 + ToFloat(vb.x);

  // Valid: assignments and moves.
  b = b2;
  vb = g_v;
  mb._11 = b;

  // Invalid: arithmetic directly on bfloat16_t, even with literals.
  b = b + b;    // expected-error {{operator is not supported for bfloat16_t}}
  b = b - b2;   // expected-error {{operator is not supported for bfloat16_t}}
  b = b * 2.0;  // expected-error {{operator is not supported for bfloat16_t}}
  b = b / 2;    // expected-error {{operator is not supported for bfloat16_t}}
  vb = vb + vb; // expected-error {{operator is not supported for bfloat16_t}}
  mb = mb * mb; // expected-error {{operator is not supported for bfloat16_t}}

  // Invalid: compound assignment computes in bfloat16_t.
  b += b;   // expected-error {{operator is not supported for bfloat16_t}}
  b *= 1.5; // expected-error {{operator is not supported for bfloat16_t}}

  // Invalid: comparisons are not defined for bfloat16_t.
  bl = b < b2;   // expected-error {{operator is not supported for bfloat16_t}}
  bl = b == b;   // expected-error {{operator is not supported for bfloat16_t}}
  bl = b != 1.0; // expected-error {{operator is not supported for bfloat16_t}}

  // Invalid: unary arithmetic on bfloat16_t.
  b = +b; // expected-error {{operator is not supported for bfloat16_t}}
  b = -b; // expected-error {{operator is not supported for bfloat16_t}}
  b++;    // expected-error {{operator is not supported for bfloat16_t}}
  --b;    // expected-error {{operator is not supported for bfloat16_t}}

  // Invalid: implicit narrowing from floating point variables.
  bfloat16_t nb = f; // expected-error {{cannot initialize a variable of type 'bfloat16_t'}}
  b = f;             // expected-error {{cannot implicitly convert from 'float' to 'bfloat16_t'}}

  // Invalid: implicit conversions between bfloat16_t and float16_t.
  bfloat16_t bh = h; // expected-error {{cannot initialize a variable of type 'bfloat16_t'}}
  half hh = b;       // expected-error {{cannot initialize a variable of type 'half'}}
  b = h;             // expected-error {{cannot implicitly convert from 'half' to 'bfloat16_t'}}
  h = b;             // expected-error {{cannot implicitly convert from 'bfloat16_t' to 'half'}}

  // Invalid: mixing bfloat16_t and float16_t in an operation is a type
  // mismatch, never a silent float16_t result.
  f = b + h; // expected-error {{type mismatch}}
  f = h + b; // expected-error {{type mismatch}}

  // Invalid: no conversion to or from bool.
  bool bb = b;        // expected-error {{cannot initialize a variable of type 'bool'}}
  bfloat16_t tb = bl; // expected-error {{cannot initialize a variable of type 'bfloat16_t'}}
  bb = bool(b); // expected-error {{type mismatch}} expected-error {{cannot convert from 'bfloat16_t' to 'bool'}}
  b = bfloat16_t(bl); // expected-error {{type mismatch}} expected-error {{cannot convert from 'bool' to 'bfloat16_t'}}

  // Invalid: implicit narrowing from integer variables.
  bfloat16_t ib = i; // expected-error {{cannot initialize a variable of type 'bfloat16_t'}}
  b = i;             // expected-error {{cannot implicitly convert from 'int' to 'bfloat16_t'}}
}
