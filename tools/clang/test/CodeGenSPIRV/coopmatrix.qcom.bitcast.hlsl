// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/qcom/cooperative_matrix_conversion.h>

groupshared float data[64];
groupshared uint32_t casted[64];

// CHECK: OpCapability CooperativeMatrixConversionQCOM
// CHECK: OpExtension "SPV_QCOM_cooperative_matrix_conversion"

[numthreads(64, 1, 1)] void main() {
  // Bitcast between compatible 1D arrays via inout parameter
  // CHECK: OpBitCastArrayQCOM
  vk::qcom::bitCastArray(data, casted);
}
