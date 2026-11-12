// RUN: %dxc -T lib_6_9 -E firstEntry -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_KHR_opacity_micromap %s | FileCheck %s

// The opacity-micromap request lives in a helper function here, so the
// execution mode has to be attached to every entry point that reaches that
// helper - and only to those. All of them share one specialization constant.

// CHECK:      OpExecutionModeId %firstEntry OpacityMicromapIdKHR [[ENABLE:%[0-9a-zA-Z_]+]]
// CHECK-NEXT: OpExecutionModeId %secondEntry OpacityMicromapIdKHR [[ENABLE]]
// CHECK-NOT:  OpExecutionModeId
// CHECK-NOT:  OpExecutionMode
// CHECK:      OpDecorate [[ENABLE]] SpecId 0
// CHECK:      [[ENABLE]] = OpSpecConstantTrue %bool

RaytracingAccelerationStructure AS : register(t0);

// Requests opacity micromaps; reached from firstEntry and secondEntry.
void traceWithOpacityMicromap(RayDesc ray) {
  RayQuery<RAY_FLAG_NONE, RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS> q;
  q.TraceRayInline(AS, RAY_FLAG_FORCE_OMM_2_STATE, 0xFF, ray);
  q.Proceed();
}

// Does not request it; the only ray query reached from thirdEntry.
void tracePlain(RayDesc ray) {
  RayQuery<RAY_FLAG_NONE> q;
  q.TraceRayInline(AS, RAY_FLAG_NONE, 0xFF, ray);
  q.Proceed();
}

[shader("raygeneration")]
void firstEntry() {
  RayDesc ray = { float3(0, 0, 0), 0.0f, float3(1, 0, 0), 100.0f };
  traceWithOpacityMicromap(ray);
}

[shader("raygeneration")]
void secondEntry() {
  RayDesc ray = { float3(0, 0, 0), 0.0f, float3(1, 0, 0), 100.0f };
  tracePlain(ray);
  traceWithOpacityMicromap(ray);
}

[shader("raygeneration")]
void thirdEntry() {
  RayDesc ray = { float3(0, 0, 0), 0.0f, float3(1, 0, 0), 100.0f };
  tracePlain(ray);
}
