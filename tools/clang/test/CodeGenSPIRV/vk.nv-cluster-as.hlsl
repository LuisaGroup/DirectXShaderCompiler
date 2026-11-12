// RUN: %dxc -T cs_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_NV_cluster_acceleration_structure %s | FileCheck %s

// SPV_NV_cluster_acceleration_structure: the ray query cluster-ID accessor, its
// capability and its extension (G26/L0, G26/L1, G26/L2). L3 is implicit: dxc
// validates every module it emits unless -Vd is given, so this file failing to
// compile is the validity gate. The accessors are header-only (they have no DXIL
// equivalent, so they are not RayQuery methods); see <vk/nv/cluster_as.h>.
//
// The instruction is OpRayQueryGetIntersectionClusterIdNV (5345), operands
// (IdResultType, IdResult, IdRef RayQuery, IdRef Intersection): the same shape as
// OpRayQueryGetIntersectionInstanceIdKHR, with a constant 32-bit integer in place
// of the candidate/committed selector. SPIRV-Tools requires that operand to be a
// constant ("expected Intersection ID to be a constant 32-bit int scalar"), which
// is why the header offers the two wrappers and exports the two selector values
// instead of taking a bool. The result is a 32-bit unsigned integer.
//
// Anti-false-green note: the cluster ID is only defined for geometry built from a
// cluster acceleration structure. This module is a pure encoding test - no driver
// runs it, and for ordinary triangle geometry the value the instruction returns
// is undefined. Nothing here proves the value is meaningful.

// Included twice on purpose: the header has to be guarded, and including it
// must not add anything to the module by itself (see the off-path test).
#include <vk/nv/cluster_as.h>
#include <vk/nv/cluster_as.h>

RaytracingAccelerationStructure Scene : register(t0);
RWStructuredBuffer<uint> Out : register(u0);

[numThreads(1, 1, 1)]
void main() {
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
  RayDesc ray = {float3(0, 0, 0), 0.0f, float3(0, 0, 1), 100.0f};
  q.TraceRayInline(Scene, RAY_FLAG_NONE, 0xFF, ray);

  while (q.Proceed()) {
    // Candidate intersection: only meaningful inside the Proceed() loop.
    Out[1] = vk::nv::RayQueryGetCandidateIntersectionClusterId(q);
  }

  // Committed intersection: meaningful once the traversal has stopped.
  Out[0] = vk::nv::RayQueryGetCommittedIntersectionClusterId(q);

  // Raw form: the intersection selector is the caller's constant. Both selector
  // spellings must reach the operand as %uint_1 / %uint_0.
  Out[2] =
      vk::nv::RayQueryGetIntersectionClusterId(q, vk::nv::IntersectionCommitted);
  Out[3] =
      vk::nv::RayQueryGetIntersectionClusterId(q, vk::nv::IntersectionCandidate);
}

// L1: the capability and the extension, once each, and the RayQueryKHR capability
// the ray query itself needs. They are emitted from the instruction by
// CapabilityVisitor (not by [[vk::ext_capability]]/[[vk::ext_extension]] on the
// header declaration), so they appear only when the accessor is used and only
// when -fspv-extension=SPV_NV_cluster_acceleration_structure permits it.
// CHECK: OpCapability RayQueryKHR
// CHECK: OpCapability RayTracingClusterAccelerationStructureNV
// The capability block is contiguous, so any duplicate would be right here.
// CHECK-NOT: OpCapability RayTracingClusterAccelerationStructureNV
// CHECK: OpExtension "SPV_KHR_ray_query"
// CHECK: OpExtension "SPV_NV_cluster_acceleration_structure"
// CHECK-NOT: OpExtension "SPV_NV_cluster_acceleration_structure"
// CHECK: OpMemoryModel Logical GLSL450

// L2: the ray query object and the 32-bit unsigned result type, captured once.
// CHECK-DAG: [[UINT:%[0-9A-Za-z_]+]] = OpTypeInt 32 0
// CHECK-DAG: [[RQ:%[0-9A-Za-z_]+]] = OpVariable %_ptr_Function_rayQueryKHR Function

// L0/L2: the two wrappers reach the same instruction from main.
// CHECK: OpFunctionCall %uint %vk__nv__RayQueryGetCandidateIntersectionClusterId [[RQ]]
// CHECK: OpFunctionCall %uint %vk__nv__RayQueryGetCommittedIntersectionClusterId [[RQ]]

// L2: the committed raw call, then the candidate raw call. The intersection
// operand is the only thing that differs, so a lowering that swapped the selector
// (or folded it to a constant) cannot pass both lines.
// CHECK: [[COMMITTED:%[0-9A-Za-z_]+]] = OpRayQueryGetIntersectionClusterIdNV [[UINT]] [[RQ]] %uint_1
// CHECK: [[CANDIDATE:%[0-9A-Za-z_]+]] = OpRayQueryGetIntersectionClusterIdNV [[UINT]] [[RQ]] %uint_0

// L0/L2: the wrapper bodies. -fcgl keeps the wrappers as real functions and the
// selector is the constant each wrapper baked in; the two bodies are emitted in
// call order (candidate first). The operand is the wrapper's own ray query
// parameter, i.e. the object is passed as a pointer, not copied.
// CHECK: %vk__nv__RayQueryGetCandidateIntersectionClusterId = OpFunction
// CHECK: [[PC:%[0-9A-Za-z_]+]] = OpFunctionParameter %_ptr_Function_rayQueryKHR
// CHECK: OpRayQueryGetIntersectionClusterIdNV [[UINT]] [[PC]] %uint_0
// CHECK: %vk__nv__RayQueryGetCommittedIntersectionClusterId = OpFunction
// CHECK: [[PM:%[0-9A-Za-z_]+]] = OpFunctionParameter %_ptr_Function_rayQueryKHR
// CHECK: OpRayQueryGetIntersectionClusterIdNV [[UINT]] [[PM]] %uint_1
