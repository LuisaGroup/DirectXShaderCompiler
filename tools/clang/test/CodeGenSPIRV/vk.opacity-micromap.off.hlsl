// RUN: %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_KHR_opacity_micromap %s | FileCheck %s --check-prefix=NOFLAG
// RUN: %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 %s | FileCheck %s --check-prefix=NOEXT

// L5: without the HLSL ray flag the extension is enabled but nothing is
// emitted, and without -fspv-extension=SPV_KHR_opacity_micromap even a shader
// that does request opacity micromaps keeps the pre-existing output. Both are
// asserted against the ray query initialization that is the anchor of the
// region.

// NOFLAG:      OpExtension "SPV_KHR_ray_query"
// NOFLAG-NOT:  OpCapability RayTracingOpacityMicromapExecutionModeKHR
// NOFLAG-NOT:  OpCapability RayTracingOpacityMicromapKHR
// NOFLAG-NOT:  OpExtension "SPV_KHR_opacity_micromap"
// NOFLAG-NOT:  OpExtension "SPV_EXT_opacity_micromap"
// NOFLAG:      OpEntryPoint RayGenerationKHR %main "main"
// NOFLAG-NOT:  OpExecutionMode
// NOFLAG-NOT:  OpExecutionModeId
// NOFLAG:      OpDecorate
// NOFLAG-NOT:  SpecId
// NOFLAG:      OpRayQueryInitializeKHR

// NOEXT:       OpExtension "SPV_KHR_ray_query"
// NOEXT-NOT:   OpCapability RayTracingOpacityMicromapExecutionModeKHR
// NOEXT-NOT:   OpCapability RayTracingOpacityMicromapKHR
// NOEXT-NOT:   OpExtension "SPV_KHR_opacity_micromap"
// NOEXT:       OpEntryPoint RayGenerationKHR %main "main"
// NOEXT-NOT:   OpExecutionModeId
// NOEXT-NOT:   SpecId
// NOEXT:       OpRayQueryInitializeKHR

RaytracingAccelerationStructure AS : register(t0);

[shader("raygeneration")]
void main() {
  RayDesc ray = { float3(0, 0, 0), 0.0f, float3(1, 0, 0), 100.0f };
  RayQuery<RAY_FLAG_NONE> q;
  q.TraceRayInline(AS, RAY_FLAG_NONE, 0xFF, ray);
  q.Proceed();
}
