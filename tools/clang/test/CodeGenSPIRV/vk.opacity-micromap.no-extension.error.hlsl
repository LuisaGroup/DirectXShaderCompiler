// RUN: %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 %s 2>&1 | FileCheck %s

// L4: with the ray flag but without -fspv-extension=SPV_KHR_opacity_micromap
// the opt-in cannot be expressed, so it is reported instead of being silently
// dropped. The module itself is unchanged (see vk.opacity-micromap.off.hlsl).
// CHECK: warning: opacity micromap ray flag ignored; use -fspv-extension=SPV_KHR_opacity_micromap to emit the OpacityMicromapIdKHR execution mode

RaytracingAccelerationStructure AS : register(t0);

[shader("raygeneration")]
void main() {
  RayDesc ray = { float3(0, 0, 0), 0.0f, float3(1, 0, 0), 100.0f };
  RayQuery<RAY_FLAG_NONE, RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS> q;
  q.TraceRayInline(AS, RAY_FLAG_FORCE_OMM_2_STATE, 0xFF, ray);
  q.Proceed();
}
