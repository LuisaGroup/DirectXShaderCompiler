// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s

// Test that tensor layout and view types + functions compile and emit the
// correct capabilities and extensions. This validates the tensor_addressing.h
// header and its SPIR-V emission.
//
// Note: cooperativeMatrixLoadTensor / cooperativeMatrixStoreTensor are
// defined separately and require CooperativeMatrixTensorAddressingNV (5433).
// See cooperative_matrix2.h for the full tensor load/store integration.

#include <vk/nv/tensor_addressing.h>

// CHECK: OpCapability TensorAddressingNV
// CHECK: OpExtension "SPV_NV_tensor_addressing"

RWStructuredBuffer<float> data;
static const int stride = 64;

[numthreads(64, 1, 1)] void main() {
  // Create a tensor layout
  vk::nv::TensorLayout<2, 0> layout =
      vk::nv::createTensorLayout<2, 0>();
  // CHECK: OpCreateTensorLayoutNV
  layout = vk::nv::tensorLayoutSetDimension(layout, 0, 16);
  // CHECK: OpTensorLayoutSetDimensionNV
  layout = vk::nv::tensorLayoutSetDimension(layout, 1, 8);
  layout = vk::nv::tensorLayoutSetStride(layout, 0, 1);
  // CHECK: OpTensorLayoutSetStrideNV

  // Create a tensor view
  vk::nv::TensorView<2, false, 0, 1> view =
      vk::nv::createTensorView<2, false, 0, 1>();
  // CHECK: OpCreateTensorViewNV
  view = vk::nv::tensorViewSetDimension(view, 0, 16);
  // CHECK: OpTensorViewSetDimensionNV
  view = vk::nv::tensorViewSetDimension(view, 1, 8);
}
