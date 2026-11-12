// RUN: %dxc -T cs_6_5 -E main -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_NV_cluster_acceleration_structure %s

// Cluster IDs with VK_NV_cluster_acceleration_structure /
// SPV_NV_cluster_acceleration_structure.
//
// A cluster acceleration structure groups the triangles of a mesh into clusters
// and gives every cluster an identity. Building the clusters is a host-side
// operation; the only thing a shader sees is the cluster ID of an intersection,
// which is what this example reads:
//
//   %clusterId = OpRayQueryGetIntersectionClusterIdNV %uint %query %uint_1
//
// A renderer uses that identity to pick the material, the level of detail or the
// shading bin of the triangle that was hit, instead of deriving that decision
// from the primitive index - the primitive index is unique per triangle, while
// the cluster ID is shared by every triangle of one cluster, so the lookup stays
// small and cache friendly.
//
// The accessors live in <vk/nv/cluster_as.h>. They are free functions rather
// than RayQuery methods because DXR has no cluster acceleration structures: the
// RayQuery method table is shared between the DXIL and the SPIR-V backends, and a
// method would need a DXIL lowering that cannot exist. There is no DXIL code
// path for them either: a DXIL compile ignores the vk:: attributes on the
// declaration (-Wignored-attributes) and leaves an accessor with no definition,
// which is an error in a non-library profile.
//
// Required from the host (the compiler cannot check any of it):
//  * Vulkan device extension VK_NV_cluster_acceleration_structure (enable
//    VK_NV_CLUSTER_ACCELERATION_STRUCTURE_EXTENSION_NAME at vkCreateDevice),
//  * feature bit VkPhysicalDeviceClusterAccelerationStructureFeaturesNV::
//    clusterAccelerationStructure (query it with vkGetPhysicalDeviceFeatures2 and
//    chain the structure into VkDeviceCreateInfo::pNext with the bit set to
//    VK_TRUE),
//  * an acceleration structure built with clusters:
//    vkGetClusterAccelerationStructureBuildSizesNV plus
//    vkCmdBuildClusterAccelerationStructureIndirectNV build the cluster level,
//    and the ray traced scene has to reference it,
//  * SPIR-V 1.4 / Vulkan 1.2 or newer for ray queries (SPV_KHR_ray_query is
//    enabled by default; SPV_NV_cluster_acceleration_structure has to be asked
//    for with -fspv-extension=).
//
// The value is undefined for geometry built from ordinary triangles: the
// instruction is always encodable, but only a cluster acceleration structure
// gives the result a meaning. The compiler cannot detect the difference, so the
// shader author has to know what the acceleration structure contains.
//
// See the "Cluster acceleration structures" section of docs/SPIR-V.rst and
// tools/clang/test/CodeGenSPIRV/vk.nv-cluster-as*.hlsl.

#include <vk/nv/cluster_as.h>

// One entry per cluster: what the renderer needs to shade a hit that belongs to
// that cluster. The host sizes this table to the number of clusters it built.
struct ClusterShading {
  uint albedoIndex;
  uint emissiveIndex;
};

RaytracingAccelerationStructure Scene : register(t0);
StructuredBuffer<ClusterShading> ClusterTable : register(t1);

// (cluster ID, albedo index) per traced pixel, 1920 pixels per row.
RWStructuredBuffer<uint2> Output : register(u0);

[numThreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  RayDesc ray;
  ray.Origin = float3(tid.xy, 0.0f);
  ray.Direction = float3(0.0f, 0.0f, 1.0f);
  ray.TMin = 0.0f;
  ray.TMax = 1.0e4f;

  RayQuery<RAY_FLAG_FORCE_OPAQUE> query;
  query.TraceRayInline(Scene, RAY_FLAG_NONE, 0xFF, ray);

  // Candidate intersections are visited by the Proceed() loop, and their cluster
  // ID is available there too:
  //   clusterId = vk::nv::RayQueryGetCandidateIntersectionClusterId(query);
  // which is what a "reject this cluster" decision would use. This example only
  // needs the intersection that survives the traversal.
  while (query.Proceed()) {
  }

  uint clusterId = 0xFFFFFFFFu;
  uint albedoIndex = 0xFFFFFFFFu;
  if (query.CommittedStatus() == COMMITTED_TRIANGLE_HIT) {
    // One OpRayQueryGetIntersectionClusterIdNV with the committed-intersection
    // selector (%uint_1).
    clusterId = vk::nv::RayQueryGetCommittedIntersectionClusterId(query);
    // Every triangle of a cluster reports the same ID, so this lookup is shared
    // by the whole cluster. The table must be large enough for every ID the
    // acceleration structure can produce; the shader cannot bounds-check that
    // because the cluster count is a host property.
    ClusterShading shading = ClusterTable[clusterId];
    albedoIndex = shading.albedoIndex;
  }

  Output[tid.x + tid.y * 1920] = uint2(clusterId, albedoIndex);
}
