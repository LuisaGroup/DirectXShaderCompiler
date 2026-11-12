// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.1 -fspv-extension=SPV_EXT_long_vector %s -spirv 2>&1 | FileCheck %s

// L4 gate: a component count of four or less is an ordinary vector.
//
// SPV_EXT_long_vector widens OpTypeVector to "an arbitrary positive number of
// components", which includes 1, 2, 3 and 4 - but those already have a dedicated
// encoding in this backend (SpirvType::VectorType, the type every HLSL
// float2/float3/float4/vector<T, N> lowers to). Spelling
// vk::ext::LongVector<float, 4> would create a second, indistinguishable
// OpTypeVector %float 4 with the long-vector capability attached to it, so the
// header points the author at the native type instead.
//
// The check is in LowerTypeVisitor::lowerInlineSpirvType, where a
// vk::SpirvOpaqueType with the OpTypeVector opcode is turned into its SPIR-V
// type: that is the only place that sees the component count as a value, and it
// rejects the same spelling from a hand-written vk::SpirvOpaqueType as from the
// header.

#include <vk/ext/long_vector.h>

RWStructuredBuffer<float> g_out : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // CHECK: error: a vector with 4 components is an ordinary vector, which vk::ext::LongVector does not provide; use a native HLSL vector type (float2/float3/float4 or vector<T, N>) instead
  vk::ext::LongVector<float, 4> v4;
  g_out[0] = 1.0;
}
