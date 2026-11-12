// RUN: not %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_matrix_decode_vector -fspv-extension=SPV_NV_cooperative_matrix2 -fspv-extension=SPV_NV_tensor_addressing -fspv-extension=SPV_KHR_physical_storage_buffer %s 2>&1 | FileCheck %s
//
// G19/L4: the two operands of OpTypeTensorLayoutNV. Both are <id>s of 32-bit
// integer constants, and the validator checks their values:
//   "OpTypeTensorLayoutNV Dim <id> ... must be between 1 and 5."
//   "OpTypeTensorLayoutNV ClampMode <id> ... must be a valid TensorClampMode."
// so a layout with a rank of 0 or 6 is rejected here by CapabilityVisitor
// instead of producing a module that SPIRV-Tools rejects. Dim comes from a
// template argument of vk::nv::TensorLayout, so it is a compile-time constant and
// the message is reported once per module;
// nv.decode-vector.clamp.error.hlsl covers the ClampMode operand.

#include <vk/nv/cooperative_matrix_decode_vector.h>

using Mat = vk::khr::CooperativeMatrixA<float, vk::ScopeWorkgroup, 16, 16>;

groupshared float g_data[256];

[numthreads(1, 1, 1)]
void main() {
  Mat source;
  // CHECK: error: the dimension of a tensor layout (vk::nv::TensorLayout) must be between 1 and 5
  Mat m = vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV<4>(
      g_data, source,
      vk::nv::CreateTensorLayout<6, vk::nv::TensorClampModeClampToEdge>());
  m.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(
      vk::GetGroupSharedAddress(g_data[0]), 16);
}
