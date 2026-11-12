// RUN: not %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_matrix_decode_vector -fspv-extension=SPV_NV_cooperative_matrix2 -fspv-extension=SPV_NV_tensor_addressing -fspv-extension=SPV_KHR_physical_storage_buffer %s 2>&1 | FileCheck %s
//
// G19/L4: the second operand of OpTypeTensorLayoutNV. ClampMode is an <id> of a
// 32-bit integer constant, and the validator checks its value
// ("OpTypeTensorLayoutNV ClampMode <id> ... must be a valid TensorClampMode."),
// so a clamp mode above RepeatMirrored is rejected here by CapabilityVisitor
// instead of producing a module that SPIRV-Tools rejects. The value comes from a
// template argument of vk::nv::TensorLayout, so it is a compile-time constant and
// the message is reported once per module;
// nv.decode-vector.layout.error.hlsl covers the Dim operand.

#include <vk/nv/cooperative_matrix_decode_vector.h>

using Mat = vk::khr::CooperativeMatrixA<float, vk::ScopeWorkgroup, 16, 16>;

groupshared float g_data[256];

[numthreads(1, 1, 1)]
void main() {
  Mat source;
  Mat m = vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV<4>(
      g_data, source,
      // CHECK: error: the clamp mode of a tensor layout (vk::nv::TensorLayout) must be one of the five TensorClampMode enumerators
      vk::nv::CreateTensorLayout<2, 5>());
  m.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(
      vk::GetGroupSharedAddress(g_data[0]), 16);
}
