// RUN: %dxc -T cs_6_0 -E main -HV 2021 %s -spirv | FileCheck %s

// L6: the same bfloat16 dot product as bfloat16.dot.hlsl, but through the
// shipped post-processing (legalization, spirv-opt and the capability trim pass)
// instead of -fcgl. Two things can only break here: the optimizer rewriting or
// dropping the OpDot, and the capability trim pass removing
// BFloat16DotProductKHR because it only sees an opcode it does not know.

// CHECK: OpCapability BFloat16TypeKHR
// CHECK: OpCapability BFloat16DotProductKHR
// CHECK-NOT: OpCapability BFloat16DotProductKHR
// CHECK: OpExtension "SPV_KHR_bfloat16"
// CHECK-NOT: OpExtension "SPV_KHR_bfloat16"

RWStructuredBuffer<bfloat16_t> Buf;
RWStructuredBuffer<bfloat16_t> Out;

[numthreads(1, 1, 1)]
void main() {
  bfloat16_t4 a = bfloat16_t4(Buf[0], Buf[1], Buf[2], Buf[3]);
  bfloat16_t4 b = bfloat16_t4(Buf[4], Buf[5], Buf[6], Buf[7]);

  // The result is consumed, so the dot product must survive optimization with
  // its bfloat16 result type and its operands still bfloat16.
  // CHECK: OpDot %bfloat16
  bfloat16_t d = dot(a, b);
  Out[0] = d;

  // A dot product whose result is unused must be removed together with nothing
  // else: the capability is still needed for the first call above.
  bfloat16_t dead = dot(a, b);
  (void)dead;
}
