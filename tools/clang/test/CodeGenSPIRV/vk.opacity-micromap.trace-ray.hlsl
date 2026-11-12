// RUN: %dxc -T lib_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_KHR_opacity_micromap %s | FileCheck %s

// The same opt-in spelled as a RayFlags argument to TraceRay. The execution
// mode only affects ray query traversal, but it is derived from the flag
// wherever the flag appears, so a TraceRay-only shader declares it too and the
// ForceOpacityMicromap2StateKHR bit in OpTraceRayKHR stays valid.

// CHECK:      OpCapability RayTracingOpacityMicromapExecutionModeKHR
// CHECK:      OpCapability RayTracingOpacityMicromapKHR
// CHECK:      OpExtension "SPV_KHR_opacity_micromap"
// CHECK:      OpExecutionModeId %main OpacityMicromapIdKHR [[ENABLE:%[0-9a-zA-Z_]+]]
// CHECK:      OpDecorate [[ENABLE]] SpecId 0
// CHECK:      [[ENABLE]] = OpSpecConstantTrue %bool
// CHECK:      OpTraceRayKHR {{%[0-9a-zA-Z_]+}} %uint_1024

RaytracingAccelerationStructure AS : register(t0);

struct Payload {
  float4 color;
};

[shader("raygeneration")]
void main() {
  Payload payload = { float4(0, 0, 0, 0) };
  RayDesc ray = { float3(0, 0, 0), 0.0f, float3(1, 0, 0), 100.0f };
  TraceRay(AS, RAY_FLAG_FORCE_OMM_2_STATE, 0xFF, 0, 1, 0, ray, payload);
}
