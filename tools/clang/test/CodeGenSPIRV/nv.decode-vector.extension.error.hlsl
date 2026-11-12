// RUN: not %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_matrix2 -fspv-extension=SPV_NV_tensor_addressing -fspv-extension=SPV_KHR_physical_storage_buffer %s 2>&1 | FileCheck %s
//
// G19/L4: SPV_NV_cooperative_matrix_decode_vector is an allow-list entry, not an
// always-on switch, so a module can never carry the DecodeVectorFunc bit without
// the extension (and the CooperativeMatrixDecodeVectorNV capability) Vulkan
// requires of it.
//
// The other three extensions the module needs *are* listed, so the failure is
// about this one and not about a prerequisite: an explicit -fspv-extension list
// replaces the set of extensions that are enabled by default
// (FeatureManager::FeatureManager), and the decode-vector extension is
// registered with enabledByDefault() == false.
//
// The exact wording is FeatureManager::requestExtension's message, so this test
// also pins that the extension is registered: an unregistered name would be
// rejected earlier, as "unknown SPIR-V extension
// 'SPV_NV_cooperative_matrix_decode_vector'", and -fspv-extension could not name
// it at all.

#include <vk/nv/cooperative_matrix_decode_vector.h>

using Mat = vk::khr::CooperativeMatrixA<float, vk::ScopeWorkgroup, 16, 16>;

groupshared float g_data[256];

[numthreads(1, 1, 1)]
void main() {
  Mat source;
  // CHECK: error: SPIR-V extension 'SPV_NV_cooperative_matrix_decode_vector' required for cooperative matrix decode vector block loads but not permitted to use
  Mat m = vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV<4>(
      g_data, source,
      vk::nv::CreateTensorLayout<2, vk::nv::TensorClampModeClampToEdge>());
  m.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(
      vk::GetGroupSharedAddress(g_data[0]), 16);
}
