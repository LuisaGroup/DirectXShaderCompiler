// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -HV 2021 %s -spirv | FileCheck %s

// L5 off-path regression for SPV_ARM_cooperative_matrix_layouts: the classic
// RowMajorKHR (0) / ColumnMajorKHR (1) path must stay exactly what it was.
//
// A module that only uses the two layouts SPV_KHR_cooperative_matrix defines
// declares neither the CooperativeMatrixLayoutsARM capability nor the
// SPV_ARM_cooperative_matrix_layouts extension, never materialises an Arm
// MemoryLayout enumerant, and passes the classic enumerants through unchanged.
// This is the guard against a capability-inference change that starts declaring
// the Arm extension everywhere the cooperative matrix headers are included.

#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<float> data;

// The CHECK-NOT regions are anchored: the first runs over every remaining
// capability line, the second over every remaining extension line. The
// %int_4202 / %int_4203 constants themselves are not a usable signal - the
// enumerants are declared by <vk/spirv.h> either way - so the absence of the
// layouts is asserted through the capability, the extension and the MemoryLayout
// operands below.
// CHECK: OpCapability VulkanMemoryModel
// CHECK-NOT: OpCapability CooperativeMatrixLayoutsARM
// CHECK: OpExtension "SPV_KHR_cooperative_matrix"
// CHECK-NOT: OpExtension "SPV_ARM_cooperative_matrix_layouts"
// CHECK: OpMemoryModel Logical Vulkan

[numthreads(64, 1, 1)]
void main() {
  using FloatMatA =
      vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, 16, 16>;

  // The classic path keeps its operands: ColumnMajorKHR (1) for the load,
  // RowMajorKHR (0) for the store, and a stride that still comes from a
  // run-time argument.
  // CHECK: %[[LD:[0-9]+]] = OpCooperativeMatrixLoadKHR %spirvIntrinsicType %{{[0-9]+}} %int_1 %{{[0-9]+}} None
  FloatMatA m =
      FloatMatA::Load<vk::CooperativeMatrixLayoutColumnMajorKHR>(data, 0, 256);

  // CHECK: OpCooperativeMatrixStoreKHR %{{[0-9]+}} %{{[0-9]+}} %int_0 %{{[0-9]+}} None
  m.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(data, 64, 16);
}
