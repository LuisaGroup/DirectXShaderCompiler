// RUN: %dxc -T cs_6_0 -E main -fcgl  %s -spirv | FileCheck %s

// G31/L2: VK_KHR_maintenance8 rule 2 - HLSL "%" is truncating (C-style)
// remainder, and DXC lowers it to OpSRem, never to OpSMod. maintenance8 is what
// makes that lowering well defined for negative operands in the Vulkan SPIR-V
// environment: before it, "if either operand to OpSRem and OpSMod is negative
// the result is undefined" (Vulkan, "Precision and Operation of SPIR-V
// Instructions"), which is exactly the SPIR-V definition HLSL relies on - the
// sign of a non-zero result comes from the *first* operand. OpSMod takes the
// sign from the second operand, so it would give the wrong answer for HLSL
// semantics, and it is the near-miss this test excludes.
//
// The fixtures therefore use negative operands on both sides. Only signed "%"
// is in scope: there is no OpURem, so HLSL unsigned "%" is OpUMod.
//
// OpSDiv for "/" is asserted alongside: maintenance8 also makes signed division
// well defined where the result is representable, and keeping the two opcodes in
// one file pins them against a future "fold the division into the remainder"
// rewrite.
//
// Absence of OpSMod is asserted at every remainder site (a CHECK-NOT placed
// between two positive CHECKs, so its region is exactly the gap where a wrong
// lowering would appear) plus once over the module header. A single trailing
// CHECK-NOT would be vacuous.

RWStructuredBuffer<int> outI : register(u0);
RWStructuredBuffer<int64_t> outL : register(u1);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  int a = outI[0];
  int b = outI[1];
  int64_t la = outL[0];
  int64_t lb = outL[1];

  // CHECK: OpCapability Shader
  // CHECK-NOT: OpSMod
  // CHECK: OpMemoryModel Logical GLSL450

  // Non-negative operands: a plain OpSRem on the 32-bit int type.
  // CHECK: [[A:%[0-9]+]] = OpLoad %int %a
  // CHECK: [[B:%[0-9]+]] = OpLoad %int %b
  // CHECK-NOT: OpSMod
  // CHECK: [[REM:%[0-9]+]] = OpSRem %int [[A]] [[B]]
  outI[2] = a % b;

  // Negative dividend: the sign of the result comes from operand 1, which is
  // what OpSRem does and what OpSMod would not.
  // CHECK: [[A2:%[0-9]+]] = OpLoad %int %a
  // CHECK: [[NEG_A:%[0-9]+]] = OpSNegate %int [[A2]]
  // CHECK: [[B2:%[0-9]+]] = OpLoad %int %b
  // CHECK-NOT: OpSMod
  // CHECK: {{%[0-9]+}} = OpSRem %int [[NEG_A]] [[B2]]
  outI[3] = -a % b;

  // Negative divisor: still OpSRem, so the result keeps the dividend's sign.
  // CHECK: [[A3:%[0-9]+]] = OpLoad %int %a
  // CHECK: [[B3:%[0-9]+]] = OpLoad %int %b
  // CHECK: [[NEG_B:%[0-9]+]] = OpSNegate %int [[B3]]
  // CHECK-NOT: OpSMod
  // CHECK: {{%[0-9]+}} = OpSRem %int [[A3]] [[NEG_B]]
  outI[4] = a % -b;

  // "/" is a separate opcode and must stay one.
  // CHECK: [[A4:%[0-9]+]] = OpLoad %int %a
  // CHECK: [[B4:%[0-9]+]] = OpLoad %int %b
  // CHECK-NOT: OpSMod
  // CHECK: {{%[0-9]+}} = OpSDiv %int [[A4]] [[B4]]
  outI[5] = a / b;

  // The same rule at 64-bit width: the remainder is still OpSRem, typed %long.
  // CHECK: [[LA:%[0-9]+]] = OpLoad %long %la
  // CHECK: [[LB:%[0-9]+]] = OpLoad %long %lb
  // CHECK-NOT: OpSMod
  // CHECK: {{%[0-9]+}} = OpSRem %long [[LA]] [[LB]]
  outL[2] = la % lb;

  // CHECK: [[LA2:%[0-9]+]] = OpLoad %long %la
  // CHECK: [[NEG_LA:%[0-9]+]] = OpSNegate %long [[LA2]]
  // CHECK: [[LB2:%[0-9]+]] = OpLoad %long %lb
  // CHECK-NOT: OpSMod
  // CHECK: [[REM_L:%[0-9]+]] = OpSRem %long [[NEG_LA]] [[LB2]]
  // CHECK: [[PTR_L:%[0-9]+]] = OpAccessChain %_ptr_Uniform_long %outL %int_0 %uint_3
  // CHECK: OpStore [[PTR_L]] [[REM_L]]
  outL[3] = -la % lb;

  // CHECK: OpReturn
  // CHECK: OpFunctionEnd
}
