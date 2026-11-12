// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 %s -spirv 2>&1 | FileCheck %s
// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -fspv-extension=SPV_KHR_shader_clock %s -spirv 2>&1 | FileCheck %s --check-prefix=ALLOWLIST

// L4 gate: SPV_NV_cooperative_vector is an entry in FeatureManager's allow-list,
// not an always-on switch.
//
// FeatureManager::enabledByDefault returns false for
// Extension::NV_cooperative_vector, so the extension has to be named on the
// command line. Without it, every use of <vk/nv/cooperative_vector.h> is a
// compile error instead of a module that declares CooperativeVectorNV and
// OpExtension "SPV_NV_cooperative_vector" - which a driver without
// VK_NV_cooperative_vector rejects. The capability and the extension are added
// by CapabilityVisitor from the type and from the instruction, and both go
// through FeatureManager::requestExtension, which is what produces this
// diagnostic; [[vk::ext_capability]] / [[vk::ext_extension]] on the header's
// declarations could not, because those attributes write the capability and the
// extension string unconditionally.
//
// The message is also the evidence that the extension is registered as an
// allow-list entry: an unknown name would have been rejected earlier, as
// "error: unknown SPIR-V extension 'SPV_NV_cooperative_vector'", and the
// command-line option itself would not have accepted it (which is why
// -fspv-extension=SPV_NV_cooperative_vector works in the positive gates).
//
// The second RUN line is the allow-list half: an explicit -fspv-extension list
// that omits this extension refuses it in exactly the same way.
//
// -fspv-target-env=vulkan1.3 is deliberate: the target environment has to be
// able to emit the extension before the permission check is the interesting
// failure. There is no "target environment too old" test for this extension,
// because the grammar gives it no SPIR-V version requirement - see
// nv.cooperative-vector.hlsl, whose second RUN line compiles the same feature at
// the default (SPIR-V 1.0) target environment.
#include <vk/nv/cooperative_vector.h>

groupshared uint g_matrix[64];
groupshared uint g_vector[16];
RWStructuredBuffer<uint> g_out : register(u0);

[numthreads(1, 1, 1)] void main(uint3 tid : SV_DispatchThreadID) {
  // CHECK: error: SPIR-V extension 'SPV_NV_cooperative_vector' required for cooperative vector types but not permitted to use
  // ALLOWLIST: error: SPIR-V extension 'SPV_NV_cooperative_vector' required for cooperative vector types but not permitted to use
  vk::nv::CooperativeVector<uint, 4> v = vk::nv::Load<uint, 4>(g_vector, 0);
  // CHECK: error: SPIR-V extension 'SPV_NV_cooperative_vector' required for cooperative vectors but not permitted to use
  // ALLOWLIST: error: SPIR-V extension 'SPV_NV_cooperative_vector' required for cooperative vectors but not permitted to use
  vk::nv::CooperativeVector<uint, 4> r = vk::nv::MatrixMul<uint, 4, 4>(
      v, vk::CooperativeVectorComponentTypeUnsignedInt32NV, g_matrix, 0,
      vk::CooperativeVectorComponentTypeUnsignedInt32NV, 4, 4,
      vk::CooperativeVectorMatrixLayoutRowMajorNV, false, 16);
  vk::nv::Store<uint, 4>(g_vector, 4, r);
  g_out[0] = tid.x;
}
