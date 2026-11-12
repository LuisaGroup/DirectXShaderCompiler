// RUN: %dxc -T cs_6_5 -E main -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_NV_linear_swept_spheres %s

// Analytic spheres with VK_NV_ray_tracing_linear_swept_spheres /
// SPV_NV_linear_swept_spheres.
//
// VK_NV_ray_tracing_linear_swept_spheres adds two analytic geometry kinds to ray
// tracing: spheres (particles, froxels, point clouds) and linear swept spheres
// (hair, fur, curve primitives). Both are intersected analytically instead of
// being tessellated into triangles, so a ray query reports the geometry it hit as
// a sphere center and a radius (or as a swept segment with a per-endpoint radius
// and a hit value) instead of as a triangle or an AABB:
//
//   %center = OpRayQueryGetIntersectionSpherePositionNV %v3float %query %uint_1
//   %radius = OpRayQueryGetIntersectionSphereRadiusNV %float %query %uint_1
//   %isSphere = OpRayQueryIsSphereHitNV %bool %query %uint_1
//
// The accessors live in <vk/nv/linear_swept_spheres.h>. They are free functions
// rather than RayQuery methods because DXR has no sphere geometry: the RayQuery
// method table is shared between the DXIL and the SPIR-V backends, and a method
// would need a DXIL lowering that cannot exist. There is no DXIL code path for
// them either: a DXIL compile ignores the vk:: attributes on the declaration
// (-Wignored-attributes) and leaves an accessor with no definition, which is an
// error in a non-library profile.
//
// Which capability the module gets: the sphere accessors declare
// RayTracingSpheresGeometryNV and the linear-swept-sphere accessors declare
// RayTracingLinearSweptSpheresGeometryNV, because
// VkPhysicalDeviceRayTracingLinearSweptSpheresFeaturesNV::spheres and
// ::linearSweptSpheres are independent device features. This example only reads
// spheres, so the module declares only the sphere capability (plus
// OpExtension "SPV_NV_linear_swept_spheres", which both halves need).
//
// Required from the host (the compiler cannot check any of it):
//  * Vulkan device extension VK_NV_ray_tracing_linear_swept_spheres (enable
//    VK_NV_RAY_TRACING_LINEAR_SWEPT_SPHERES_EXTENSION_NAME at vkCreateDevice),
//  * feature bit VkPhysicalDeviceRayTracingLinearSweptSpheresFeaturesNV::spheres
//    (query it with vkGetPhysicalDeviceFeatures2 and chain the structure into
//    VkDeviceCreateInfo::pNext with the bit set to VK_TRUE); the
//    ::linearSweptSpheres bit is only needed by shaders that read swept spheres,
//  * an acceleration structure whose geometry descriptions use
//    VK_GEOMETRY_TYPE_SPHERES_NV: the build range is a
//    VkAccelerationStructureGeometrySpheresDataNV (vertex buffer of
//    VkAccelerationStructureGeometrySpheresDataNV::vertexData holding the sphere
//    centers, radius buffer, optional index buffer), packed into
//    VkAccelerationStructureGeometryKHR::geometry.spheres and referenced from
//    VkAccelerationStructureBuildGeometryInfoKHR. A scene without sphere geometry
//    still compiles and runs, but the accessor results are undefined and the
//    predicate is false.
//  * SPIR-V 1.4 / Vulkan 1.2 or newer for ray queries (SPV_KHR_ray_query has to
//    stay in the -fspv-extension allow-list;
//    SPV_NV_linear_swept_spheres has to be asked for with -fspv-extension=).
//
// See the "Linear swept spheres" section of docs/SPIR-V.rst and
// tools/clang/test/CodeGenSPIRV/vk.nv-swept-spheres*.hlsl.

#include <vk/nv/linear_swept_spheres.h>

// What the shader needs to shade a sphere hit. The sphere geometry itself lives in
// the acceleration structure; the shading parameters live in this table, indexed by
// the per-sphere instance ID the host assigned when it built the sphere geometry
// (AccelerationStructureInstanceKHR::instanceCustomIndex in the top level).
struct SphereShading {
  float3 albedo;
  float roughness;
};

RaytracingAccelerationStructure Scene : register(t0);
StructuredBuffer<SphereShading> SphereTable : register(t1);

// One shaded sample per traced ray.
RWStructuredBuffer<float4> Output : register(u0);

[numThreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  RayDesc ray;
  ray.Origin = float3(tid.xy, 0.0f);
  ray.Direction = float3(0.0f, 0.0f, 1.0f);
  ray.TMin = 0.0f;
  ray.TMax = 1.0e4f;

  RayQuery<RAY_FLAG_FORCE_OPAQUE> query;
  query.TraceRayInline(Scene, RAY_FLAG_NONE, 0xFF, ray);
  while (query.Proceed()) {
    // Candidate (frontier) intersections are visited here. The same accessors work
    // with the candidate selector, which is what a "skip this sphere" decision
    // would use:
    //   if (vk::nv::RayQueryIsCandidateSphereHit(query)) { ... }
  }

  float4 result = float4(0.0f, 0.0f, 0.0f, -1.0f);
  // Branch on IsSphereHit, not on CommittedStatus(): DXR has no sphere
  // intersection type, so CommittedStatus()/GetCandidateType() keep reporting the
  // triangle/AABB answer and are not a reliable way to tell sphere geometry apart.
  // The predicate is the extension's own answer and is false for every other
  // geometry kind.
  if (vk::nv::RayQueryIsCommittedSphereHit(query)) {
    // Center and radius of the sphere that was hit: one
    // OpRayQueryGetIntersectionSpherePositionNV (%v3float) and one
    // OpRayQueryGetIntersectionSphereRadiusNV (%float), both with the
    // committed-intersection selector (%uint_1).
    const float3 center = vk::nv::RayQueryGetCommittedIntersectionSpherePosition(query);
    const float radius = vk::nv::RayQueryGetCommittedIntersectionSphereRadius(query);

    // The hit point is not one of the sphere accessors: it is where the ray
    // reached the surface, i.e. origin + t * direction with t from the query.
    const float3 hitPoint = ray.Origin + query.CommittedRayT() * ray.Direction;
    // For a sphere the geometric normal is the normalized offset from the center,
    // which is why the position accessor is enough to shade the hit analytically -
    // no tessellated normals, no barycentric interpolation.
    const float3 normal = normalize(hitPoint - center);

    const uint instanceId = query.CommittedInstanceID();
    SphereShading shading = SphereTable[instanceId];
    const float nDotL = saturate(dot(normal, normalize(float3(0.4f, 0.7f, 0.5f))));
    result = float4(shading.albedo * nDotL, radius);
  }

  Output[tid.x + tid.y * 64] = result;
}
