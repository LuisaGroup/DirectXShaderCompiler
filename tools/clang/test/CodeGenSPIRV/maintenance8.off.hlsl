// RUN: %dxc -T ps_6_0 -E main -fcgl  %s -spirv | FileCheck %s

// G31/L5: off-path identity. VK_KHR_maintenance8 has no switch of its own: it is
// a relaxation of the Vulkan SPIR-V *environment*, adopted by the device feature
// VkPhysicalDeviceMaintenance8FeaturesKHR::maintenance8, and it changes neither
// the instruction set nor the module header. There is therefore no flag to turn
// on, and this file states the "off" half explicitly: with no option at all, the
// module must contain no maintenance8 surface whatsoever - no
// OpExtension "SPV_KHR_maintenance8" (the name is not registered in SPIR-V, see
// docs/SPIR-V.rst), no new capability - and the two encodings the extension is
// about must already be the ones DXC emits.
//
// This is the audit's control group: it is the same statement the pre-existing
// texture.sample.variable-offset.hlsl, texture.sample-offset.with.loop-unroll.hlsl
// and texture.sample.offset.needs.legalization*.hlsl make, re-stated for the two
// maintenance8 rules together. Those files are deliberately left unmodified.
//
// Every assertion is anchored: the CHECK-NOTs sit between the OpCapability and
// OpMemoryModel lines and before the OpFunctionEnd, so none of them is a
// trailing, vacuous directive.

SamplerState gSampler : register(s5);
Texture2D<float4> t : register(t1);
RWStructuredBuffer<int> outI : register(u0);

float4 main(int2 dynamicOffset : A) : SV_Target {
  int a = outI[0];
  int b = outI[1];

  // CHECK: OpCapability Shader
  // CHECK-NOT: OpExtension "SPV_KHR_maintenance8"
  // CHECK: OpMemoryModel Logical GLSL450

  // Rule 1 keeps its pre-existing encoding in both directions: a dynamic offset
  // is Offset, a constant offset is ConstOffset.
  // CHECK: [[DYN:%[0-9]+]] = OpLoad %v2int %dynamicOffset
  // CHECK: OpImageSampleImplicitLod %v4float {{%[0-9]+}} {{%[0-9]+}} Offset [[DYN]]{{$}}
  float4 s = t.Sample(gSampler, float2(0.1, 0.2), dynamicOffset);

  // CHECK: OpImageSampleImplicitLod %v4float {{%[0-9]+}} {{%[0-9]+}} ConstOffset {{%[0-9]+$}}
  float4 c = t.Sample(gSampler, float2(0.1, 0.2), int2(1, 2));

  // Rule 2 keeps its pre-existing encoding: HLSL "%" is OpSRem.
  // CHECK: [[A:%[0-9]+]] = OpLoad %int %a
  // CHECK: [[B:%[0-9]+]] = OpLoad %int %b
  // CHECK-NOT: OpSMod
  // CHECK: [[REM:%[0-9]+]] = OpSRem %int [[A]] [[B]]
  // CHECK: [[PTR:%[0-9]+]] = OpAccessChain %_ptr_Uniform_int %outI %int_0 %uint_2
  // CHECK: OpStore [[PTR]] [[REM]]
  outI[2] = a % b;

  return s + c;
}

// Anchored negative over the tail of the entry point: neither the extension
// string nor a capability carrying the name may appear, and no further image
// instruction may be emitted.
// CHECK-NOT: maintenance8
// CHECK-NOT: OpImageSampleImplicitLod
// CHECK: OpReturnValue
