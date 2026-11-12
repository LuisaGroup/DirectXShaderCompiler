// RUN: %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_KHR_opacity_micromap %s | FileCheck %s
// RUN: %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_KHR_opacity_micromap -fvk-opacity-micromap-spec-id=7 %s | FileCheck %s --check-prefix=SPECID

// SPV_KHR_opacity_micromap expresses the opacity-micromap opt-in as the
// module-level OpacityMicromapIdKHR execution mode, whose operand is a
// specialization constant, while HLSL expresses it as the
// RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS / RAY_FLAG_FORCE_OMM_2_STATE ray flags.
// The execution mode is therefore derived from the flag, once per entry point.

// L1: exactly one capability and one OpExtension. The EXT spelling of the same
// extension is not emitted: a module that uses OpacityMicromapIdKHR must
// declare the KHR spelling.
// CHECK:      OpCapability RayTracingOpacityMicromapExecutionModeKHR
// CHECK:      OpCapability RayTracingOpacityMicromapKHR
// CHECK-NOT:  RayTracingOpacityMicromapExecutionModeEXT
// CHECK:      OpExtension "SPV_KHR_opacity_micromap"
// CHECK-NOT:  OpExtension "SPV_EXT_opacity_micromap"

// L2: the mode is emitted with OpExecutionModeId (id operand), not with the
// literal-operand OpExecutionMode form, and it is attached to the entry point
// that requested it only.
// CHECK:      OpExecutionModeId %main OpacityMicromapIdKHR [[ENABLE:%[0-9a-zA-Z_]+]]
// CHECK-NOT:  OpExecutionModeId %noOpacityMicromap OpacityMicromapIdKHR
// CHECK-NOT:  OpExecutionMode %main OpacityMicromapIdKHR
// CHECK-NOT:  OpExecutionModeId

// L2: the operand is a boolean specialization constant with a SpecId the host
// can specialize, and its default is true.
// CHECK:      OpDecorate [[ENABLE]] SpecId 0
// CHECK:      [[ENABLE]] = OpSpecConstantTrue %bool

// The same specialization constant, moved to SpecId 7 by
// -fvk-opacity-micromap-spec-id=7.
// SPECID:     OpDecorate [[SENABLE:%[0-9a-zA-Z_]+]] SpecId 7
// SPECID:     [[SENABLE]] = OpSpecConstantTrue %bool

// The HLSL flag itself keeps reaching the ray-flags operand unchanged: the
// 0x400 bit is SPIR-V's ForceOpacityMicromap2StateKHR.
// CHECK:      [[FLAGS:%[0-9a-zA-Z_]+]] = OpBitwiseOr %uint %uint_0 %uint_1024
// CHECK:      OpRayQueryInitializeKHR {{%[0-9a-zA-Z_]+}} {{%[0-9a-zA-Z_]+}} [[FLAGS]]

RaytracingAccelerationStructure AS : register(t0);

[shader("raygeneration")]
void main() {
  RayDesc ray = { float3(0, 0, 0), 0.0f, float3(1, 0, 0), 100.0f };
  RayQuery<RAY_FLAG_NONE, RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS> q;
  q.TraceRayInline(AS, RAY_FLAG_FORCE_OMM_2_STATE, 0xFF, ray);
  q.Proceed();
}

// No opacity-micromap flag: no execution mode for this entry point.
[shader("raygeneration")]
void noOpacityMicromap() {
  RayDesc ray = { float3(0, 0, 0), 0.0f, float3(1, 0, 0), 100.0f };
  RayQuery<RAY_FLAG_NONE> q;
  q.TraceRayInline(AS, RAY_FLAG_NONE, 0xFF, ray);
  q.Proceed();
}
