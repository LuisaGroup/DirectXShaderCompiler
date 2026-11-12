// RUN: %dxc -T lib_6_9 -E main -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_KHR_opacity_micromap %s | FileCheck %s

// L6: without -fcgl the module goes through legalization, spirv-opt and the
// capability trimming pass. The execution mode, its capability and the
// specialization constant must all survive, and the module must still be
// accepted by SPIRV-Tools (validation is on: no -Vd).
// CHECK:      OpCapability RayTracingOpacityMicromapExecutionModeKHR
// CHECK:      OpExtension "SPV_KHR_opacity_micromap"
// CHECK:      OpExecutionModeId %main OpacityMicromapIdKHR [[ENABLE:%[0-9a-zA-Z_]+]]
// CHECK:      OpDecorate [[ENABLE]] SpecId 0
// CHECK:      [[ENABLE]] = OpSpecConstantTrue %bool
// CHECK:      OpRayQueryInitializeKHR {{%[0-9a-zA-Z_]+}} {{%[0-9a-zA-Z_]+}} %uint_1024

RaytracingAccelerationStructure AS : register(t0);

[shader("raygeneration")]
void main() {
  RayDesc ray = { float3(0, 0, 0), 0.0f, float3(1, 0, 0), 100.0f };
  RayQuery<RAY_FLAG_NONE, RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS> q;
  q.TraceRayInline(AS, RAY_FLAG_FORCE_OMM_2_STATE, 0xFF, ray);
  q.Proceed();
}
