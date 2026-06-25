// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/nv/tensor_addressing.h>

// CHECK: OpCapability TensorAddressingNV
// CHECK: OpExtension "SPV_NV_tensor_addressing"

[numthreads(64, 1, 1)] void main() {
  // Create a 2D tensor layout with undefined clamp mode
  // CHECK: OpCreateTensorLayoutNV
  vk::nv::TensorLayout<2, 0> layout = vk::nv::createTensorLayout<2, 0>();

  // Set dimension 0 size to 16
  // CHECK: OpTensorLayoutSetDimensionNV
  layout = vk::nv::tensorLayoutSetDimension(layout, 0, 16);

  // Set dimension 1 size to 8
  // CHECK: OpTensorLayoutSetDimensionNV
  layout = vk::nv::tensorLayoutSetDimension(layout, 1, 8);

  // Set stride for dimension 0
  // CHECK: OpTensorLayoutSetStrideNV
  layout = vk::nv::tensorLayoutSetStride(layout, 0, 1);

  // Set block size for dimension 0
  // CHECK: OpTensorLayoutSetBlockSizeNV
  layout = vk::nv::tensorLayoutSetBlockSize(layout, 0, 4);

  // Set clamp value
  // CHECK: OpTensorLayoutSetClampValueNV
  layout = vk::nv::tensorLayoutSetClampValue(layout, 0);
}
