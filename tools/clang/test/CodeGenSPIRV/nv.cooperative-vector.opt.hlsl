// RUN: %dxc -T cs_6_0 -E main -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_vector %s -spirv | FileCheck %s

// L6 optimizer-survival gate for VK_NV_cooperative_vector: the same shader as the
// matrix-vector case in nv.cooperative-vector.hlsl, compiled *without* -fcgl, so
// SpirvEmitter runs HLSL legalization, the spirv-opt pass list and the
// capability-trimming pass before validation.
//
// Three things can go wrong only here:
//
// * Capability trimming (SpirvEmitter::spirvToolsTrimCapabilities) could drop
//   CooperativeVectorNV, leaving a module that declares OpTypeVectorIdEXT
//   without its capability. It does not: the vendored trimming pass only touches
//   the capabilities in its own table, and CooperativeVectorNV is not in it.
//   Validation would fail loudly if that changed ("Opcode TypeVectorIdEXT
//   requires one of these capabilities: CooperativeVectorNV LongVectorEXT"),
//   which is the negative control for this gate - nothing here is compiled with
//   -Vd.
// * The optimizer could rewrite the opaque load/store pair or the instruction
//   itself. What survives is asserted below, and the ids are chained: the value
//   loaded from g_vector is the input of the matrix multiply, and the result of
//   the matrix multiply is what is stored back to g_vector.
// * Inlining and DCE could change the number of copies of the instruction. Here
//   that also *removes* the module-scope variables <vk/spirv.h> creates for its
//   enumerators, so the optimized module is much smaller than the -fcgl one and
//   the capability and the extension have to be re-derived from the instructions
//   alone rather than from a variable that happened to survive.
//
// What this does not show: that a driver's own spirv-opt run keeps the
// instructions, or that the device implements them.
#include <vk/nv/cooperative_vector.h>

groupshared uint g_matrix[64];
groupshared uint g_vector[16];
RWStructuredBuffer<uint> g_out : register(u0);

[numthreads(1, 1, 1)] void main(uint3 tid : SV_DispatchThreadID) {
  // The capability and the extension are still there, exactly once.
  // CHECK: OpCapability Shader
  // CHECK: OpCapability CooperativeVectorNV
  // CHECK-NOT: OpCapability CooperativeVectorNV
  // CHECK: OpExtension "SPV_NV_cooperative_vector"
  // CHECK-NOT: OpExtension "SPV_NV_cooperative_vector"
  // CHECK: OpMemoryModel Logical GLSL450
  vk::nv::CooperativeVector<uint, 4> v = vk::nv::Load<uint, 4>(g_vector, 0);
  vk::nv::CooperativeVector<uint, 4> r = vk::nv::MatrixMul<uint, 4, 4>(
      v, vk::CooperativeVectorComponentTypeUnsignedInt32NV, g_matrix, 0,
      vk::CooperativeVectorComponentTypeUnsignedInt32NV, 4, 4,
      vk::CooperativeVectorMatrixLayoutRowMajorNV, false, 16);
  vk::nv::Store<uint, 4>(g_vector, 4, r);
  // The type, then the three instructions with their operands still in place and
  // chained through their result ids.
  // CHECK: %[[CV:[A-Za-z0-9_]+]] = OpTypeVectorIdEXT %uint %uint_4
  // CHECK: %[[VAL:[A-Za-z0-9_]+]] = OpCooperativeVectorLoadNV %[[CV]] %g_vector %uint_0
  // CHECK: %[[RES:[A-Za-z0-9_]+]] = OpCooperativeVectorMatrixMulNV %[[CV]] %[[VAL]] %int_9 %g_matrix %uint_0 %int_9 %uint_4 %uint_4 %int_0 %false %uint_16
  // CHECK: OpCooperativeVectorStoreNV %g_vector %uint_4 %[[RES]]
  g_out[0] = tid.x;
}
