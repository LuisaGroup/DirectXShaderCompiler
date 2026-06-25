// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/nv/cooperative_matrix2.h>

RWStructuredBuffer<float> data;
int stride;

// CHECK: OpCapability CooperativeMatrixConversionsNV
// CHECK: OpExtension "SPV_NV_cooperative_matrix2"

[numthreads(64, 1, 1)] void main() {
  using FloatMatAcc =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, 16, 8>;
  using FloatMatB =
      vk::khr::CooperativeMatrixB<float, vk::ScopeSubgroup, 8, 16>;

  // Load an Accumulator matrix
  // CHECK: OpCooperativeMatrixLoadKHR
  FloatMatAcc acc_mat = FloatMatAcc::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(
      data, 0, stride);

  // Transpose: M×N Acc -> N×M MatrixB
  // CHECK: OpCooperativeMatrixTransposeNV
  FloatMatB mat_b = vk::nv::cooperativeMatrixTranspose<
      float, vk::ScopeSubgroup, 16, 8>(acc_mat);
}
