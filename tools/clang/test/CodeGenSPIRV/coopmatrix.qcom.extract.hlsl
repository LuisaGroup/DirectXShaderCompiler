// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/qcom/cooperative_matrix_conversion.h>

RWStructuredBuffer<float> data;
static const int stride = 64;
// Result array length must equal number of columns (8) for the cooperative matrix
groupshared float resultArray[8];

// CHECK: OpCapability CooperativeMatrixConversionQCOM
// CHECK: OpExtension "SPV_QCOM_cooperative_matrix_conversion"

[numthreads(64, 1, 1)] void main() {
  using FloatMatAcc =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, 8, 8>;

  // Load a cooperative matrix first
  FloatMatAcc mat = FloatMatAcc::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(
      data, 0, stride);

  // Extract cooperative matrix into per-invocation arrays
  // Result array length must equal columns (8)
  // CHECK: OpCompositeExtractCoopMatQCOM
  vk::qcom::compositeExtractCooperativeMatrix(mat, resultArray);
}
