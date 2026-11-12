// RUN: not %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_matrix_decode_vector -fspv-extension=SPV_NV_cooperative_matrix2 -fspv-extension=SPV_NV_tensor_addressing -fspv-extension=SPV_KHR_physical_storage_buffer %s 2>&1 | FileCheck %s
//
// G19/L4: the Pointer operand of OpCooperativeMatrixLoadTensorNV has to be a
// pointer whose storage class is Workgroup, StorageBuffer or
// PhysicalStorageBuffer ("storage class for pointer type <id> ... is not
// Workgroup, StorageBuffer, or PhysicalStorageBuffer."). An *element* of the
// groupshared array is a pointer to a scalar in the right storage class, which
// the validator accepts but which is not the tensor memory the block is read
// from; this test passes `g_data[0]` instead of `g_data` so that the shape the
// header asks for (the array, passed whole) is what the diagnostic pins.

#include <vk/nv/cooperative_matrix_decode_vector.h>

using Mat = vk::khr::CooperativeMatrixA<float, vk::ScopeWorkgroup, 16, 16>;

groupshared float g_data[256];

[numthreads(1, 1, 1)]
void main() {
  Mat source;
  // CHECK: error: the first argument of __builtin_spv_CooperativeMatrixLoadTensorNV must be an array
  Mat m = vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV<4>(
      g_data[0], source,
      vk::nv::CreateTensorLayout<2, vk::nv::TensorClampModeClampToEdge>());
  m.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(
      vk::GetGroupSharedAddress(g_data[0]), 16);
}
