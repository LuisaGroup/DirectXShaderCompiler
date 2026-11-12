// RUN: not %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_matrix_decode_vector -fspv-extension=SPV_NV_cooperative_matrix2 -fspv-extension=SPV_NV_tensor_addressing -fspv-extension=SPV_KHR_physical_storage_buffer %s 2>&1 | FileCheck %s
//
// G19/L4: the decode-vector length. SPV_NV_cooperative_matrix_decode_vector
// allows the DecodeVectorFunc function to return a 2-, 4- or 8-component vector
// ("return vector length must be 2, 4, or 8."), and this header supports 2 and 4.
// Eight components would need OpCapability LongVectorEXT (SPV_EXT_long_vector) for
// the OpTypeVector, which <vk/nv/cooperative_matrix_decode_vector.h> deliberately
// does not request, so 8 is refused here instead of emitting a module that does
// not validate. The value is a compile-time constant (a template argument), so
// the diagnostic is raised while the call is translated and no module is written.

#include <vk/nv/cooperative_matrix_decode_vector.h>

using Mat = vk::khr::CooperativeMatrixA<float, vk::ScopeWorkgroup, 16, 16>;

groupshared float g_data[256];

[numthreads(1, 1, 1)]
void main() {
  Mat source;
  // CHECK: error: the decode vector length must be 2 or 4
  Mat m = vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV<8>(
      g_data, source,
      vk::nv::CreateTensorLayout<2, vk::nv::TensorClampModeClampToEdge>());
  m.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(
      vk::GetGroupSharedAddress(g_data[0]), 16);
}
