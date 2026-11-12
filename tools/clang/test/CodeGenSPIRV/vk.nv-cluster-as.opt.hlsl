// RUN: %dxc -T cs_6_5 -E main -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_NV_cluster_acceleration_structure %s | FileCheck %s

// SPV_NV_cluster_acceleration_structure after legalization and optimization
// (G26/L6).
//
// Without -fcgl the module goes through legalization (which inlines the two
// header wrappers), spirv-opt and the capability trimming pass. Two things can
// go wrong only here: the optimizer drops or rewrites the accessor, or the
// trimming pass removes RayTracingClusterAccelerationStructureNV from a module
// that still uses it (which the validator would then reject, so this file
// compiling at all is also a validity check without -Vd).
//
// What must survive: the capability, the extension, and all four accessors of the
// source shader, all reading the one ray query object of the entry point - which
// is also the evidence that the wrapper functions are gone.

#include <vk/nv/cluster_as.h>

RaytracingAccelerationStructure Scene : register(t0);
RWStructuredBuffer<uint> Out : register(u0);

[numThreads(1, 1, 1)]
void main() {
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
  RayDesc ray = {float3(0, 0, 0), 0.0f, float3(0, 0, 1), 100.0f};
  q.TraceRayInline(Scene, RAY_FLAG_NONE, 0xFF, ray);

  while (q.Proceed()) {
    Out[1] = vk::nv::RayQueryGetCandidateIntersectionClusterId(q);
  }

  Out[0] = vk::nv::RayQueryGetCommittedIntersectionClusterId(q);
  Out[2] = vk::nv::RayQueryGetIntersectionClusterId(q, vk::nv::IntersectionCommitted);
  Out[3] = vk::nv::RayQueryGetIntersectionClusterId(q, vk::nv::IntersectionCandidate);
}

// The capability and the extension survive both passes.
// CHECK: OpCapability RayTracingClusterAccelerationStructureNV
// CHECK: OpExtension "SPV_NV_cluster_acceleration_structure"

// Only the entry point is left: legalization inlined both wrappers.
// CHECK: %main = OpFunction
// CHECK-NOT: = OpFunction
// CHECK: [[RQ:%[0-9A-Za-z_]+]] = OpVariable %_ptr_Function_rayQueryKHR Function

// All four accessors still read that one object, with the selectors the source
// asked for: candidate and committed for the wrappers, then the two raw calls.
// CHECK: OpRayQueryGetIntersectionClusterIdNV %uint [[RQ]] %uint_0
// CHECK: OpRayQueryGetIntersectionClusterIdNV %uint [[RQ]] %uint_1
// CHECK: OpRayQueryGetIntersectionClusterIdNV %uint [[RQ]] %uint_1
// CHECK: OpRayQueryGetIntersectionClusterIdNV %uint [[RQ]] %uint_0
