// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_vector %s -spirv | FileCheck %s

// L1/L2 gates for the two *training* instructions of
// VK_NV_cooperative_vector, i.e. OpCooperativeVectorOuterProductAccumulateNV
// (5290) and OpCooperativeVectorReduceSumAccumulateNV (5291).
//
// VK_NV_cooperative_vector splits into two device features, and SPV_NV_
// cooperative_vector splits into two capabilities with them:
// CooperativeVectorNV (5394) for the inferencing half and
// CooperativeVectorTrainingNV (5435) for these two instructions. The capability
// is therefore selected per instruction, not once for the extension
// (CapabilityVisitor::visitInstruction): a device that implements only the
// inferencing half must be able to run a module that this header produced
// without a training instruction, and a module that uses one has to declare the
// capability. nv.cooperative-vector.hlsl asserts the other direction - that its
// module does *not* declare CooperativeVectorTrainingNV - which is the half of
// this gate that an "opcode present" test would miss.
//
// A training module declares both capabilities: the instructions take
// cooperative vector operands, and the type itself requires CooperativeVectorNV
// which cannot be renamed or dropped.
//
// Neither instruction has a result: the accumulator array in memory is the
// destination. That is why the L2 assertions below have no result type and no
// result id, and why the two of them are the only entry points in this header
// that return void.
//
// What these gates cannot prove: numeric semantics, the accumulation order, and
// whether a device implements the training half at all. Nothing in CI executes
// the extension; SPIRV-Tools validation is the only signal (and it is part of
// these compiles, since none of them passes -Vd).
#include <vk/nv/cooperative_vector.h>

// The accumulator, and the two operand vectors, have to live in Workgroup
// memory: the pointer operand of both instructions must address an array in the
// Workgroup, StorageBuffer or PhysicalStorageBuffer storage class
// (external/SPIRV-Tools, ValidateCooperativeVectorPointer).
groupshared uint g_matrix[64];
groupshared uint g_vector[16];
groupshared uint g_accumulator[64];
RWStructuredBuffer<uint> g_out : register(u0);

[numthreads(1, 1, 1)] void main(uint3 tid : SV_DispatchThreadID) {
  // L1: both capabilities, each exactly once, and the extension once. The
  // CHECK-NOTs bound the region they apply to.
  // CHECK: OpCapability Shader
  // CHECK: OpCapability CooperativeVectorNV
  // CHECK: OpCapability CooperativeVectorTrainingNV
  // CHECK-NOT: OpCapability CooperativeVectorTrainingNV
  // CHECK: OpExtension "SPV_NV_cooperative_vector"
  // CHECK-NOT: OpExtension "SPV_NV_cooperative_vector"
  // CHECK: OpMemoryModel Logical GLSL450
  vk::nv::CooperativeVector<uint, 4> a = vk::nv::Load<uint, 4>(g_vector, 0);
  vk::nv::CooperativeVector<uint, 8> b = vk::nv::Load<uint, 8>(g_vector, 8);

  // Two distinct cooperative vector types, one per component count, each with
  // the count as the id of an OpConstant.
  // CHECK: [[CV4:%[A-Za-z0-9_]+]] = OpTypeVectorIdEXT %uint %uint_4
  // CHECK: [[CV8:%[A-Za-z0-9_]+]] = OpTypeVectorIdEXT %uint %uint_8

  // L2, the outer product: (Pointer, Offset, A, B, MemoryLayout,
  // MatrixInterpretation, [MatrixStride]) - no result type, no result id, and the
  // layout before the interpretation (the reverse of the two matrix-vector
  // instructions, whose layout comes last).
  // %int_0 is CooperativeVectorMatrixLayoutRowMajorNV, %int_3 is
  // TrainingOptimalNV and %int_9 is CooperativeVectorComponentTypeUnsignedInt32NV.
  // CHECK: OpCooperativeVectorOuterProductAccumulateNV %g_accumulator %uint_0 %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}} %int_0 %int_9 %uint_32
  vk::nv::OuterProductAccumulate<uint, 4, 8>(
      g_accumulator, 0, a, b, vk::CooperativeVectorMatrixLayoutRowMajorNV,
      vk::CooperativeVectorComponentTypeUnsignedInt32NV, 32);

  // The TrainingOptimalNV layout leaves the stride to the device, so the second
  // overload omits the operand: the line ends after MatrixInterpretation.
  // CHECK: OpCooperativeVectorOuterProductAccumulateNV %g_accumulator %uint_8 %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}} %int_3 %int_9{{$}}
  vk::nv::OuterProductAccumulate<uint, 4, 8>(
      g_accumulator, 8, a, b, vk::CooperativeVectorMatrixLayoutTrainingOptimalNV,
      vk::CooperativeVectorComponentTypeUnsignedInt32NV);

  // L2, the reduce-sum: (Pointer, Offset, V), the shortest instruction in the
  // extension.
  // CHECK: OpCooperativeVectorReduceSumAccumulateNV %g_accumulator %uint_16 %{{[A-Za-z0-9_]+}}
  vk::nv::ReduceSumAccumulate<uint, 4>(g_accumulator, 16, a);
  g_out[0] = tid.x;
}
