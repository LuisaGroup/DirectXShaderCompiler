// RUN: %dxc -T cs_6_0 -E main -fcgl %s -spirv | FileCheck %s

// L5 off-path regression for SPV_EXT_long_vector.
//
// <vk/ext/long_vector.h> only declares templates and
// [[vk::ext_instruction]] prototypes, so including it adds nothing to a module:
// no OpCapability LongVectorEXT, no OpExtension "SPV_EXT_long_vector", and no
// long OpTypeVector. The capability, the extension and the type are all driven
// by the *use* of vk::ext::LongVector (CapabilityVisitor sees the
// SpirvIntrinsicType, LowerTypeVisitor rejects a component count of four or
// less), which is what keeps the extension opt-in rather than something that
// starts changing existing shaders the moment a header is included.
//
// The shader below is the pre-existing shape it must keep working: ordinary
// 4-component vectors. The CHECK-NOT regions are anchored between the lines that
// bound them so they cover the capability block, the extension block and the
// type block, rather than being vacuous end-of-file assertions.
//
// The behavioral half of L5 - a long vector being refused rather than lowered to
// something else when the extension is off - is pinned in
// vk.long-vector.extension.error.hlsl.

#include <vk/ext/long_vector.h>

RWStructuredBuffer<float> g_in : register(u0);
RWStructuredBuffer<float> g_out : register(u1);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // CHECK:      OpCapability Shader
  // CHECK-NOT:  OpCapability LongVectorEXT
  // CHECK-NOT:  OpExtension "SPV_EXT_long_vector"
  // CHECK:      OpMemoryModel Logical GLSL450
  float4 v = float4(g_in[0], g_in[1], g_in[2], g_in[3]);
  // CHECK:      %[[V4:[A-Za-z0-9_]+]] = OpTypeVector %float 4
  // CHECK-NOT:  OpTypeVector %float 8
  // CHECK-NOT:  OpTypeVector %float 16
  // CHECK:      OpFunction
  g_out[0] = v.x + v.w;
}
