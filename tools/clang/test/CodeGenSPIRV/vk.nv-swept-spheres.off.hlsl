// RUN: %dxc -T cs_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_NV_linear_swept_spheres %s | FileCheck %s --check-prefix=OFF
// RUN: %dxc -T cs_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 %s | FileCheck %s --check-prefix=OFF
//
// SPV_NV_linear_swept_spheres off path (G27/L5).
//
// The shader includes <vk/nv/linear_swept_spheres.h> but never touches sphere or
// linear-swept-sphere geometry. Nothing of the feature may appear in the module:
// no RayTracingSpheresGeometryNV / RayTracingLinearSweptSpheresGeometryNV
// capability, no OpExtension "SPV_NV_linear_swept_spheres", no
// OpRayQuery*Sphere*NV / OpRayQuery*LSS*NV instruction - and the ordinary
// RayQuery accessors must keep their exact pre-existing encoding.
//
// The first RUN line is the interesting one: the extension is enabled and still
// must not be declared, because declaring an extension a module does not use
// invites a driver to reject it for nothing (and the capability trimming pass
// would have to remove it again). The second RUN line is the default mode, where
// the extension is not enabled at all, so the header must also be harmless
// without it.
#include <vk/nv/linear_swept_spheres.h>

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
// OFF-NOT: OpCapability RayTracingSpheresGeometryNV
// OFF-NOT: OpCapability RayTracingLinearSweptSpheresGeometryNV
// OFF: OpExtension "SPV_KHR_ray_query"
// OFF-NOT: OpExtension "SPV_NV_linear_swept_spheres"
// OFF: OpMemoryModel Logical GLSL450

// The pre-existing accessors are untouched: same opcode, same result type, same
// candidate/committed selector as before the extension existed. Anchoring the
// CHECK-NOT lines between the two calls (rather than at end of file) limits them
// to the region that could contain a sphere accessor.
// OFF: [[RQ:%[0-9A-Za-z_]+]] = OpVariable %_ptr_Function_rayQueryKHR Function
// OFF: OpRayQueryGetIntersectionInstanceIdKHR %uint [[RQ]] %uint_0
// OFF-NOT: OpRayQueryGetIntersectionSpherePositionNV
// OFF-NOT: OpRayQueryGetIntersectionSphereRadiusNV
// OFF-NOT: OpRayQueryIsSphereHitNV
// OFF-NOT: OpRayQueryGetIntersectionLSSHitValueNV
// OFF-NOT: OpRayQueryIsLSSHitNV
// OFF: OpRayQueryGetIntersectionInstanceIdKHR %uint [[RQ]] %uint_1
// OFF-NOT: OpRayQueryGetIntersectionSpherePositionNV
// OFF-NOT: OpRayQueryGetIntersectionSphereRadiusNV
// OFF-NOT: OpRayQueryIsSphereHitNV
// OFF-NOT: OpRayQueryGetIntersectionLSSHitValueNV
// OFF-NOT: OpRayQueryIsLSSHitNV
// OFF: OpFunctionEnd
