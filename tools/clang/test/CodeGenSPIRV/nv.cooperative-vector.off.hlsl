// RUN: %dxc -T cs_6_0 -E main -fcgl %s -spirv | FileCheck %s

// L5 off-path regression for VK_NV_cooperative_vector.
//
// <vk/nv/cooperative_vector.h> only declares templates and
// [[vk::ext_instruction]] prototypes, so including it adds nothing to a module:
// no OpCapability CooperativeVectorNV, no OpCapability
// CooperativeVectorTrainingNV, no OpExtension "SPV_NV_cooperative_vector", no
// OpTypeVectorIdEXT and no OpCooperativeVector*NV instruction. The capability,
// the extension and the type are all driven by *use* - CapabilityVisitor sees
// the SpirvIntrinsicType and the instruction - which is what keeps the extension
// usable as an allow-list entry that changes nothing until a shader asks for it.
// Note that -fspv-extension is deliberately absent: an include plus ordinary
// HLSL has to stay byte-for-byte the module it was before this header existed.
//
// The CHECK-NOT regions are anchored between the lines that bound them, so they
// cover the capability block, the extension block and the type block instead of
// being vacuous end-of-file assertions. The near miss this pins is the ordinary
// 4-component vector, which is the encoding a cooperative vector would be
// mistaken for if the type were implemented as an OpTypeVector with a count.
//
// What is not covered here: the behavior of the entry points with the extension
// off. They are not silently lowered to something else; every call is a compile
// error, which is pinned in nv.cooperative-vector.extension.error.hlsl.
#include <vk/nv/cooperative_vector.h>

RWStructuredBuffer<float> g_in : register(u0);
RWStructuredBuffer<float> g_out : register(u1);
groupshared float g_shared[16];

[numthreads(1, 1, 1)] void main(uint3 tid : SV_DispatchThreadID) {
  // CHECK: OpCapability Shader
  // CHECK-NOT: OpCapability CooperativeVectorNV
  // CHECK-NOT: OpCapability CooperativeVectorTrainingNV
  // CHECK-NOT: OpExtension "SPV_NV_cooperative_vector"
  // CHECK: OpMemoryModel Logical GLSL450
  float4 v = float4(g_in[0], g_in[1], g_in[2], g_in[3]);
  // The ordinary vector stays an OpTypeVector, and no cooperative vector type
  // appears next to it.
  // CHECK: %[[V4:[A-Za-z0-9_]+]] = OpTypeVector %float 4
  // CHECK-NOT: OpTypeVectorIdEXT
  // CHECK-NOT: OpTypeCooperativeVectorNV
  // CHECK: OpFunction
  g_shared[0] = v.x + v.w;
  g_out[0] = g_shared[0];
  // CHECK: OpFunctionEnd
  // CHECK-NOT: OpCooperativeVector
}
