// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -HV 2021 -fspv-extension=SPV_ARM_cooperative_matrix_layouts %s -spirv | FileCheck %s

// SPV_ARM_cooperative_matrix_layouts: the two blocked-interleaved Arm memory
// layouts and the CooperativeMatrixLayoutsARM capability (4201) they require.
//
// RowBlockedInterleavedARM    4202
// ColumnBlockedInterleavedARM 4203
//
// Both layouts need a constant Stride operand, so they are reached through
// LoadBlockedInterleaved/StoreBlockedInterleaved, which take the stride as a
// template argument (see <vk/arm/cooperative_matrix_layouts.h>).

#include <vk/arm/cooperative_matrix_layouts.h>

RWStructuredBuffer<float> data;

// The capability and the extension are declared once each, inferred from the
// MemoryLayout operand of the load/store instructions - not requested by
// -fspv-extension=, which is only listed on the RUN line to keep the allow-list
// explicit. The CHECK-NOT runs are anchored between the surrounding capabilities
// and extensions so that a duplicated OpCapability/OpExtension line fails.
// CHECK: OpCapability VulkanMemoryModel
// CHECK: OpCapability CooperativeMatrixLayoutsARM
// CHECK-NOT: OpCapability CooperativeMatrixLayoutsARM
// CHECK: OpExtension "SPV_KHR_cooperative_matrix"
// CHECK: OpExtension "SPV_ARM_cooperative_matrix_layouts"
// CHECK-NOT: OpExtension "SPV_ARM_cooperative_matrix_layouts"
// CHECK: OpMemoryModel Logical Vulkan

// The MemoryLayout operand is the enumerant itself - a constant instruction, as
// the extension requires - and the Stride operand is one too. The literals are
// asserted because the assembler prints the number, not the enumerant name.
// CHECK: %[[ROW_LAYOUT:int_4202]] = OpConstant %int 4202
// CHECK: %[[COL_LAYOUT:int_4203]] = OpConstant %int 4203
// CHECK: %[[STRIDE_1:uint_1]] = OpConstant %uint 1
// CHECK: %[[STRIDE_2:uint_2]] = OpConstant %uint 2

[numthreads(64, 1, 1)]
void main() {
  using FloatMatA =
      vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, 16, 16>;

  // L2: RowBlockedInterleavedARM with a Stride of 1. The operand order is
  // OpCooperativeMatrixLoadKHR (Pointer, MemoryLayout, Stride, MemoryAccess).
  // CHECK: %{{[0-9]+}} = OpCooperativeMatrixLoadKHR %spirvIntrinsicType %{{[0-9]+}} %[[ROW_LAYOUT]] %[[STRIDE_1]] None
  FloatMatA row = FloatMatA::LoadBlockedInterleaved<
      vk::CooperativeMatrixLayoutRowBlockedInterleavedARM, 1>(data, 0);

  // OpCooperativeMatrixStoreKHR (Pointer, Object, MemoryLayout, Stride,
  // MemoryAccess) - the Object operand in front of MemoryLayout is why the
  // layout is operand 2 here and operand 1 in the load.
  // CHECK: OpCooperativeMatrixStoreKHR %{{[0-9]+}} %{{[0-9]+}} %[[ROW_LAYOUT]] %[[STRIDE_1]] None
  row.StoreBlockedInterleaved<
      vk::CooperativeMatrixLayoutRowBlockedInterleavedARM, 1>(data, 64);

  // L2: ColumnBlockedInterleavedARM with a Stride of 2. The pair of layouts
  // shows that the operand is passed through and not hard-coded.
  // CHECK: %{{[0-9]+}} = OpCooperativeMatrixLoadKHR %spirvIntrinsicType %{{[0-9]+}} %[[COL_LAYOUT]] %[[STRIDE_2]] None
  FloatMatA col = FloatMatA::LoadBlockedInterleaved<
      vk::CooperativeMatrixLayoutColumnBlockedInterleavedARM, 2>(data, 128);

  // CHECK: OpCooperativeMatrixStoreKHR %{{[0-9]+}} %{{[0-9]+}} %[[COL_LAYOUT]] %[[STRIDE_2]] None
  col.StoreBlockedInterleaved<
      vk::CooperativeMatrixLayoutColumnBlockedInterleavedARM, 2>(data, 192);
}
