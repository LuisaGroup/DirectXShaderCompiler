// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/nv/tensor_addressing.h>

// CHECK: OpCapability TensorAddressingNV
// CHECK: OpExtension "SPV_NV_tensor_addressing"

RWStructuredBuffer<float> data;

[numthreads(64, 1, 1)] void main() {
  // Create a 2D tensor layout with constant clamp mode
  // CHECK: OpCreateTensorLayoutNV
  vk::nv::TensorLayout<2, 1> layout =
      vk::nv::createTensorLayout<2, 1>();

  // Set layout dimensions and stride
  // CHECK: OpTensorLayoutSetDimensionNV
  layout = vk::nv::tensorLayoutSetDimension(layout, 0, 16);
  // CHECK: OpTensorLayoutSetDimensionNV
  layout = vk::nv::tensorLayoutSetDimension(layout, 1, 8);
  // CHECK: OpTensorLayoutSetStrideNV
  layout = vk::nv::tensorLayoutSetStride(layout, 0, 1);
  // CHECK: OpTensorLayoutSetClampValueNV
  layout = vk::nv::tensorLayoutSetClampValue(layout, 0);

  // Create a 2D tensor view with identity permutation
  // CHECK: OpCreateTensorViewNV
  vk::nv::TensorView<2, false, 0, 1> view =
      vk::nv::createTensorView<2, false, 0, 1>();

  // Set view dimensions
  // CHECK: OpTensorViewSetDimensionNV
  view = vk::nv::tensorViewSetDimension(view, 0, 16);
  // CHECK: OpTensorViewSetDimensionNV
  view = vk::nv::tensorViewSetDimension(view, 1, 8);
}
