// RUN: %dxc -T cs_6_2 -E main -spirv -fcgl -enable-16bit-types -fspv-enable-maintenance9 %s

// VK_KHR_maintenance9: bitwise instructions on narrow and 64-bit integer widths.
//
// ---------------------------------------------------------------------------
// What the extension relaxes
// ---------------------------------------------------------------------------
// VK_KHR_maintenance9 is a Vulkan *maintenance* extension: a collection of small
// corrections that a driver opts into as a whole through one feature bit,
// VkPhysicalDeviceMaintenance9FeaturesKHR::maintenance9 (query with
// vkGetPhysicalDeviceFeatures2, enable by chaining the structure into
// VkDeviceCreateInfo::pNext).
//
// One item changes what a SPIR-V shader module is allowed to contain. The
// Vulkan SPIR-V environment used to require the Base operand of exactly five
// instructions to be a 32-bit integer (VUID-RuntimeSpirv-None-10824, "Expected
// 32-bit int type for Base operand"):
//
//   OpBitReverse, OpBitCount,
//   OpBitFieldInsert, OpBitFieldSExtract, OpBitFieldUExtract
//
// maintenance9 removes that restriction, so those five accept any integer width:
// 8, 16, 32 or 64 bits. No other bitwise instruction is involved -
// OpBitwiseAnd/Or/Xor/Not and the shift instructions were never width-restricted.
//
// ---------------------------------------------------------------------------
// What DXC does with it
// ---------------------------------------------------------------------------
// The extension adds no instruction and no capability, and there is no such
// thing as SPV_KHR_maintenance9 in the Khronos SPIR-V registry: asking DXC for
// -fspv-extension=SPV_KHR_maintenance9 is an "unknown SPIR-V extension" error on
// purpose, and nothing in the module header changes. What changes is the
// *instruction stream*, because widths the rule rejected can now be used
// directly, so DXC cannot assume the feature - it would silently emit modules
// that older drivers reject. -fspv-enable-maintenance9 is the opt-in, and it is
// the right knob rather than -fspv-target-env because the relaxation depends on
// a device feature, not on a SPIR-V version (a Vulkan 1.1/1.2/1.3 device may
// enable it, and DXC's -fspv-target-env list stops at vulkan1.3 anyway).
//
// With the flag, this file produces one instruction per call:
//
//   reversebits(uint16_t)  ->  OpBitReverse %ushort
//   reversebits(uint64_t)  ->  OpBitReverse %ulong
//   countbits(uint16_t)    ->  OpBitCount %uint %ushort
//   countbits(uint64_t)    ->  OpBitCount %uint %ulong
//
// Without the flag the same expressions need emulation that is valid on every
// device, and that is what DXC still generates by default: reversing a 16-bit
// value becomes OpUConvert + OpBitReverse + OpShiftRightLogical + OpUConvert,
// reversing a 64-bit value becomes nine instructions that reverse both 32-bit
// halves and recombine them, and countbits widens (16-bit) or counts and adds
// the two halves (64-bit). Compile this file twice, with and without the flag,
// to see the difference; tools/clang/test/CodeGenSPIRV/maintenance9.off.hlsl
// pins the unflagged form.
//
// Two neighbouring cases are *not* covered by the extension:
//   * 8-bit widths are legal with maintenance9 and can be reached through inline
//     SPIR-V ([[vk::ext_instruction]]), but not through the HLSL reversebits /
//     countbits builtins: their Sema overload set covers 16/32/64-bit integers
//     only, so an int8_t/uint8_t argument is promoted to int before the
//     intrinsic and the operation happens on 32 bits.
//   * firstbitlow()/firstbithigh() keep their 32-bit restriction, which comes
//     from GLSL.std.450 (FindILsb/FindUMsb have no 16-bit form), not from the
//     Vulkan rule maintenance9 relaxes.
//
// ---------------------------------------------------------------------------
// Required from the host
// ---------------------------------------------------------------------------
//   * Vulkan 1.4, or Vulkan 1.1+ with VK_KHR_maintenance9 enabled at
//     vkCreateDevice (VK_KHR_MAINTENANCE_9_EXTENSION_NAME);
//   * feature bit VkPhysicalDeviceMaintenance9FeaturesKHR::maintenance9 = VK_TRUE.
//
// Without it, a pipeline whose shader contains one of the five instructions
// with a non-32-bit Base operand is rejected at pipeline creation. The compiler
// cannot check that - it does not know which device will run the shader - so it
// does not claim to. What it does guarantee is that the module it produces with
// the flag is validated under the relaxation it emitted for, and that the module
// it produces without the flag is validated under the old rule.

RWStructuredBuffer<uint> g_result : register(u0);

// 16-bit reversal: one OpBitReverse %ushort with the flag.
uint16_t reverse16(uint16_t v) { return reversebits(v); }

// 64-bit reversal: one OpBitReverse %ulong with the flag.
uint64_t reverse64(uint64_t v) { return reversebits(v); }

// Both counts keep their 32-bit result type while the operand keeps its width;
// OpBitCount is allowed to differ from its Base in result type and width.
uint count16(uint16_t v) { return countbits(v); }
uint count64(uint64_t v) { return countbits(v); }

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint index : SV_GroupIndex) {
  // Build the operands from the thread id so nothing folds to a constant.
  uint16_t v16 = (uint16_t)(tid.x ^ index);
  uint64_t v64 = (uint64_t)tid.x * 0x9E3779B97F4A7C15ull;

  uint16_t r16 = reverse16(v16);
  uint64_t r64 = reverse64(v64);

  g_result[0] = count16(v16) + count64(v64);
  g_result[1] = r16 + (uint)r64;
}
