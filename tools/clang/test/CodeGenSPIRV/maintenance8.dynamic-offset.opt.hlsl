// RUN: %dxc -T ps_6_0 -E main %s -spirv | FileCheck %s

// G31/L6 + G31/L3 for VK_KHR_maintenance8 rule 1, on the instruction the rule is
// about. No -fcgl, so legalization, spirv-opt, capability trimming and validation
// all run; no -Vd, so a passing compile *is* the module-validity statement.
//
// This is the red-first gate of the feature. Before the environment rule was
// wired into SpirvEmitter::spirvToolsValidate, this compile failed outright:
//   fatal error: generated SPIR-V is invalid:
//   [VUID-RuntimeSpirv-Offset-10213] Image Operand Offset can only be used with
//   OpImage*Gather operations.
//   This is allowed if you enable the maintenance8 feature (or use the
//   --allow-offset-texture-operand command line flag)
// because DXC emitted Offset on OpImageSampleImplicitLod (the only possible
// encoding for a non-constant HLSL offset) while validating against the
// pre-maintenance8 environment rule. The -fcgl tests cannot see this: -fcgl sets
// before_hlsl_legalization, which skips the check, so the operand was only ever
// exercised in a mode where the module is never validated as a final module.
//
// The mask is asserted with {{$}} so the exact operand word is pinned, and the
// absence of ConstOffset is then asserted over the instruction tail.

SamplerState gSampler : register(s5);
Texture2D<float4> t : register(t1);
RWStructuredBuffer<int> outI : register(u0);

float4 main(int2 dynamicOffset : A) : SV_Target {
  int a = outI[0];
  int b = outI[1];

  // The dynamic offset reaches the sampling instruction as Offset and survives
  // legalization + spirv-opt + capability trimming unchanged.
  // CHECK: OpImageSampleImplicitLod %v4float {{%[0-9]+}} {{%[0-9]+}} Offset {{%[0-9]+$}}
  float4 s = t.Sample(gSampler, float2(0.1, 0.2), dynamicOffset);

  // The negative control survives too: a constant offset is still ConstOffset,
  // so the relaxation did not turn into "always Offset".
  // CHECK: OpImageSampleImplicitLod %v4float {{%[0-9]+}} {{%[0-9]+}} ConstOffset {{%[0-9]+$}}
  float4 c = t.Sample(gSampler, float2(0.1, 0.2), int2(1, 2));

  // Rule 2 rides along so one non-fcgl module covers both maintenance8 rules.
  // CHECK: OpSRem %int
  outI[2] = a % b;

  return s + c;
}

// Anchored negative over the instruction tail: the environment relaxation has no
// module-level representation, so the module must carry no maintenance8 surface,
// no OpSMod, and no further image instruction.
// CHECK: OpStore %out_var_SV_Target
// CHECK-NOT: maintenance8
// CHECK-NOT: OpSMod
// CHECK-NOT: OpImage
// CHECK: OpFunctionEnd
