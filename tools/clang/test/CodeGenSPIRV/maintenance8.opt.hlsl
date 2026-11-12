// RUN: %dxc -T ps_6_0 -E main %s -spirv | FileCheck %s

// G31/L6: optimizer survival, and the L3 gate at the same time - no -fcgl, so
// this is the real pipeline: legalization, spirv-opt at the default
// optimization level, capability trimming, then validation. No -Vd either, so a
// passing compile is itself the statement that the module validates for the
// default target environment (Vulkan 1.0).
//
// This is the test that catches the failure mode the -fcgl tests cannot: the
// shipped validator rejects the Offset image operand on image instructions other
// than OpImage*Gather unless the VK_KHR_maintenance8 relaxation is in effect
// (VUID-RuntimeSpirv-Offset-10213). DXC emitted Offset on OpImageSample* for a
// dynamic offset while validating against the pre-maintenance8 rule, so a shader
// that only uses a non-constant texture offset failed to compile at all:
//   fatal error: generated SPIR-V is invalid: [VUID-RuntimeSpirv-Offset-10213]
//   Image Operand Offset can only be used with OpImage*Gather operations.
// The gate wiring for that is options.SetAllowOffsetTextureOperand in
// SpirvEmitter::spirvToolsValidate; this file is what keeps it honest.
//
// Both maintenance8 rules are exercised after optimization:
//  * rule 1 - a dynamic offset survives as Offset, a constant one as ConstOffset;
//  * rule 2 - "%" survives as OpSRem on int, including a negative operand.
//
// The dynamic-offset call uses .Gather() rather than .Sample() on purpose: it is
// the one image instruction for which Offset was already legal before
// maintenance8, so this module is valid for every Vulkan target environment and
// the test does not depend on the relaxation. maintenance8.dynamic-offset.opt.hlsl
// covers the sampling forms that do.

SamplerState gSampler : register(s5);
Texture2D<float4> t : register(t1);
RWStructuredBuffer<int> outI : register(u0);

float4 main(int2 dynamicOffset : A) : SV_Target {
  int a = outI[0];
  int b = outI[1];

  // Rule 1: the dynamic offset keeps the Offset mask through legalization and
  // spirv-opt, and the mask is exactly Offset.
  // CHECK: OpImageGather %v4float {{%[0-9]+}} {{%[0-9]+}} %int_0 Offset {{%[0-9]+$}}
  float4 g = t.Gather(gSampler, float2(0.1, 0.2), dynamicOffset);

  // ... and a constant offset keeps ConstOffset.
  // CHECK: OpImageGather %v4float {{%[0-9]+}} {{%[0-9]+}} %int_0 ConstOffset {{%[0-9]+$}}
  float4 c = t.Gather(gSampler, float2(0.1, 0.2), int2(1, 2));

  // Rule 2: "%" survives as OpSRem, and never becomes OpSMod.
  // CHECK: OpSRem %int
  // CHECK-NOT: OpSMod
  outI[2] = a % b;

  // A negative operand survives as OpSNegate feeding OpSRem, which is what makes
  // the result well defined only from maintenance8 onwards.
  // CHECK: [[NEG:%[0-9]+]] = OpSNegate %int
  // CHECK: [[REM:%[0-9]+]] = OpSRem %int [[NEG]]
  // CHECK: [[PTR:%[0-9]+]] = OpAccessChain %_ptr_Uniform_int %outI %int_0 %uint_3
  // CHECK: OpStore [[PTR]] [[REM]]
  outI[3] = -a % b;

  return g + c;
}

// Anchored negative: the module must not acquire any maintenance8 surface - the
// relaxation has no module-level representation, so an OpExtension or capability
// naming it would be a regression, not a feature.
// CHECK: OpStore %out_var_SV_Target
// CHECK-NOT: maintenance8
// CHECK-NOT: OpSMod
// CHECK-NOT: OpImage
// CHECK: OpFunctionEnd
