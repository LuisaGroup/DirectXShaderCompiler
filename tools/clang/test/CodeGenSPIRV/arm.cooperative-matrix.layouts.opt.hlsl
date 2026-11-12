// RUN: %dxc -T cs_6_0 -E main -fspv-target-env=vulkan1.3 -HV 2021 %s -spirv | FileCheck %s

// L6 optimizer survival for SPV_ARM_cooperative_matrix_layouts: no -fcgl, so the
// module goes through legalization, spirv-opt and capability trimming before it
// is validated.
//
// Two things can only go wrong here: the optimizer drops or rewrites the
// instructions, or capability trimming removes CooperativeMatrixLayoutsARM (which
// would either warn "SPIR-V capability trimming: ..." or produce a module that
// spirv-val rejects).
//
// The workgroup form is only exercised here, not in the -fcgl test, because the
// Scope operand of the workgroup load/store is a run-time argument before
// legalization and a constant after it; spirv-val requires a constant Scope, so a
// -fcgl compile of any workgroup-memory cooperative matrix load/store - with the
// classic layouts as well - is rejected for that reason alone.
//
// No -fspv-extension= on the RUN line: the extension is enabled by default and the
// capability is inferred from the MemoryLayout operands.

#include <vk/arm/cooperative_matrix_layouts.h>

RWStructuredBuffer<float> data;
groupshared float shared_data[1024];

// The capability and the extension are still there after trimming.
// CHECK: OpCapability CooperativeMatrixLayoutsARM
// CHECK: OpExtension "SPV_ARM_cooperative_matrix_layouts"

[numthreads(64, 1, 1)]
void main() {
  using FloatMatA =
      vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, 16, 16>;

  // RowBlockedInterleavedARM with a Stride of 4 reading from a structured buffer.
  // CHECK: %[[ROWLOAD:[0-9]+]] = OpCooperativeMatrixLoadKHR %spirvIntrinsicType %{{[0-9]+}} %int_4202 %uint_4 None
  FloatMatA m = FloatMatA::LoadBlockedInterleaved<
      vk::CooperativeMatrixLayoutRowBlockedInterleavedARM, 4>(data, 0);

  // ColumnBlockedInterleavedARM with a Stride of 2 writing to workgroup memory.
  // The make-available/non-private memory access operands and the workgroup scope
  // are what LoadBlockedInterleaved/StoreBlockedInterleaved add for workgroup
  // memory.
  // CHECK: OpCooperativeMatrixStoreKHR %{{[0-9]+}} %{{[0-9]+}} %int_4203 %uint_2 MakePointerAvailable|NonPrivatePointer %int_2
  m.StoreBlockedInterleaved<
      vk::CooperativeMatrixLayoutColumnBlockedInterleavedARM, 2>(
      vk::GetGroupSharedAddress(shared_data[0]));

  // CHECK: %[[COLLOAD:[0-9]+]] = OpCooperativeMatrixLoadKHR %spirvIntrinsicType %{{[0-9]+}} %int_4203 %uint_2 MakePointerVisible|NonPrivatePointer %int_2
  FloatMatA n = FloatMatA::LoadBlockedInterleaved<
      vk::CooperativeMatrixLayoutColumnBlockedInterleavedARM, 2>(
      vk::GetGroupSharedAddress(shared_data[0]));

  // RowBlockedInterleavedARM with a Stride of 1 writing back to the buffer.
  // CHECK: OpCooperativeMatrixStoreKHR %{{[0-9]+}} %{{[0-9]+}} %int_4202 %uint_1 None
  n.StoreBlockedInterleaved<
      vk::CooperativeMatrixLayoutRowBlockedInterleavedARM, 1>(data, 16);
}
