// RUN: %dxc -T cs_6_0 -E main -fspv-target-env=vulkan1.1 -fspv-extension=SPV_EXT_long_vector %s -spirv | FileCheck %s

// L6 optimizer-survival gate for SPV_EXT_long_vector: the same shader as
// vk.long-vector.hlsl, compiled *without* -fcgl, so SpirvEmitter's
// post-processing runs (HLSL legalization, the spirv-opt pass list and the
// capability-trimming pass) before validation.
//
// Two things can only break here:
//
// * Capability trimming (SpirvEmitter::spirvToolsTrimCapabilities) could remove
//   LongVectorEXT, leaving a module that declares an OpTypeVector with 8 or 16
//   components and no capability. It does not: the vendored SPIRV-Tools trimming
//   pass only touches the capabilities listed in kSupportedCapabilities, and
//   LongVectorEXT is not in that list, so it is left alone. Validation would fail
//   loudly if this changed - "Having 8 components for TypeVector requires the
//   Vector16 or LongVectorEXT capability" - which is the negative control for
//   this gate.
// * The optimizer could fail to keep the type or rewrite the composite
//   instructions. The instructions that survive are asserted below.
//
// Note that the OpCompositeExtract instructions do *not* survive as such: the
// optimizer folds extract(construct) into the constituents, which is a correct
// rewrite and exactly the kind of change -fcgl cannot show. The type, the
// capability, the extension, the constructs and the insert do survive, and the
// module must still validate (that is the real L6 assertion: nothing here is
// compiled with -Vd).

#include <vk/ext/long_vector.h>

RWStructuredBuffer<float> g_in : register(u0);
RWStructuredBuffer<float> g_out : register(u1);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  float4 lo = float4(g_in[0], g_in[1], g_in[2], g_in[3]);
  float4 hi = float4(g_in[4], g_in[5], g_in[6], g_in[7]);
  vk::ext::LongVector<float, 8> v8 = vk::ext::Concat(lo, hi);
  v8 = vk::ext::Set<5>(v8, g_in[8]);
  float x = vk::ext::Get<7>(v8);
  vk::ext::LongVector<float, 16> v16 = vk::ext::Concat(v8, v8);
  vk::ext::LongVector<float, 16> w16 = vk::ext::Concat(lo, hi, lo, hi);
  g_out[0] = x + vk::ext::Get<15>(v16) + vk::ext::Get<3>(w16);
}

// CHECK:      OpCapability Shader
// CHECK:      OpCapability LongVectorEXT
// CHECK-NOT:  OpCapability LongVectorEXT
// CHECK:      OpExtension "SPV_EXT_long_vector"
// CHECK-NOT:  OpExtension "SPV_EXT_long_vector"
// CHECK:      OpMemoryModel Logical GLSL450

// CHECK:      %[[V8:[A-Za-z0-9_]+]] = OpTypeVector %float 8
// CHECK:      %[[V16:[A-Za-z0-9_]+]] = OpTypeVector %float 16
// CHECK-NOT:  OpTypeArray %float
// CHECK:      OpFunction

// CHECK:      OpCompositeConstruct %[[V8]] %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}}
// CHECK:      OpCompositeInsert %[[V8]] %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}} 5
// CHECK:      OpCompositeConstruct %[[V16]] %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}}
// CHECK:      OpCompositeConstruct %[[V16]] %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}} %{{[A-Za-z0-9_]+}}
