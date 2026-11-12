// RUN: %dxc -T cs_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_NV_linear_swept_spheres %s | FileCheck %s
//
// SPV_NV_linear_swept_spheres: the linear-swept-sphere ray query accessors and
// the RayTracingLinearSweptSpheresGeometryNV capability (G27/L1.lss, G27/L2).
//
// This file covers the *linear-swept-sphere* half of the extension and is the
// mirror image of vk.nv-swept-spheres.hlsl: it must declare
// RayTracingLinearSweptSpheresGeometryNV and must NOT declare
// RayTracingSpheresGeometryNV. The pair of files is what proves the capability
// selection is a decision and not a constant - declaring both capabilities
// unconditionally (the failure mode the plan calls "the most likely bug") breaks
// one of the two. VK_NV_ray_tracing_linear_swept_spheres exposes spheres and
// linear swept spheres as two independent device features, and SPIR-V mirrors
// that with two capabilities, so a module that only reads the parameters of a
// swept sphere has to stay loadable on a device that does not enable `spheres`.
//
// The instructions asserted here are OpRayQueryGetIntersectionLSSHitValueNV
// (5431, a 32-bit float: where along the segment the hit happened) and
// OpRayQueryIsLSSHitNV (5439, a bool), both with operands (IdResultType,
// IdResult, IdRef RayQuery, IdRef Intersection).
//
// Note that this header is included together with <vk/nv/cluster_as.h>: the two
// vk::nv headers have to coexist in one translation unit (their intersection
// selectors are spelled differently for exactly that reason). Including
// cluster_as.h adds nothing to the module as long as no cluster-ID accessor is
// called, which the CHECK-NOT lines below also pin down.
#include <vk/nv/cluster_as.h>
#include <vk/nv/linear_swept_spheres.h>

RaytracingAccelerationStructure Scene : register(t0);
RWStructuredBuffer<float> Out : register(u0);

[numThreads(1, 1, 1)]
void main() {
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
  RayDesc ray = {float3(0, 0, 0), 0.0f, float3(0, 0, 1), 100.0f};
  q.TraceRayInline(Scene, RAY_FLAG_NONE, 0xFF, ray);
  while (q.Proceed()) {
    // Candidate intersection: only meaningful inside the Proceed() loop.
    Out[1] = vk::nv::RayQueryIsCandidateLSSHit(q) ? 1.0 : 0.0;
    Out[2] = vk::nv::RayQueryGetCandidateIntersectionLSSHitValue(q);
  }
  // Committed intersection: meaningful once the traversal has stopped.
  Out[0] = vk::nv::RayQueryGetCommittedIntersectionLSSHitValue(q);
  Out[3] = vk::nv::RayQueryIsCommittedLSSHit(q) ? 1.0 : 0.0;
  // Raw form: the intersection selector is the caller's constant.
  Out[4] = vk::nv::RayQueryGetIntersectionLSSHitValue(
      q, vk::nv::SphereIntersectionCommitted);
  Out[5] =
      vk::nv::RayQueryIsLSSHit(q, vk::nv::SphereIntersectionCandidate) ? 1.0
                                                                     : 0.0;
}

// L1: the linear-swept-sphere capability and the extension, once each. The
// capability comes from the instruction (CapabilityVisitor), not from
// [[vk::ext_capability]] on the header declaration.
// CHECK: OpCapability RayQueryKHR
// CHECK-NOT: OpCapability RayTracingSpheresGeometryNV
// CHECK: OpCapability RayTracingLinearSweptSpheresGeometryNV
// The capability block is contiguous, so a duplicate would be right here, and
// the sphere capability of the other half of the extension must not be declared
// by a module that only reads linear swept spheres.
// CHECK-NOT: OpCapability RayTracingLinearSweptSpheresGeometryNV
// CHECK: OpExtension "SPV_KHR_ray_query"
// CHECK-NOT: OpCapability RayTracingSpheresGeometryNV
// CHECK: OpExtension "SPV_NV_linear_swept_spheres"
// CHECK-NOT: OpExtension "SPV_NV_linear_swept_spheres"
// Including <vk/nv/cluster_as.h> must not pull in the cluster extension.
// CHECK-NOT: OpExtension "SPV_NV_cluster_acceleration_structure"
// CHECK: OpMemoryModel Logical GLSL450

// L2: the two result types and the one ray query object, captured once.
// CHECK-DAG: [[FLOAT:%[0-9A-Za-z_]+]] = OpTypeFloat 32
// CHECK-DAG: [[BOOL:%[0-9A-Za-z_]+]] = OpTypeBool
// CHECK-DAG: [[RQ:%[0-9A-Za-z_]+]] = OpVariable %_ptr_Function_rayQueryKHR Function

// L2: the two raw calls from main, in source order, with their selectors.
// CHECK: OpRayQueryGetIntersectionLSSHitValueNV [[FLOAT]] [[RQ]] %uint_1
// CHECK: OpRayQueryIsLSSHitNV [[BOOL]] [[RQ]] %uint_0

// L0/L2: the wrapper bodies. -fcgl keeps the wrappers as real functions and the
// selector each wrapper baked in is a constant; the operand is the wrapper's own
// ray query parameter.
// CHECK: %vk__nv__RayQueryIsCandidateLSSHit = OpFunction %bool
// CHECK: OpRayQueryIsLSSHitNV [[BOOL]] %{{[0-9A-Za-z_]+}} %uint_0
// CHECK: %vk__nv__RayQueryGetCandidateIntersectionLSSHitValue = OpFunction [[FLOAT]]
// CHECK: OpRayQueryGetIntersectionLSSHitValueNV [[FLOAT]] %{{[0-9A-Za-z_]+}} %uint_0
// CHECK: %vk__nv__RayQueryGetCommittedIntersectionLSSHitValue = OpFunction [[FLOAT]]
// CHECK: OpRayQueryGetIntersectionLSSHitValueNV [[FLOAT]] %{{[0-9A-Za-z_]+}} %uint_1
// CHECK: %vk__nv__RayQueryIsCommittedLSSHit = OpFunction %bool
// CHECK: OpRayQueryIsLSSHitNV [[BOOL]] %{{[0-9A-Za-z_]+}} %uint_1
// No sphere-geometry instruction and no cluster-ID instruction may appear in
// this half, and the header include must not have emitted the cluster accessor.
// CHECK-NOT: OpRayQueryGetIntersectionSpherePositionNV
// CHECK-NOT: OpRayQueryGetIntersectionSphereRadiusNV
// CHECK-NOT: OpRayQueryIsSphereHitNV
// CHECK-NOT: OpRayQueryGetIntersectionClusterIdNV
// CHECK: OpFunctionEnd
