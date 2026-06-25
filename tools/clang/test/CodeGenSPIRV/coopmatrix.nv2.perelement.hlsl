// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/nv/cooperative_matrix2.h>

RWStructuredBuffer<float> data;
int stride;

// CHECK: OpCapability CooperativeMatrixPerElementOperationsNV
// CHECK: OpExtension "SPV_NV_cooperative_matrix2"

[numthreads(64, 1, 1)] void main() {
  using FloatMatAcc =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, 16, 8>;

  // Load an Accumulator matrix
  // CHECK: OpCooperativeMatrixLoadKHR
  FloatMatAcc acc_mat = FloatMatAcc::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(
      data, 0, stride);

  // Apply a per-element operation using a function ID
  // CHECK: OpCooperativeMatrixPerElementOpNV
  FloatMatAcc result = vk::nv::cooperativeMatrixPerElementOp<
      float, vk::ScopeSubgroup, 16, 8,
      vk::CooperativeMatrixUseMatrixAccumulatorKHR>(acc_mat, 42);
}
