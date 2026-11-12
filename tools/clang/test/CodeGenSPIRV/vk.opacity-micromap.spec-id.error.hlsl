// RUN: not %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_KHR_ray_tracing -fvk-opacity-micromap-spec-id=7 %s 2>&1 | FileCheck %s
// RUN: not %dxc -T lib_6_9 -E main -fspv-extension=SPV_KHR_opacity_micromap -fvk-opacity-micromap-spec-id=7 %s 2>&1 | FileCheck %s --check-prefix=NOSPIRV

// L4: -fvk-opacity-micromap-spec-id is only meaningful together with the
// extension that emits the execution mode, and it is a -spirv option.
// CHECK:   requires -fspv-extension=SPV_KHR_opacity_micromap
// NOSPIRV: requires -spirv

RaytracingAccelerationStructure AS : register(t0);

[shader("raygeneration")]
void main() {
  RayDesc ray = { float3(0, 0, 0), 0.0f, float3(1, 0, 0), 100.0f };
  RayQuery<RAY_FLAG_NONE, RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS> q;
  q.TraceRayInline(AS, RAY_FLAG_FORCE_OMM_2_STATE, 0xFF, ray);
  q.Proceed();
}
