// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/nv/cooperative_matrix2.h>

RWStructuredBuffer<float> data;
int stride;

// CHECK: OpCapability CooperativeMatrixConversionsNV
// CHECK: OpExtension "SPV_NV_cooperative_matrix2"

[numthreads(64, 1, 1)] void main() {
  using FloatMatA = vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, 16, 4>;
  using FloatMatAcc =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, 16, 4>;

  // Load an Accumulator matrix
  // CHECK: OpCooperativeMatrixLoadKHR
  FloatMatAcc acc_mat = FloatMatAcc::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(
      data, 0, stride);

  // Convert Accumulator -> MatrixA (use-type conversion)
  // CHECK: OpCooperativeMatrixConvertNV
  FloatMatA mat_a = vk::nv::cooperativeMatrixConvertUse<
      float, vk::ScopeSubgroup, 16, 4,
      vk::CooperativeMatrixUseMatrixAKHR,
      vk::CooperativeMatrixUseMatrixAccumulatorKHR>(acc_mat);
}
