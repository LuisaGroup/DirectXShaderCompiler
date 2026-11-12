// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.0 -fspv-extension=SPV_EXT_long_vector %s -spirv 2>&1 | FileCheck %s

// L4 gate: SPV_EXT_long_vector requires a SPIR-V 1.3 target environment.
//
// The extension is written as "Modifications to the SPIR-V Specification" for
// SPIR-V 1.3 ("This extension requires SPIR-V 1.3"), so a module at SPIR-V 1.0
// cannot use it. DXC's default target environment is vulkan1.0, which emits
// SPIR-V 1.0, so a long vector without -fspv-target-env is refused instead of
// being emitted into a module whose version predates the extension.
//
// The check is FeatureManager::isTargetEnvSpirv1p3OrAbove, which compares the
// SPIR-V *version* the environment emits (FeatureManager::getSpirvVersion)
// rather than the spv_target_env enumerators: every Vulkan environment sorts
// above every universal one, so comparing enumerators would consider vulkan1.0
// newer than SPIR-V 1.3. The message is
// FeatureManager::requestTargetEnvSpirv1p3's.
//
// This file uses -fspv-extension=SPV_EXT_long_vector, so the extension itself is
// permitted and the environment is the only failure.

#include <vk/ext/long_vector.h>

RWStructuredBuffer<float> g_out : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // CHECK: error: SPIR-V 1.3 is required for long vector types but not permitted to use
  // CHECK: note: please specify your target environment via command line option -fspv-target-env=
  vk::ext::LongVector<float, 8> v8;
  g_out[0] = vk::ext::Get<7>(v8);
}
