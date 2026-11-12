// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Cluster acceleration structures: VK_NV_cluster_acceleration_structure /
// SPV_NV_cluster_acceleration_structure.
//
// A cluster acceleration structure groups the triangles of a mesh into clusters
// and gives each cluster an identity that the shader can read back from an
// intersection. The identity is what a renderer uses to pick the material, the
// level of detail or a shading bin for the triangle that was hit, instead of
// deriving that decision from the primitive index. Building clusters is a
// host-side operation (vkGetClusterAccelerationStructureBuildSizesNV and
// vkCmdBuildClusterAccelerationStructureIndirectNV); the only shader-visible
// part of the extension is the cluster ID of an intersection.
//
// The HLSL entry points below lower to OpRayQueryGetIntersectionClusterIdNV
// (5345), which reads the cluster ID of one intersection of a ray query:
//
//   %cluster = OpRayQueryGetIntersectionClusterIdNV %uint %query %uint_1
//
// The operands are, in order, the ray query object and the intersection - the
// same shape as the already-supported
// OpRayQueryGetIntersectionInstanceIdKHR family. The intersection operand is 0
// for the candidate intersection and 1 for the committed one, and it must be a
// constant: SPIRV-Tools rejects a module whose intersection operand is not a
// constant 32-bit integer, so the two convenience wrappers exist to keep the
// value out of shader code that could compute it. The result is a 32-bit
// unsigned integer, like the other RayQuery accessors; the validator only asks
// for a 32-bit integer scalar.
//
// Using the accessor adds the RayTracingClusterAccelerationStructureNV (5437)
// capability and OpExtension "SPV_NV_cluster_acceleration_structure" to the
// module. Both are emitted by SPIR-V CodeGen from the instruction itself (the
// OpRayQueryGetIntersectionClusterIdNV case in CapabilityVisitor), not by
// [[vk::ext_capability]] / [[vk::ext_extension]] on the declaration below: those
// attributes write the capability and the extension string unconditionally, so
// -fspv-extension could neither select nor refuse them. The extension is
// opt-in, like SPV_EXT_split_barrier: without
// -fspv-extension=SPV_NV_cluster_acceleration_structure every call is a compile
// error instead of a module that declares an extension the host never asked for.
//
// Notes and limitations (see docs/SPIR-V.rst):
// - The accessor is SPIR-V only. DXR has no cluster acceleration structures, so
//   this instruction has no DXIL opcode, and the accessor is a free function in
//   this header rather than a member of the RayQuery object: the RayQuery method
//   table is shared by the DXIL and the SPIR-V backends, and a method would need
//   a DXIL lowering that cannot exist. On the DXIL path the `vk::` attributes on
//   the declaration below are ignored (with -Wignored-attributes warnings) and
//   the accessor stays an external function with no definition, so calling it
//   from a non-library profile is an error and a library build keeps an
//   unresolved call.
// - A cluster ID is only defined for geometry built from a cluster acceleration
//   structure. For an ordinary triangle geometry the value is undefined; the
//   compiler cannot detect that, so it is the shader author's responsibility.
// - The host must enable the clusterAccelerationStructure feature and build the
//   acceleration structure with clusters. The compiler cannot check either.
// - Everything else about the query (TraceRayInline, Proceed, the committed
//   status) comes from SPV_KHR_ray_query and is unchanged; this header adds one
//   accessor and nothing else.

#ifndef _HLSL_VK_NV_CLUSTER_AS_H_
#define _HLSL_VK_NV_CLUSTER_AS_H_

namespace vk {
namespace nv {

// Intersection selectors for OpRayQueryGetIntersectionClusterIdNV. The values
// are the ones Vulkan defines for the operand; they match the constants
// SPIR-V CodeGen uses for the equivalent RayQuery methods.
static const uint IntersectionCandidate = 0;
static const uint IntersectionCommitted = 1;

// Reads the cluster ID of one intersection of a ray query. Lowers to
// OpRayQueryGetIntersectionClusterIdNV (IdResultType, IdResult, IdRef, IdRef):
// the ray query object followed by the intersection selector, which must be a
// constant (use vk::nv::IntersectionCandidate / vk::nv::IntersectionCommitted or
// one of the two wrappers below).
template <uint flags>
[[vk::ext_instruction(/* OpRayQueryGetIntersectionClusterIdNV */ 5345)]] uint
RayQueryGetIntersectionClusterId([[vk::ext_reference]] RayQuery<flags> query,
                                 uint intersection);

// Cluster ID of the candidate intersection, i.e. the intersection
// CandidateType()/CandidateInstanceIndex() describe. Same instruction, with the
// intersection operand fixed to 0.
template <uint flags>
uint RayQueryGetCandidateIntersectionClusterId(RayQuery<flags> query) {
  return RayQueryGetIntersectionClusterId(query, IntersectionCandidate);
}

// Cluster ID of the committed intersection, i.e. the intersection
// CommittedStatus()/CommittedInstanceIndex() describe. Same instruction, with
// the intersection operand fixed to 1.
template <uint flags>
uint RayQueryGetCommittedIntersectionClusterId(RayQuery<flags> query) {
  return RayQueryGetIntersectionClusterId(query, IntersectionCommitted);
}

} // namespace nv
} // namespace vk

#endif // _HLSL_VK_NV_CLUSTER_AS_H_
