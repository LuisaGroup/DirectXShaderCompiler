// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.1 %s -spirv 2>&1 | FileCheck %s

// L4 gate: SPV_EXT_long_vector is an allow-list entry, not an always-on switch.
//
// enabledByDefault() returns false for Extension::EXT_long_vector, so without
// -fspv-extension=SPV_EXT_long_vector every use of vk::ext::LongVector is a
// compile error instead of a module that declares the LongVectorEXT capability
// and OpExtension "SPV_EXT_long_vector" - which a driver without
// VK_EXT_shader_long_vector rejects.
//
// The exact wording is FeatureManager::requestExtension's message, so this test
// also pins that the extension is registered (an unregistered name would be
// rejected earlier, as "unknown SPIR-V extension 'SPV_EXT_long_vector'", and
// -fspv-extension=SPV_EXT_long_vector could not be given at all).
//
// -fspv-target-env=vulkan1.1 is deliberate: the target environment has to be able
// to emit the extension before the permission check is the interesting failure;
// the too-old-environment diagnostic has its own test,
// vk.long-vector.env.error.hlsl.

#include <vk/ext/long_vector.h>

RWStructuredBuffer<float> g_in : register(u0);
RWStructuredBuffer<float> g_out : register(u1);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // CHECK: error: SPIR-V extension 'SPV_EXT_long_vector' required for long vector types but not permitted to use
  vk::ext::LongVector<float, 8> v8 = vk::ext::Concat(
      float4(g_in[0], g_in[1], g_in[2], g_in[3]),
      float4(g_in[4], g_in[5], g_in[6], g_in[7]));
  g_out[0] = vk::ext::Get<7>(v8);
}
