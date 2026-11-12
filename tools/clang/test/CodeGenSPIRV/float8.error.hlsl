// RUN: not %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl %s 2>&1 | FileCheck %s

// SPV_EXT_float8 defines no arithmetic, comparison, bitwise or unary operations
// on the float8 types, so every operation whose computation would be performed
// in float8_e4m3_t / float8_e5m2_t is rejected with the extension-specific
// diagnostic instead of being emitted as invalid SPIR-V. Simple assignment,
// comma, and operations whose combined type widens the float8 operand to float
// remain valid (see float8.conversion.hlsl).

[numthreads(1, 1, 1)]
void main() {
  float f = 1.0;
  int i = 1;
  float8_e4m3_t a = float8_e4m3_t(f);
  float8_e4m3_t b = float8_e4m3_t(f);
  float8_e5m2_t c = float8_e5m2_t(f);

  // CHECK: error: operator is not supported for float8_e4m3_t or float8_e5m2_t; SPV_EXT_float8 defines no arithmetic, comparison or bitwise operations - convert the operand to float or double explicitly
  float8_e4m3_t add = a + b;

  // CHECK: error: operator is not supported for float8_e4m3_t or float8_e5m2_t; SPV_EXT_float8 defines no arithmetic, comparison or bitwise operations - convert the operand to float or double explicitly
  float8_e4m3_t mul = a * b;

  // CHECK: error: operator is not supported for float8_e4m3_t or float8_e5m2_t; SPV_EXT_float8 defines no arithmetic, comparison or bitwise operations - convert the operand to float or double explicitly
  float8_e4m3_t neg = -a;

  // CHECK: error: operator is not supported for float8_e4m3_t or float8_e5m2_t; SPV_EXT_float8 defines no arithmetic, comparison or bitwise operations - convert the operand to float or double explicitly
  bool less = a < b;

  // CHECK: error: operator is not supported for float8_e4m3_t or float8_e5m2_t; SPV_EXT_float8 defines no arithmetic, comparison or bitwise operations - convert the operand to float or double explicitly
  bool equal = a == b;

  // The two float8 formats are distinct types: combining E4M3 and E5M2 in one
  // expression is a type mismatch rather than a silent conversion.
  // CHECK: error: type mismatch
  float8_e4m3_t mixed = a + c;

  // Implicit narrowing from a wider float is not allowed; the value has to be
  // cast explicitly because the conversion is lossy.
  // CHECK: error: cannot initialize a variable of type 'float8_e4m3_t' with an lvalue of type 'float'
  float8_e4m3_t narrow = f;

  // The same applies to an integer source.
  // CHECK: error: cannot initialize a variable of type 'float8_e5m2_t' with an lvalue of type 'int'
  float8_e5m2_t narrow_int = i;

  // No conversion to bool exists, not even an explicit one.
  // CHECK: error: cannot initialize a variable of type 'bool' with an lvalue of type 'float8_e4m3_t'
  bool as_bool = a;

  // Widening to a wider float is implicit, so a float8 operand can take part in
  // a float computation - this line must not be diagnosed.
  float ok = a + f;

  // A literal, on the other hand, takes the float8 kind, so mixing one into an
  // arithmetic expression is rejected like any other float8 arithmetic and the
  // operand has to be converted explicitly.
  // CHECK: error: operator is not supported for float8_e4m3_t or float8_e5m2_t; SPV_EXT_float8 defines no arithmetic, comparison or bitwise operations - convert the operand to float or double explicitly
  float literal_sum = a + 1.0;
}
