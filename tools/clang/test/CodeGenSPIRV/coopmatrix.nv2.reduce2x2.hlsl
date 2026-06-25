// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/nv/cooperative_matrix2.h>

RWStructuredBuffer<float> data;
static const int stride = 64;

// CHECK: OpCapability CooperativeMatrixReductionsNV
// CHECK: OpExtension "SPV_NV_cooperative_matrix2"

[numthreads(64, 1, 1)] void main() {
  using FloatMatAcc =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, 16, 8>;

  // Load an Accumulator matrix
  // CHECK: OpCooperativeMatrixLoadKHR
  FloatMatAcc acc_mat = FloatMatAcc::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(
      data, 0, stride);

  // 2x2 reduction: reduce 2x2 neighborhoods using FAdd (129)
  // CHECK: OpCooperativeMatrixReduceNV {{%[^ ]+}} {{%[^ ]+}} %uint_4 %uint_129
  vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, 8, 4> mat_result =
      vk::nv::cooperativeMatrixReduce2x2<
          float, vk::ScopeSubgroup, 16, 8,
          vk::CooperativeMatrixUseMatrixAccumulatorKHR>(acc_mat, 129);
}
