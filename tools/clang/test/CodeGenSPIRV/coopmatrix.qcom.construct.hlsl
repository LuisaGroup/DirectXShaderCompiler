// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/qcom/cooperative_matrix_conversion.h>

groupshared float data[8];

// CHECK: OpCapability CooperativeMatrixConversionQCOM
// CHECK: OpExtension "SPV_QCOM_cooperative_matrix_conversion"

[numthreads(64, 1, 1)] void main() {
  // Construct a cooperative matrix from per-invocation arrays.
  // The array length must equal the number of columns (8) for float32
  // MatrixAccumulatorKHR.
  // CHECK: OpCompositeConstructCoopMatQCOM
  vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, 8, 8> mat =
      vk::qcom::compositeConstructCooperativeMatrix<
          float, vk::ScopeSubgroup, 8, 8,
          vk::CooperativeMatrixUseMatrixAccumulatorKHR>(data);
}