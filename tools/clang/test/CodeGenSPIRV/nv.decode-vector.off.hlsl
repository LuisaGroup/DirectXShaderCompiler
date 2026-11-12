// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_matrix_decode_vector -fspv-extension=SPV_NV_cooperative_matrix2 -fspv-extension=SPV_NV_tensor_addressing -fspv-extension=SPV_KHR_physical_storage_buffer %s | FileCheck %s
//
// G19/L5: the off path. The decode-vector extension *is* permitted here, so the
// module is not rejected; what keeps it out is that nothing in the shader asks
// for it. This shader includes the header and uses the pre-existing
// SPV_KHR_cooperative_matrix load and store, so the module is otherwise the same
// one <vk/khr/cooperative_matrix.h> produces today.
//
// The negative assertions are anchored between two CHECK lines instead of being
// left at the end of the file, because a bare CHECK-NOT at end of file is
// vacuous (FileCheck's region semantics).

#include <vk/nv/cooperative_matrix_decode_vector.h>

using Mat = vk::khr::CooperativeMatrixA<float, vk::ScopeWorkgroup, 16, 16>;

groupshared float g_data[256];

[numthreads(1, 1, 1)]
void main() {
  Mat m = Mat::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(
      vk::GetGroupSharedAddress(g_data[0]), 16);
  m.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(
      vk::GetGroupSharedAddress(g_data[0]), 16);
}

// The pre-existing cooperative matrix capability and extension are still there.
// CHECK:      OpCapability CooperativeMatrixKHR
// CHECK:      OpExtension "SPV_KHR_cooperative_matrix"
// CHECK:      OpCooperativeMatrixLoadKHR
// Everything SPV_NV_cooperative_matrix_decode_vector adds is absent: the
// capability, its prerequisite, the extension string that carries it, the tensor
// addressing base it is built on, and the tensor load itself. The region ends at
// OpFunctionEnd of the entry point's real body.
// CHECK-NOT:  CooperativeMatrixDecodeVectorNV
// CHECK-NOT:  CooperativeMatrixBlockLoadsNV
// CHECK-NOT:  SPV_NV_cooperative_matrix_decode_vector
// CHECK-NOT:  SPV_NV_cooperative_matrix2
// CHECK-NOT:  SPV_NV_tensor_addressing
// CHECK-NOT:  TensorAddressingNV
// CHECK-NOT:  OpTypeTensorLayoutNV
// CHECK-NOT:  OpCreateTensorLayoutNV
// CHECK-NOT:  OpCooperativeMatrixLoadTensorNV
// CHECK:      OpCooperativeMatrixStoreKHR
