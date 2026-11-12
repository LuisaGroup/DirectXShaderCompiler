// RUN: %dxc -T cs_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_NV_linear_swept_spheres %s | FileCheck %s
//
// SPV_NV_linear_swept_spheres: the sphere ray query accessors, the
// RayTracingSpheresGeometryNV capability and the extension (G27/L0, G27/L1,
// G27/L2). L3 is implicit: dxc validates every module it emits unless -Vd is
// given, so this file compiling is the validity gate. The accessors are
// header-only (DXR has no sphere geometry, so they are not RayQuery methods);
// see <vk/nv/linear_swept_spheres.h>.
//
// This file covers the *sphere* half of the extension. The linear-swept-sphere
// half selects a different capability and is asserted separately in
// vk.nv-swept-spheres-lss.hlsl, so that a "declare both capabilities" bug cannot
// pass: here the LSS capability must be absent, there the sphere capability must
// be absent.
//
// The instructions are OpRayQueryGetIntersectionSpherePositionNV (5427),
// OpRayQueryGetIntersectionSphereRadiusNV (5428) and OpRayQueryIsSphereHitNV
// (5438), all with operands (IdResultType, IdResult, IdRef RayQuery, IdRef
// Intersection) - the same shape as OpRayQueryGetIntersectionInstanceIdKHR, with
// a constant 32-bit integer in place of the candidate/committed selector. The
// result types are fixed by the extension and asserted below (%v3float for a
// position, %float for a radius, %bool for the predicate); SPIRV-Tools rejects
// any other result type ("expected Result Type to be 32-bit float 3-component
// vector type", ...), which is why the header declares exactly these.
//
// Anti-false-green note: this is a pure encoding test. No driver runs it, and for
// an acceleration structure without sphere geometry the values are undefined and
// the predicate is false. Nothing here proves the values are meaningful.
//
// Included twice on purpose: the header has to be guarded, and including it must
// not add anything to the module by itself (see the off-path test).
#include <vk/nv/linear_swept_spheres.h>
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
    Out[1] = vk::nv::RayQueryIsCandidateSphereHit(q) ? 1.0 : 0.0;
    Out[2] = vk::nv::RayQueryGetCandidateIntersectionSpherePosition(q).x +
             vk::nv::RayQueryGetCandidateIntersectionSphereRadius(q);
  }
  // Committed intersection: meaningful once the traversal has stopped.
  Out[0] = vk::nv::RayQueryGetCommittedIntersectionSpherePosition(q).x +
           vk::nv::RayQueryGetCommittedIntersectionSphereRadius(q);
  Out[3] = vk::nv::RayQueryIsCommittedSphereHit(q) ? 1.0 : 0.0;
  // Raw form: the intersection selector is the caller's constant. Both selector
  // spellings must reach the operand as %uint_1 / %uint_0.
  Out[4] = vk::nv::RayQueryGetIntersectionSpherePosition(
               q, vk::nv::SphereIntersectionCommitted)
               .y;
  Out[5] = vk::nv::RayQueryGetIntersectionSphereRadius(
      q, vk::nv::SphereIntersectionCandidate);
  Out[6] = vk::nv::RayQueryIsSphereHit(q, vk::nv::SphereIntersectionCandidate)
               ? 1.0
               : 0.0;
}

// L1: the capability and the extension, once each, and the RayQueryKHR
// capability the ray query itself needs. They are emitted from the instruction
// by CapabilityVisitor (not by [[vk::ext_capability]]/[[vk::ext_extension]] on
// the header declaration), so they appear only when an accessor is used and only
// when -fspv-extension=SPV_NV_linear_swept_spheres permits it.
// CHECK: OpCapability RayQueryKHR
// CHECK-NOT: OpCapability RayTracingLinearSweptSpheresGeometryNV
// CHECK: OpCapability RayTracingSpheresGeometryNV
// The capability block is contiguous, so a duplicate would be right here. This
// also covers the whole block: the LSS capability of the other half of the
// extension must not be declared by a module that only reads spheres.
// CHECK-NOT: OpCapability RayTracingSpheresGeometryNV
// CHECK: OpExtension "SPV_KHR_ray_query"
// CHECK-NOT: OpCapability RayTracingLinearSweptSpheresGeometryNV
// CHECK: OpExtension "SPV_NV_linear_swept_spheres"
// CHECK-NOT: OpExtension "SPV_NV_linear_swept_spheres"
// CHECK: OpMemoryModel Logical GLSL450

// L2: the result types and the one ray query object, captured once. The ray
// query is passed by reference ([[vk::ext_reference]]), so every accessor reads
// the entry point's variable, not a copy.
// CHECK-DAG: [[FLOAT:%[0-9A-Za-z_]+]] = OpTypeFloat 32
// CHECK-DAG: [[V3FLOAT:%[0-9A-Za-z_]+]] = OpTypeVector [[FLOAT]] 3
// CHECK-DAG: [[BOOL:%[0-9A-Za-z_]+]] = OpTypeBool
// CHECK-DAG: [[RQ:%[0-9A-Za-z_]+]] = OpVariable %_ptr_Function_rayQueryKHR Function

// L0/L2: the wrappers reach the same instructions from main. The result type of
// each call is the accessor's result type, so a wrapper that returned the wrong
// type would already fail here.
// CHECK: OpFunctionCall %bool %vk__nv__RayQueryIsCandidateSphereHit [[RQ]]
// CHECK: OpFunctionCall [[V3FLOAT]] %vk__nv__RayQueryGetCandidateIntersectionSpherePosition [[RQ]]
// CHECK: OpFunctionCall [[FLOAT]] %vk__nv__RayQueryGetCandidateIntersectionSphereRadius [[RQ]]
// CHECK: OpFunctionCall [[V3FLOAT]] %vk__nv__RayQueryGetCommittedIntersectionSpherePosition [[RQ]]
// CHECK: OpFunctionCall [[FLOAT]] %vk__nv__RayQueryGetCommittedIntersectionSphereRadius [[RQ]]
// CHECK: OpFunctionCall %bool %vk__nv__RayQueryIsCommittedSphereHit [[RQ]]

// L2: the three raw calls from main, in source order. The intersection operand
// is the only thing that differs between the selector spellings, so a lowering
// that swapped or folded them cannot pass all three.
// CHECK: [[POS:%[0-9A-Za-z_]+]] = OpRayQueryGetIntersectionSpherePositionNV [[V3FLOAT]] [[RQ]] %uint_1
// CHECK: [[RAD:%[0-9A-Za-z_]+]] = OpRayQueryGetIntersectionSphereRadiusNV [[FLOAT]] [[RQ]] %uint_0
// CHECK: [[HIT:%[0-9A-Za-z_]+]] = OpRayQueryIsSphereHitNV [[BOOL]] [[RQ]] %uint_0
// The three result ids must be distinct: a lowering that reused one id would
// violate SSA (and the validator), but the CHECK lines above would still match.
// CHECK-NOT: [[POS]] = OpRayQueryGetIntersectionSphereRadiusNV

// L0/L2: the wrapper bodies. -fcgl keeps the wrappers as real functions and the
// selector each wrapper baked in is a constant; the operand is the wrapper's own
// ray query parameter, i.e. the object is passed as a pointer, not copied.
// CHECK: %vk__nv__RayQueryIsCandidateSphereHit = OpFunction %bool
// CHECK: [[ACQ:%[0-9A-Za-z_]+]] = OpFunctionParameter %_ptr_Function_rayQueryKHR
// CHECK: OpRayQueryIsSphereHitNV [[BOOL]] [[ACQ]] %uint_0
// CHECK: %vk__nv__RayQueryGetCandidateIntersectionSpherePosition = OpFunction [[V3FLOAT]]
// CHECK: [[APQ:%[0-9A-Za-z_]+]] = OpFunctionParameter %_ptr_Function_rayQueryKHR
// CHECK: OpRayQueryGetIntersectionSpherePositionNV [[V3FLOAT]] [[APQ]] %uint_0
// CHECK: %vk__nv__RayQueryGetCandidateIntersectionSphereRadius = OpFunction [[FLOAT]]
// CHECK: [[ARQ:%[0-9A-Za-z_]+]] = OpFunctionParameter %_ptr_Function_rayQueryKHR
// CHECK: OpRayQueryGetIntersectionSphereRadiusNV [[FLOAT]] [[ARQ]] %uint_0
// CHECK: %vk__nv__RayQueryGetCommittedIntersectionSpherePosition = OpFunction [[V3FLOAT]]
// CHECK: [[CPQ:%[0-9A-Za-z_]+]] = OpFunctionParameter %_ptr_Function_rayQueryKHR
// CHECK: OpRayQueryGetIntersectionSpherePositionNV [[V3FLOAT]] [[CPQ]] %uint_1
// CHECK: %vk__nv__RayQueryGetCommittedIntersectionSphereRadius = OpFunction [[FLOAT]]
// CHECK: [[CRQ:%[0-9A-Za-z_]+]] = OpFunctionParameter %_ptr_Function_rayQueryKHR
// CHECK: OpRayQueryGetIntersectionSphereRadiusNV [[FLOAT]] [[CRQ]] %uint_1
// CHECK: %vk__nv__RayQueryIsCommittedSphereHit = OpFunction %bool
// CHECK: [[CHQ:%[0-9A-Za-z_]+]] = OpFunctionParameter %_ptr_Function_rayQueryKHR
// CHECK: OpRayQueryIsSphereHitNV [[BOOL]] [[CHQ]] %uint_1
// No linear-swept-sphere instruction may be emitted by this half.
// CHECK-NOT: OpRayQueryIsLSSHitNV
// CHECK-NOT: OpRayQueryGetIntersectionLSSHitValueNV
// CHECK: OpFunctionEnd
