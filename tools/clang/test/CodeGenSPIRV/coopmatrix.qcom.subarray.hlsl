// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/qcom/cooperative_matrix_conversion.h>

groupshared float data[64];
groupshared float sub[32];

// CHECK: OpCapability CooperativeMatrixConversionQCOM
// CHECK: OpExtension "SPV_QCOM_cooperative_matrix_conversion"

[numthreads(64, 1, 1)] void main() {
  // Extract a sub-array from a source array at the given index via inout parameter
  // CHECK: OpExtractSubArrayQCOM
  vk::qcom::extractSubArray(data, 16, sub);
}
