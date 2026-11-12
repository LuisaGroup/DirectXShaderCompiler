// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.1 -fspv-extension=SPV_EXT_long_vector %s -spirv 2>&1 | FileCheck %s

// L4 gate: the component count has to be a compile-time constant.
//
// SPV_EXT_long_vector can build a vector whose component count comes from a
// specialization constant, but that is a different type instruction:
// OpTypeVectorIdEXT (5288), whose Component Count is an <id> of a 32-bit integer
// constant instruction instead of a LiteralInteger:
//
//   %v = OpTypeVectorIdEXT %float %count      ; %count is an OpSpecConstant
//
// This landing deliberately does not implement it (see docs/SPIR-V.rst, "Long
// vectors"): the type would have to be keyed on a spec-constant id in
// SpirvContext's structural uniquing, and the storage-class rules differ again
// for spec-constant-sized vectors (they are rejected in explicitly laid out
// storage classes). vk::ext::LongVector takes its count as a template argument,
// so a run-time value is rejected by the front end before anything reaches
// SPIR-V CodeGen - which is the point of this test: there is no path from a
// non-constant count to a malformed OpTypeVector.

#include <vk/ext/long_vector.h>

RWStructuredBuffer<float> g_out : register(u0);

[numthreads(1, 1, 1)]
void main(uint n : SV_DispatchThreadID) {
  // CHECK: error: non-type template argument of type 'uint' is not an integral constant expression
  vk::ext::LongVector<float, n> v;
  g_out[0] = 1.0;
}
