// RUN: %dxc -T cs_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_NV_cluster_acceleration_structure %s | FileCheck %s --check-prefix=OFF
// RUN: %dxc -T cs_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 %s | FileCheck %s --check-prefix=OFF

// SPV_NV_cluster_acceleration_structure off path (G26/L5).
//
// The shader includes <vk/nv/cluster_as.h> but never reads a cluster ID. Nothing
// of the feature may appear in the module: no
// RayTracingClusterAccelerationStructureNV capability, no
// OpExtension "SPV_NV_cluster_acceleration_structure", no
// OpRayQueryGetIntersectionClusterIdNV - and the ordinary RayQuery accessors must
// keep their exact pre-existing encoding.
//
// The first RUN line is the interesting one: the extension is enabled and still
// must not be declared, because declaring an extension a module does not use
// invites a driver to reject it for nothing (and the capability trimming pass
// would have to remove it again). The second RUN line is the default mode, where
// the extension is not enabled at all.

#include <vk/nv/cluster_as.h>

RaytracingAccelerationStructure Scene : register(t0);
RWStructuredBuffer<uint> Out : register(u0);

[numThreads(1, 1, 1)]
void main() {
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
  RayDesc ray = {float3(0, 0, 0), 0.0f, float3(0, 0, 1), 100.0f};
  q.TraceRayInline(Scene, RAY_FLAG_NONE, 0xFF, ray);

  while (q.Proceed()) {
    Out[1] = q.CandidateInstanceIndex();
  }

  Out[0] = q.CommittedInstanceIndex();
}

// OFF: OpCapability RayQueryKHR
// OFF-NOT: OpCapability RayTracingClusterAccelerationStructureNV
// OFF: OpExtension "SPV_KHR_ray_query"
// OFF-NOT: OpExtension "SPV_NV_cluster_acceleration_structure"
// OFF: OpMemoryModel Logical GLSL450

// The pre-existing accessors are untouched: same opcode, same result type, same
// candidate/committed selector as before the extension existed.
// OFF: [[RQ:%[0-9A-Za-z_]+]] = OpVariable %_ptr_Function_rayQueryKHR Function
// OFF: OpRayQueryGetIntersectionInstanceIdKHR %uint [[RQ]] %uint_0
// OFF-NOT: OpRayQueryGetIntersectionClusterIdNV
// OFF: OpRayQueryGetIntersectionInstanceIdKHR %uint [[RQ]] %uint_1
// OFF-NOT: OpRayQueryGetIntersectionClusterIdNV
// OFF: OpFunctionEnd
