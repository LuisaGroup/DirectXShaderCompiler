// RUN: not %dxc -T cs_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 %s 2>&1 | FileCheck %s
// RUN: not %dxc -T cs_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query %s 2>&1 | FileCheck %s

// SPV_NV_cluster_acceleration_structure is opt-in (G26/L4).
//
// FeatureManager::enabledByDefault returns false for it, so a module that reads a
// cluster ID has to be asked for explicitly. The two RUN lines cover both ways of
// not asking:
//   * the default mode, where every extension that is not opt-in is allowed and
//     this one is not (first RUN line);
//   * an explicit allow-list that names another extension but not this one
//     (second RUN line). This is the half that proves the restriction is not
//     bypassable: the accessor must not smuggle the extension into the module
//     through [[vk::ext_extension]], which writes the OpExtension string without
//     consulting FeatureManager and would therefore pass both runs below.
//
// The capability is only ever emitted together with the extension, so a module
// that declared RayTracingClusterAccelerationStructureNV without its extension
// would also be rejected by SPIRV-Tools ("Capability
// RayTracingClusterAccelerationStructureNV is not allowed by Vulkan 1.2
// specification (or requires extension)"). Refusing at compile time is the
// useful error: the shader cannot work without
// VK_NV_cluster_acceleration_structure anyway.
//
// Both diagnostics come from the CapabilityVisitor, i.e. from the instruction
// this shader would have emitted, and point at the offending call. The header
// wrappers (vk::nv::RayQueryGetCommittedIntersectionClusterId and
// RayQueryGetCandidateIntersectionClusterId) produce the same diagnostic; they
// only move the reported location into the header.

#include <vk/nv/cluster_as.h>

RaytracingAccelerationStructure Scene : register(t0);
RWStructuredBuffer<uint> Out : register(u0);

[numThreads(1, 1, 1)]
void main() {
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
  RayDesc ray = {float3(0, 0, 0), 0.0f, float3(0, 0, 1), 100.0f};
  q.TraceRayInline(Scene, RAY_FLAG_NONE, 0xFF, ray);
  while (q.Proceed()) {
  }
  // CHECK: error: SPIR-V extension 'SPV_NV_cluster_acceleration_structure' required for OpRayQueryGetIntersectionClusterIdNV but not permitted to use
  Out[0] = vk::nv::RayQueryGetIntersectionClusterId(q, vk::nv::IntersectionCommitted);
  // CHECK: error: SPIR-V extension 'SPV_NV_cluster_acceleration_structure' required for OpRayQueryGetIntersectionClusterIdNV but not permitted to use
  Out[1] = vk::nv::RayQueryGetIntersectionClusterId(q, vk::nv::IntersectionCandidate);
}
