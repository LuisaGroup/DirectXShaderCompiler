// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

#include <vk/nv/tensor_addressing.h>

// CHECK: OpCapability TensorAddressingNV
// CHECK: OpExtension "SPV_NV_tensor_addressing"

[numthreads(64, 1, 1)] void main() {
  // Create a 2D tensor view with no dimensions and identity permutation
  // CHECK: OpCreateTensorViewNV
  vk::nv::TensorView<2, false, 0, 1> view =
      vk::nv::createTensorView<2, false, 0, 1>();

  // Set dimension 0 size
  // CHECK: OpTensorViewSetDimensionNV
  view = vk::nv::tensorViewSetDimension(view, 0, 16);

  // Set dimension 1 size
  // CHECK: OpTensorViewSetDimensionNV
  view = vk::nv::tensorViewSetDimension(view, 1, 8);

  // Set stride for dimension 0
  // CHECK: OpTensorViewSetStrideNV
  view = vk::nv::tensorViewSetStride(view, 0, 1);

  // Set clip region
  // CHECK: OpTensorViewSetClipNV
  view = vk::nv::tensorViewSetClip(view, 0, 8, 0, 16);
}
