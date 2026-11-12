// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 %s -spirv 2>&1 | FileCheck %s

// dot() requires both operands to have the same component type. Widening the
// bfloat16_t side would silently turn a BFloat16DotProductKHR request into a
// float dot product, which is exactly what the capability is meant to control,
// so a mixed call is rejected instead. Note that this is not a plain "no
// matching function" error: Sema does find the float overload through the
// documented bfloat16_t -> float widening, so the check has to look at the
// pre-conversion operand types.

// CHECK: error: dot product cannot mix bfloat16_t with other component types; convert both operands to the same type explicitly
// CHECK: error: dot product cannot mix bfloat16_t with other component types; convert both operands to the same type explicitly

RWStructuredBuffer<float> Out;

[numthreads(1, 1, 1)]
void main() {
  bfloat16_t2 bf = bfloat16_t2(1.0, 2.0);
  float2 f = float2(3.0, 4.0);

  Out[0] = dot(bf, f);
  Out[1] = dot(f, bf);
}
