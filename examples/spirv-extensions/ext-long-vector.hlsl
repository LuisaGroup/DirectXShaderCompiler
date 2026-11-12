// RUN: %dxc -T cs_6_0 -E main -spirv -fcgl -fspv-target-env=vulkan1.1 -fspv-extension=SPV_EXT_long_vector %s

// Long vectors with VK_EXT_shader_long_vector / SPV_EXT_long_vector.
//
// SPIR-V's OpTypeVector is limited to 1..4 components unless the module declares
// OpCapability LongVectorEXT (5425), which SPV_EXT_long_vector defines. With the
// capability a vector may have an arbitrary positive number of components, and
// the instructions that accept vector types accept those vectors too - so the
// arithmetic, OpLoad/OpStore, OpCompositeExtract/Insert/Construct and even
// OpVectorShuffle - with a fixed set of storage classes (Function, Private,
// UniformConstant, Uniform, Workgroup, StorageBuffer, PhysicalStorageBuffer,
// PushConstant, ShaderRecordBufferKHR, CrossWorkgroup, Generic).
//
// What it is for: a shader that naturally works on more than four related
// components - a 6-DOF pose, an 8-tap filter kernel, 16 packed lanes - can keep
// them in one value instead of splitting them into float4s by hand. The
// implementation decides how a wide vector is executed: it may be one register
// group per component, or wider registers, and the number of components a
// implementation accepts at all is a device limit (see "Required from the host").
//
// HLSL has no type of its own for this. vector<T, N> is rejected by the front end
// for N > 4, so the type comes from <vk/ext/long_vector.h>:
//
//   vk::ext::LongVector<float, 8> v = vk::ext::Concat(lo, hi);  // OpCompositeConstruct
//   v = vk::ext::Set<5>(v, x);                                 // OpCompositeInsert
//   float y = vk::ext::Get<7>(v);                              // OpCompositeExtract
//
// The value is built from, and decomposed into, ordinary vectors. This header is
// a type plus element access, not a new arithmetic system: HLSL's operators,
// swizzles and implicit conversions are defined on ordinary vectors and do not
// apply to a long vector, so anything arithmetic is done on the float4 halves
// this example reads and writes, with the long vector carrying the value in
// between.
//
// The compiler emits, for the shader below:
//   OpCapability LongVectorEXT
//   OpExtension "SPV_EXT_long_vector"
//   %v8   = OpTypeVector %float 8
//   %v16  = OpTypeVector %float 16
//   %v8   = OpCompositeConstruct %v8 %lo %hi        ; from two float4
//   %v8   = OpCompositeInsert %v8 %x %v8 5          ; component 5
//   %f    = OpCompositeExtract %float %v8 7         ; component 7
//
// Restrictions, all diagnosed by the compiler rather than miscompiled:
// * -fspv-target-env=vulkan1.1 or later. SPV_EXT_long_vector is specified
//   against SPIR-V 1.3, and the default target environment (vulkan1.0) emits
//   SPIR-V 1.0.
// * -fspv-extension=SPV_EXT_long_vector. The extension is opt-in: a driver that
//   does not expose VK_EXT_shader_long_vector rejects a module that declares
//   LongVectorEXT.
// * The component count must be a compile-time constant greater than four. Four
//   or fewer components is an ordinary HLSL vector, and a count from a
//   specialization constant would need OpTypeVectorIdEXT (5288), which this
//   landing does not implement.
// * No stage input/output: SPV_EXT_long_vector does not list Input or Output
//   among the storage classes long vectors may be allocated in.
//
// Required from the host - the compiler cannot check any of this:
// * the VK_EXT_shader_long_vector device extension (enable
//   VK_EXT_SHADER_LONG_VECTOR_EXTENSION_NAME at vkCreateDevice),
// * its longVector feature bit, queried and enabled through the extension's
//   feature struct in the VkPhysicalDeviceFeatures2 / VkDeviceCreateInfo pNext
//   chain,
// * the device limit on the number of components: query the extension's
//   properties struct and keep maxVectorComponents in mind. A shader that uses
//   more components than the device reports still compiles and validates, but
//   creating the pipeline fails - the compiler cannot see the limit, so a shader
//   that must run on a range of devices should keep its long vectors as narrow as
//   it can, or the application should specialize on the reported limit.
// * the host must lay out any buffer that interleaves long vectors with the same
//   rule the shader assumes; this example only ever holds the long vector in
//   Function storage and reads/writes scalars, so no buffer layout is implied.
//
// See docs/SPIR-V.rst ("Long vectors") for the full description and
// tools/clang/test/CodeGenSPIRV/vk.long-vector*.hlsl for the tests that pin the
// capability, the type encoding, the composite instructions, the optimizer path
// and the diagnostics.

#include <vk/ext/long_vector.h>

// Eight input taps and eight output taps. The shader below keeps an 8-component
// value in one SPIR-V vector and a 16-component value to show that the type
// scales, instead of juggling two and four float4s.
RWStructuredBuffer<float> g_in : register(u0);
RWStructuredBuffer<float> g_out : register(u1);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  const uint base = tid.x * 8;

  // The two ordinary halves the extension is worth having for: without it these
  // would have to be carried around separately all the way to the consumer.
  float4 low = float4(g_in[base + 0], g_in[base + 1], g_in[base + 2],
                      g_in[base + 3]);
  float4 high =
      float4(g_in[base + 4], g_in[base + 5], g_in[base + 6], g_in[base + 7]);

  // OpCompositeConstruct %v8 %low %high - the constructor-from-smaller-vectors
  // path. The constituents are concatenated in order, so component i is low[i]
  // for i < 4 and high[i - 4] otherwise.
  vk::ext::LongVector<float, 8> taps = vk::ext::Concat(low, high);

  // OpCompositeInsert %v8 <new> %taps 5 - a per-component update, which is what
  // OpCompositeInsert is for: one component changes, the other seven are
  // carried over unchanged.
  taps = vk::ext::Set<5>(taps, g_in[base + 5] * 2.0);

  // OpCompositeExtract %float %taps 7 - read one component back. The index is
  // above 3, which OpTypeVector cannot express without LongVectorEXT.
  const float last = vk::ext::Get<7>(taps);

  // The same value widened again: a 16-component vector built from two
  // 8-component ones, and from four ordinary 4-component ones. Both forms are
  // one OpCompositeConstruct.
  vk::ext::LongVector<float, 16> wide = vk::ext::Concat(taps, taps);
  vk::ext::LongVector<float, 16> four = vk::ext::Concat(low, high, low, high);

  // The reduction is ordinary HLSL on ordinary vectors - the long vectors above
  // are storage for the value, not a new arithmetic.
  const float sum = low.x + high.w + last + vk::ext::Get<0>(wide) +
                    vk::ext::Get<15>(four);
  g_out[tid.x] = sum;
}
