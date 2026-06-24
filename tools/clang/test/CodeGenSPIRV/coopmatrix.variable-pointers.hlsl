// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

// Test that VariablePointersStorageBuffer capability is correctly declared
// when cooperative matrix types are present and buffer references are passed
// to cooperative matrix intrinsics (creating pointer-to-pointer patterns).

// CHECK: OpCapability CooperativeMatrixKHR
// CHECK: OpCapability VariablePointersStorageBuffer
// CHECK: OpExtension "SPV_KHR_cooperative_matrix"

#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<int> data;

[numthreads(64, 1, 1)]
void main() {
  using IntMatA = vk::khr::CooperativeMatrixA<int, vk::ScopeSubgroup, 16, 4>;

  // Load from buffer - creates pointer-to-pointer pattern
  // CHECK: OpCooperativeMatrixLoadKHR
  IntMatA a = IntMatA::Load<vk::CooperativeMatrixLayoutColumnMajorKHR>(data, 0, 8);
}
