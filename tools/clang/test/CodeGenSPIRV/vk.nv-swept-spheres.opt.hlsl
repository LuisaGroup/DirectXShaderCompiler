// RUN: %dxc -T cs_6_5 -E main -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_NV_linear_swept_spheres %s | FileCheck %s
//
// SPV_NV_linear_swept_spheres after legalization and optimization (G27/L6).
//
// Without -fcgl the module goes through legalization (which inlines the header
// wrappers), spirv-opt and the capability trimming pass. Two things can go wrong
// only here: the optimizer drops or rewrites an accessor (the calls return values
// that are read into a store, but a future DCE change could still remove one), or
// the trimming pass removes RayTracingSpheresGeometryNV from a module that still
// uses it, which the validator would then reject - so this file compiling at all
// is also a validity check without -Vd.
//
// What must survive: the capability, the extension, and all the accessors of the
// source shader, all reading the one ray query object of the entry point - which
// is also the evidence that the wrapper functions are gone.
#include <vk/nv/linear_swept_spheres.h>

RaytracingAccelerationStructure Scene : register(t0);
RWStructuredBuffer<float> Out : register(u0);

[numThreads(1, 1, 1)]
void main() {
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
  RayDesc ray = {float3(0, 0, 0), 0.0f, float3(0, 0, 1), 100.0f};
  q.TraceRayInline(Scene, RAY_FLAG_NONE, 0xFF, ray);
  while (q.Proceed()) {
    Out[1] = vk::nv::RayQueryIsCandidateSphereHit(q) ? 1.0 : 0.0;
    Out[2] = vk::nv::RayQueryGetCandidateIntersectionSpherePosition(q).x;
  }
  Out[0] = vk::nv::RayQueryGetCommittedIntersectionSpherePosition(q).x +
           vk::nv::RayQueryGetCommittedIntersectionSphereRadius(q);
  Out[3] = vk::nv::RayQueryIsCommittedSphereHit(q) ? 1.0 : 0.0;
  Out[4] = vk::nv::RayQueryGetIntersectionSphereRadius(
      q, vk::nv::SphereIntersectionCandidate);
}

// The capability and the extension survive both passes, and the other half of
// the extension is still not declared.
// CHECK: OpCapability RayQueryKHR
// CHECK-NOT: OpCapability RayTracingLinearSweptSpheresGeometryNV
// CHECK: OpCapability RayTracingSpheresGeometryNV
// CHECK: OpExtension "SPV_NV_linear_swept_spheres"
// CHECK: OpMemoryModel Logical GLSL450

// Only the entry point is left: legalization inlined every wrapper.
// CHECK: %main = OpFunction
// CHECK-NOT: = OpFunction
// CHECK: [[RQ:%[0-9A-Za-z_]+]] = OpVariable %_ptr_Function_rayQueryKHR Function

// All accessors still read that one object with the selector the source asked
// for: candidate and committed for the wrappers, then the raw candidate call.
// CHECK: OpRayQueryIsSphereHitNV %bool [[RQ]] %uint_0
// CHECK: OpRayQueryGetIntersectionSpherePositionNV %v3float [[RQ]] %uint_0
// CHECK: OpRayQueryGetIntersectionSpherePositionNV %v3float [[RQ]] %uint_1
// CHECK: OpRayQueryGetIntersectionSphereRadiusNV %float [[RQ]] %uint_1
// CHECK: OpRayQueryIsSphereHitNV %bool [[RQ]] %uint_1
// CHECK: OpRayQueryGetIntersectionSphereRadiusNV %float [[RQ]] %uint_0
// CHECK: OpFunctionEnd
