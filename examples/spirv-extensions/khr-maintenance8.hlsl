// RUN: %dxc -T ps_6_0 -E main -spirv -fcgl %s

// VK_KHR_maintenance8: dynamic image offsets and signed remainder.
//
// VK_KHR_maintenance8 is a Vulkan *maintenance* extension: a collection of small
// corrections that a driver opts into as a whole through one feature bit,
//     VkPhysicalDeviceMaintenance8FeaturesKHR::maintenance8
// (query with vkGetPhysicalDeviceFeatures2, enable by chaining the structure into
// VkDeviceCreateInfo::pNext). Two of its items change what a SPIR-V shader module
// is allowed to mean, and those are the two this example is about:
//
//   1. "Support Offset (as an alternative to ConstOffset) image operand in
//      texture sampling and fetch operations." Before maintenance8 the Vulkan
//      SPIR-V environment permitted the image operand Offset only on the gather
//      operations, so a texture offset had to be a compile-time constant to be
//      expressible at all. maintenance8 extends Offset to the sampling, fetch and
//      read/write operations, which is what makes a *computed* offset usable.
//
//   2. "Use the SPIR-V definition of OpSRem and OpSMod, making these operations
//      produce well-defined results for negative operands." The Vulkan
//      environment used to say that if either operand of OpSRem/OpSMod is
//      negative the result is undefined. maintenance8 removes that caveat, so the
//      SPIR-V definition applies: for OpSRem the sign of a non-zero result comes
//      from the first operand.
//
// Both are rules of the Vulkan SPIR-V *environment*, not new module surface. The
// extension adds no instruction, no capability and - unlike most of the other
// extensions in this directory - no SPIR-V OpExtension string: there is no such
// thing as SPV_KHR_maintenance8 in the Khronos SPIR-V registry, and asking DXC for
// -fspv-extension=SPV_KHR_maintenance8 is an "unknown SPIR-V extension" error on
// purpose. There is also no new target environment to select: DXC's
// -fspv-target-env list stops at vulkan1.3, and the relaxation is available to a
// Vulkan 1.1/1.2/1.3 device that enables the extension, so it is a property of
// the device, not of the target env. Nothing in the module header changes, which
// is why this file has no flag to pass beyond -spirv.
//
// Why an HLSL shader does not have to change
// ------------------------------------------
// The HLSL source is the same either way, and so is the SPIR-V DXC emits: a
// non-constant offset already lowers to Offset (a constant offset is what lowers
// to ConstOffset), and HLSL "%" already lowers to OpSRem, never to OpSMod, because
// HLSL's % is C-style truncating remainder. The compiler has always generated the
// maintenance8-correct encoding; what maintenance8 changes is whether a *device*
// may accept it. The shader therefore needs no edit, no #define and no new
// intrinsic - the only decisions are on the host side.
//
// Required from the host
// ----------------------
//   * Vulkan 1.4, or Vulkan 1.1+ with VK_KHR_maintenance8 enabled at
//     vkCreateDevice (VK_KHR_MAINTENANCE_8_EXTENSION_NAME);
//   * feature bit VkPhysicalDeviceMaintenance8FeaturesKHR::maintenance8 = VK_TRUE.
// Without it, a module that carries Offset on a sampling instruction is rejected
// at pipeline creation, and the remainder results for negative operands are
// undefined. The compiler cannot check either condition - it does not know which
// device will run the shader - so it does not claim to.
//
// Note on the offsets below: HLSL does not require a texture offset to be a
// literal. Passing a value computed in the shader is what produces the Offset
// image operand and what needs maintenance8; the literal-offset call next to it
// produces ConstOffset and needs nothing.

SamplerState gSampler : register(s5);
Texture2D<float4> t : register(t1);
RWStructuredBuffer<float4> g_result : register(u0);
RWStructuredBuffer<int> g_remainder : register(u1);

// A computed offset: legal HLSL, and reachable in SPIR-V only from maintenance8
// onwards. Reading the offset from a buffer keeps it genuinely non-constant, so
// the compiler cannot fold it to a ConstOffset.
float4 sampleWithComputedOffset(float2 uv, int2 offsetFromData) {
  // Lowers to OpImageSampleImplicitLod ... Offset %offset.
  // The Offset image operand carries the Offset bit (0x0010), not ConstOffset
  // (0x0008), and the module gains the ImageGatherExtended capability that the
  // SPIR-V grammar requires for the operand.
  return t.Sample(gSampler, uv, offsetFromData);
}

// A literal offset: unchanged behaviour, useful for contrast. Lowers to
// OpImageSampleImplicitLod ... ConstOffset %constant and needs no feature at all.
float4 sampleWithConstantOffset(float2 uv) {
  return t.Sample(gSampler, uv, int2(1, 2));
}

// HLSL "%" on signed integers is truncating remainder: the sign of a non-zero
// result follows the dividend, which is exactly OpSRem. maintenance8 is what makes
// that result well defined for a negative operand on a Vulkan device; before it,
// the same instruction was only guaranteed for non-negative operands.
// Emits OpSRem (never OpSMod) for every line below.
int truncatingRemainder(int a, int b) {
  int r0 = a % b;
  int r1 = -a % b;          // negative dividend: result keeps a's sign
  int r2 = a % -b;          // negative divisor: result still keeps a's sign
  int r3 = a / b;           // "/" is a separate opcode, OpSDiv
  return r0 + r1 + r2 + r3;
}

float4 main(int2 uvOffset : A, int a : B, int b : C) : SV_Target {
  // One invocation of each remainder form, so a single compiled module exercises
  // the whole rule.
  g_remainder[0] = truncatingRemainder(a, b);

  // The computed offset path (needs maintenance8 on the device) ...
  g_result[0] = sampleWithComputedOffset(float2(0.25, 0.75), uvOffset);

  // ... and the literal offset path (needs nothing), side by side.
  return g_result[0] + sampleWithConstantOffset(float2(0.25, 0.75));
}
