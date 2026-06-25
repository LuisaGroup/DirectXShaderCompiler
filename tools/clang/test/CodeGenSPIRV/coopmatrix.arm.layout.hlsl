// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<float> data;
static const int stride = 4;

// CHECK: OpCapability CooperativeMatrixKHR
// CHECK: OpExtension "SPV_KHR_cooperative_matrix"
// CHECK: OpCapability CooperativeMatrixLayoutsARM
// CHECK: OpExtension "SPV_ARM_cooperative_matrix_layouts"

[numthreads(64, 1, 1)] void main() {
  using FloatMatA = vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, 16, 16>;

  // Load with RowBlockedInterleavedARM layout
  // CHECK: OpCooperativeMatrixLoadKHR {{%[^ ]+}} {{%[^ ]+}} %uint_4202
  FloatMatA mat_a = FloatMatA::Load<vk::CooperativeMatrixLayoutRowBlockedInterleavedARM>(
      data, 0, stride);

  // Store with ColumnBlockedInterleavedARM layout
  // CHECK: OpCooperativeMatrixStoreKHR {{%[^ ]+}} {{%[^ ]+}} %uint_4203
  mat_a.Store<vk::CooperativeMatrixLayoutColumnBlockedInterleavedARM>(data, 64, stride);
}
