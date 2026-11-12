// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Linear swept spheres: VK_NV_ray_tracing_linear_swept_spheres /
// SPV_NV_linear_swept_spheres.
//
// VK_NV_ray_tracing_linear_swept_spheres adds two analytic geometry kinds to
// ray tracing: spheres (particles, froxels, point clouds) and linear swept
// spheres (hair, fur, curve primitives). Both are hit analytically instead of
// being tessellated into triangles, so a ray query reports the geometry it hit
// as a position and a radius (a swept sphere also has a per-endpoint radius and
// a hit value that describes where along the segment the hit happened) rather
// than as a triangle or an AABB. Building such an acceleration structure is a
// host-side operation (VkAccelerationStructureGeometrySpheresDataNV and
// VkAccelerationStructureGeometryLinearSweptSpheresDataNV in the build
// geometry); the shader-visible part of the extension is the geometry of an
// intersection.
//
// The HLSL entry points below lower to the ray query accessors of the
// extension:
//
//   %p = OpRayQueryGetIntersectionSpherePositionNV %v3float %query %uint_1
//   %r = OpRayQueryGetIntersectionSphereRadiusNV %float %query %uint_1
//   %h = OpRayQueryIsSphereHitNV %bool %query %uint_0
//
// The operands are, in order, the ray query object and the intersection - the
// same shape as the already-supported
// OpRayQueryGetIntersectionInstanceIdKHR family. The intersection operand is 0
// for the candidate intersection and 1 for the committed one, and it is a
// constant 32-bit integer, so the two convenience wrappers exist to keep a
// computed value out of shader code. The result types are fixed by the
// extension: a 3-component 32-bit float vector for a position, a 32-bit float
// for a radius or a hit value, and a bool for the two predicates.
//
// The extension defines two capabilities, one per geometry kind:
// RayTracingSpheresGeometryNV (5418) for the sphere accessors and
// RayTracingLinearSweptSpheresGeometryNV (5419) for the linear-swept-sphere
// ones. They are selected per instruction, because
// VkPhysicalDeviceRayTracingLinearSweptSpheresFeaturesNV::spheres and
// ::linearSweptSpheres are independent device features and a module that only
// reads a sphere must not require the other one. Both are emitted together with
// OpExtension "SPV_NV_linear_swept_spheres" by SPIR-V CodeGen from the
// instruction itself (the OpRayQuery*Sphere*NV / OpRayQuery*LSS*NV cases in
// CapabilityVisitor), not by [[vk::ext_capability]] / [[vk::ext_extension]] on
// the declarations below: those attributes write the capability and the
// extension string unconditionally, so -fspv-extension could neither select nor
// refuse them. The extension is opt-in: without
// -fspv-extension=SPV_NV_linear_swept_spheres every call is a compile error
// instead of a module that declares an extension the host never asked for.
//
// Notes and limitations (see docs/SPIR-V.rst):
// - The accessors are SPIR-V only. DXR has no sphere geometry, so these
//   instructions have no DXIL opcode, and the accessors are free functions in
//   this header rather than members of the RayQuery object: the RayQuery method
//   table is shared by the DXIL and the SPIR-V backends, and a method would need
//   a DXIL lowering that cannot exist. On the DXIL path the `vk::` attributes on
//   the declarations below are ignored (with -Wignored-attributes warnings) and
//   the accessors stay external functions with no definition.
// - Use IsSphereHit / IsLSSHit to branch, not GetCandidateType(): DXR has no
//   sphere intersection type, so RayQuery::GetCandidateType() and
//   CommittedGetCandidateType() keep returning the triangle/AABB answer (the
//   reported type of sphere and linear-swept-sphere geometry is
//   implementation-defined), while the predicate is the extension's own answer.
// - The parameters are only defined for geometry that was built from spheres
//   (resp. linear swept spheres). For ordinary triangle geometry the values are
//   undefined and the predicate is false; the compiler cannot detect that, so it
//   is the shader author's responsibility.
// - OpRayQueryGetIntersectionLSSPositionsNV (5429, a 2-element array of float3)
//   and OpRayQueryGetIntersectionLSSRadiiNV (5430, a 2-element array of float)
//   are not exposed yet: an accessor that returns an array has to be a function
//   template to be usable with any RayQuery<flags>, and this front end rejects
//   array return types in a function template (Sema::CheckFunctionReturnType
//   does not carry the HLSL array-return exception that the declarator path
//   has), so declaring them is a compile error today.
// - The host must enable the spheres / linearSweptSpheres feature bits and build
//   the acceleration structure with the corresponding geometry types. The
//   compiler cannot check either.
// - Everything else about the query (TraceRayInline, Proceed, the committed
//   status) comes from SPV_KHR_ray_query and is unchanged; this header adds the
//   accessors and nothing else.

#ifndef _HLSL_VK_NV_LINEAR_SWEPT_SPHERES_H_
#define _HLSL_VK_NV_LINEAR_SWEPT_SPHERES_H_

namespace vk {
namespace nv {

// Intersection selectors for the accessors below. The values are the ones
// SPIR-V defines for the operand (RayQueryCandidateIntersectionKHR /
// RayQueryCommittedIntersectionKHR); they match the constants SPIR-V CodeGen
// uses for the equivalent RayQuery methods. The names are spelled out rather
// than shared with <vk/nv/cluster_as.h> so that a shader can include both
// headers (same namespace, so identical names would be a redefinition).
static const uint SphereIntersectionCandidate = 0;
static const uint SphereIntersectionCommitted = 1;

// Reads the position of a sphere intersection. Lowers to
// OpRayQueryGetIntersectionSpherePositionNV (IdResultType, IdResult, IdRef,
// IdRef): the ray query object followed by the intersection selector, and
// produces a 3-component float vector.
template <uint flags>
[[vk::ext_instruction(/* OpRayQueryGetIntersectionSpherePositionNV */ 5427)]] float3
RayQueryGetIntersectionSpherePosition(
    [[vk::ext_reference]] RayQuery<flags> query, uint intersection);

// Reads the radius of a sphere intersection. Lowers to
// OpRayQueryGetIntersectionSphereRadiusNV, same operands as the position
// accessor, float result.
template <uint flags>
[[vk::ext_instruction(/* OpRayQueryGetIntersectionSphereRadiusNV */ 5428)]] float
RayQueryGetIntersectionSphereRadius([[vk::ext_reference]] RayQuery<flags> query,
                                    uint intersection);

// True if the intersection was generated by sphere geometry. Lowers to
// OpRayQueryIsSphereHitNV, same operands as the position accessor, bool result.
// This is the portable way to branch on the geometry kind: the candidate /
// committed type enumerations of SPV_KHR_ray_query do not describe spheres.
template <uint flags>
[[vk::ext_instruction(/* OpRayQueryIsSphereHitNV */ 5438)]] bool
RayQueryIsSphereHit([[vk::ext_reference]] RayQuery<flags> query,
                    uint intersection);

// Reads the hit value of a linear-swept-sphere intersection: the position along
// the segment where the ray hit, relative to its two endpoints. Lowers to
// OpRayQueryGetIntersectionLSSHitValueNV (IdResultType, IdResult, IdRef, IdRef),
// float result.
template <uint flags>
[[vk::ext_instruction(
    /* OpRayQueryGetIntersectionLSSHitValueNV */ 5431)]] float
RayQueryGetIntersectionLSSHitValue([[vk::ext_reference]] RayQuery<flags> query,
                                   uint intersection);

// True if the intersection was generated by linear-swept-sphere geometry.
// Lowers to OpRayQueryIsLSSHitNV, same operands, bool result.
template <uint flags>
[[vk::ext_instruction(/* OpRayQueryIsLSSHitNV */ 5439)]] bool
RayQueryIsLSSHit([[vk::ext_reference]] RayQuery<flags> query, uint intersection);

// Position of the candidate intersection, i.e. the intersection the
// Proceed() loop is asking about. Same instruction, with the intersection
// operand fixed to 0.
template <uint flags>
float3 RayQueryGetCandidateIntersectionSpherePosition(RayQuery<flags> query) {
  return RayQueryGetIntersectionSpherePosition(query,
                                               SphereIntersectionCandidate);
}

// Radius of the candidate intersection. Same instruction, selector 0.
template <uint flags>
float RayQueryGetCandidateIntersectionSphereRadius(RayQuery<flags> query) {
  return RayQueryGetIntersectionSphereRadius(query,
                                             SphereIntersectionCandidate);
}

// True if the candidate intersection was generated by sphere geometry.
template <uint flags>
bool RayQueryIsCandidateSphereHit(RayQuery<flags> query) {
  return RayQueryIsSphereHit(query, SphereIntersectionCandidate);
}

// Hit value of the candidate linear-swept-sphere intersection.
template <uint flags>
float RayQueryGetCandidateIntersectionLSSHitValue(RayQuery<flags> query) {
  return RayQueryGetIntersectionLSSHitValue(query,
                                            SphereIntersectionCandidate);
}

// True if the candidate intersection was generated by linear-swept-sphere
// geometry.
template <uint flags>
bool RayQueryIsCandidateLSSHit(RayQuery<flags> query) {
  return RayQueryIsLSSHit(query, SphereIntersectionCandidate);
}

// Position of the committed intersection, i.e. the intersection reported after
// the query has stopped traversal. Same instruction, selector 1.
template <uint flags>
float3 RayQueryGetCommittedIntersectionSpherePosition(RayQuery<flags> query) {
  return RayQueryGetIntersectionSpherePosition(query,
                                               SphereIntersectionCommitted);
}

// Radius of the committed intersection. Same instruction, selector 1.
template <uint flags>
float RayQueryGetCommittedIntersectionSphereRadius(RayQuery<flags> query) {
  return RayQueryGetIntersectionSphereRadius(query,
                                             SphereIntersectionCommitted);
}

// True if the committed intersection was generated by sphere geometry.
template <uint flags>
bool RayQueryIsCommittedSphereHit(RayQuery<flags> query) {
  return RayQueryIsSphereHit(query, SphereIntersectionCommitted);
}

// Hit value of the committed linear-swept-sphere intersection.
template <uint flags>
float RayQueryGetCommittedIntersectionLSSHitValue(RayQuery<flags> query) {
  return RayQueryGetIntersectionLSSHitValue(query,
                                            SphereIntersectionCommitted);
}

// True if the committed intersection was generated by linear-swept-sphere
// geometry.
template <uint flags>
bool RayQueryIsCommittedLSSHit(RayQuery<flags> query) {
  return RayQueryIsLSSHit(query, SphereIntersectionCommitted);
}

} // namespace nv
} // namespace vk

#endif // _HLSL_VK_NV_LINEAR_SWEPT_SPHERES_H_
