// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.1 -fspv-extension=SPV_EXT_long_vector %s -spirv | FileCheck %s

// L0/L1/L2 gates for VK_EXT_shader_long_vector / SPV_EXT_long_vector.
//
// The type is <vk/ext/long_vector.h>. HLSL cannot spell a vector with more than
// four components (Sema rejects vector<T, N> for N > 4 with "invalid value,
// valid range is between 1 and 4 inclusive"), so the header builds one out of
// vk::SpirvOpaqueType<OpTypeVector, T, Literal<integral_constant<uint, N>>>:
//
//   vk::ext::LongVector<float, 8>  ->  OpTypeVector %float 8
//   vk::ext::LongVector<float, 16> ->  OpTypeVector %float 16
//
// A module that contains either declares the LongVectorEXT (5425) capability
// and OpExtension "SPV_EXT_long_vector". Both are added by the
// SpirvIntrinsicType case in CapabilityVisitor::addCapabilityForType from the
// type itself, not by [[vk::ext_capability]] / [[vk::ext_extension]] on the
// header's declarations, which is what makes -fspv-extension able to refuse the
// extension (see vk.long-vector.extension.error.hlsl).
//
// -fspv-target-env=vulkan1.1 is part of the gate: the extension is specified
// against SPIR-V 1.3, and the default target environment (vulkan1.0) emits
// SPIR-V 1.0. vulkan1.1 is the minimum environment that works; the error case is
// pinned in vk.long-vector.env.error.hlsl.
//
// Values are read from a buffer so that nothing here is a constant the
// optimizer could fold away; the L1/L2 assertions below are the pre-legalization
// stream, which is what -fcgl exists for. The post-optimizer form is pinned
// separately in vk.long-vector.opt.hlsl.

#include <vk/ext/long_vector.h>

RWStructuredBuffer<float> g_in : register(u0);
RWStructuredBuffer<float> g_out : register(u1);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // The long vector is built from ordinary vectors, which is the constructor
  // path: OpCompositeConstruct (80) concatenates its constituents in order.
  float4 lo = float4(g_in[0], g_in[1], g_in[2], g_in[3]);
  float4 hi = float4(g_in[4], g_in[5], g_in[6], g_in[7]);
  vk::ext::LongVector<float, 8> v8 = vk::ext::Concat(lo, hi);

  // Per-component write: OpCompositeInsert (82) with a literal index. The
  // operand order is the instruction's - the new component ("Object") first, the
  // value it is inserted into ("Composite") second.
  v8 = vk::ext::Set<5>(v8, g_in[8]);

  // Per-component read: OpCompositeExtract (81) with a literal index above 3,
  // which is the encoding OpTypeVector cannot produce without LongVectorEXT.
  float x = vk::ext::Get<7>(v8);

  // A 16-component vector from two 8-component ones, and from four ordinary
  // 4-component ones.
  vk::ext::LongVector<float, 16> v16 = vk::ext::Concat(v8, v8);
  vk::ext::LongVector<float, 16> w16 = vk::ext::Concat(lo, hi, lo, hi);

  g_out[0] = x + vk::ext::Get<15>(v16) + vk::ext::Get<3>(w16);
}

// L1: exactly one OpCapability LongVectorEXT and exactly one OpExtension, and
// Shader is still declared once. The CHECK-NOT regions are anchored between the
// lines that bound them, so they cover the capability block and the extension
// block rather than the whole file.
// CHECK:      OpCapability Shader
// CHECK-NOT:  OpCapability Shader
// CHECK:      OpCapability LongVectorEXT
// CHECK-NOT:  OpCapability LongVectorEXT
// CHECK:      OpExtension "SPV_EXT_long_vector"
// CHECK-NOT:  OpExtension "SPV_EXT_long_vector"
// CHECK:      OpMemoryModel Logical GLSL450

// L2: one OpTypeVector with 8 and one with 16 components. The anti-false-green
// assertion is the CHECK-NOT on OpTypeArray: a compiler that packs a long vector
// into an array of ordinary vectors would still contain the two CHECK lines
// above only by accident, but it would necessarily contain the array type.
// CHECK:      %[[V8:[A-Za-z0-9_]+]] = OpTypeVector %float 8
// CHECK:      %[[V16:[A-Za-z0-9_]+]] = OpTypeVector %float 16
// CHECK-NOT:  OpTypeArray %float
// CHECK:      OpFunction

// L2: OpCompositeConstruct from two ordinary vectors, from two long vectors and
// from four ordinary vectors.
// CHECK:      OpCompositeConstruct %[[V8]] %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}}
// CHECK:      OpCompositeConstruct %[[V16]] %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}}
// CHECK:      OpCompositeConstruct %[[V16]] %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}}

// L2: OpCompositeInsert at component 5, then OpCompositeExtract at 7, 15 and 3 -
// the indices above 3 are the ones the capability exists for.
// CHECK:      OpCompositeInsert %[[V8]] %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}} 5
// CHECK:      OpCompositeExtract %float %{{[A-Za-z0-9_]+}} 7
// CHECK:      OpCompositeExtract %float %{{[A-Za-z0-9_]+}} 15
// CHECK:      OpCompositeExtract %float %{{[A-Za-z0-9_]+}} 3
