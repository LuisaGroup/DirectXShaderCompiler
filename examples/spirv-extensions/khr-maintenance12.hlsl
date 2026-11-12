// RUN: %dxc -T cs_6_0 -E main -spirv -fcgl %s

// Selecting push-constant data with a divergent index (VK_KHR_maintenance12).
// ---------------------------------------------------------------------------
// What the extension permits
// --------------------------
// VK_KHR_maintenance12 is a Vulkan *device* extension, revision 1 (2026-03-25):
// "a collection of minor features, none of which would warrant an entire
// extension of their own". The first of the four items it lists is the one this
// example is about, and the extension states it in one line: non-uniform indexing
// of values within a variable with a PushConstant storage class. Before it, a
// push-constant subscript had to be dynamically uniform - one block could not be
// indexed by a per-invocation value - even in a shader that was already free to
// index a descriptor array non-uniformly.
//
// How it appears in SPIR-V
// ------------------------
// The permission adds no instruction and no new capability, and there is no
// OpExtension string for it. The SPIR-V side already has the one thing it needs:
// the NonUniform decoration (5300), defined by SPV_EXT_descriptor_indexing, on the
// access chain whose Array Index is divergent, together with the ShaderNonUniform
// capability (5301) that legalises the decoration. A module carrying them is the
// module maintenance12 makes runnable; on a device without the extension it is
// exactly the case the extension removes.
//
// There is no SPV_KHR_maintenance12 in the Khronos SPIR-V registry - checked
// against the vendored grammar, external/SPIRV-Headers v2026.08.0, whose only
// "maintenance" names are SPV_EXT_cooperative_matrix_maintenance1 - so asking DXC
// for -fspv-extension=SPV_KHR_maintenance12 is an "unknown SPIR-V extension" error
// on purpose, and nothing in the module header changes for maintenance12. There is
// no new target environment to select either: DXC's -fspv-target-env list stops at
// vulkan1.3, and the relaxation belongs to a device that enables the extension, so
// it is a property of the device and not of the target env.
//
// Why the HLSL shader has to say so
// ---------------------------------
// DXC does not infer uniformity. An index that happens to be divergent does not
// become a NonUniform decoration by itself: HLSL has one way to declare it,
// NonUniformResourceIndex(), and despite the name it is not restricted to resource
// handles - its Sema check accepts a plain uint, which is what makes it usable on a
// push-constant subscript. DXC lowers it to an OpCopyObject marked NonUniform
// (SpirvEmitter::processIntrinsicNonUniformResourceIndex) and NonUniformVisitor
// propagates the marking to the access chain, to the load, and to the instructions
// that consume the loaded value. The two forms, side by side:
//
// g_push.materials[NonUniformResourceIndex(tid.x & 7)] -> a decorated chain
// g_push.scale -> an undecorated chain, unchanged
//
// The intrinsic is written directly at each subscript below rather than stored in
// a local first: the marking lives on the instruction that produces the index, and
// a value parked in a Function-storage variable only gets it back once the
// optimizer has promoted that variable to an SSA value (compile this file without
// -fcgl to see the promoted form).
//
// Required from the host
// ----------------------
// * the device extension VK_KHR_maintenance12, enabled at vkCreateDevice
//   (VK_KHR_MAINTENANCE_12_EXTENSION_NAME);
// * the feature bits it exposes for the items in use: the extension defines
//   VkPhysicalDeviceMaintenance12FeaturesKHR, queried with
//   vkGetPhysicalDeviceFeatures2 and enabled by chaining the structure into
//   VkDeviceCreateInfo::pNext.
//
// Without it a driver is entitled to assume the subscript is dynamically uniform,
// and what the shader reads is then undefined - the values one invocation selects
// need not be the ones it gets. The compiler cannot check that condition: it does
// not know which device will run the shader, and every -fspv-target-env DXC
// accepts validates a module carrying the decoration (see docs/SPIR-V.rst,
// "Non-uniform push constant indexing").

struct PerMaterial {
  float4x4 worldViewProj;
  float4   tint;
};

struct PushData {
  float       scale;
  PerMaterial materials[8];
};

// A single push-constant block, as Vulkan allows: one variable in the
// PushConstant storage class per module (more with SPV_NV_push_constant_bank).
// Everything below is read out of it, and the array of per-material data is what
// the divergent subscript selects from.
[[vk::push_constant]] PushData g_push;

RWStructuredBuffer<float4> g_position : register(u0);
RWStructuredBuffer<float4> g_result : register(u1);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // tid.x differs between the invocations of a wave and of the workgroup, so this
  // is the classic per-invocation ("non-uniform") index - here it selects one of
  // eight material slots. It lowers to:
  //   %copy  = OpCopyObject %uint %masked                       ; decorated
  //   %chain = OpAccessChain %_ptr_PushConstant_mat4v4float %g_push
  //                            %int_1 %copy %int_0              ; decorated
  //   [%load = OpLoad ... %chain]                               ; decorated
  // The decoration on the chain is the part a driver acts on; the copy is only
  // there to carry the marking, and the loaded value and its consumers inherit it.
  float4 clipPos = mul(g_push.materials[NonUniformResourceIndex(tid.x & 7)].worldViewProj,
                       g_position[tid.x]);

  // The same block, read through a uniform path: a plain member and a constant
  // element of the same array. Nothing is decorated here, and this is what the
  // module looked like for every read before maintenance12 - the relaxation is per
  // access chain, not per variable.
  float4 tint = g_push.materials[0].tint * g_push.scale;

  g_result[tid.x] = clipPos * tint;
}
