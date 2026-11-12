// RUN: %dxc -T cs_6_0 -E main -spirv -fcgl -fspv-extension=SPV_NV_push_constant_bank %s

// Banked push constants with VK_NV_push_constant_bank (SPV_NV_push_constant_bank).
//
// [[vk::push_constant_bank(N)]] on a push constant block selects the hardware
// bank the block lives in, and [[vk::push_constant_bank_offset(N)]] adds a base
// byte offset to every member offset of the block:
//
//   OpCapability PushConstantBanksNV          (5423)
//   OpExtension "SPV_NV_push_constant_bank"
//   OpDecorate %pcs BankNV 1                  (5397)
//   OpDecorate %pcs MemberOffsetNV 64         (5358)
//
// Despite the name, MemberOffsetNV is not a member decoration. The registry text
// says "Apply to a variable with PushConstant storage class to specify a base
// offset (in bytes) that is added to all member offsets within the block", and
// both decorations are plain OpDecorate on the OpVariable. A block without
// BankNV is in bank 0; a block without MemberOffsetNV starts at offset 0 of its
// bank. Offsets are still subject to the ordinary push constant layout rules, so
// MemberOffsetNV must respect the alignment of the block's first member.
//
// Hardware reason: NVIDIA hardware has several banks of push constant / push
// data memory, and descriptor sets only expose one set of push data at a time.
// Spreading push constants over several banks lets a descriptor-heap application
// reach more root-descriptor data without a descriptor set per shader.
//
// What the compiler checks, and what it does not:
//   * checked: the attributes are only accepted on a [[vk::push_constant]]
//     global, only with -fspv-extension=SPV_NV_push_constant_bank, at most once
//     per declaration, with a non-negative bank/offset, and at most one push
//     constant block per bank. The module then always validates.
//   * not checked, and not checkable: how many banks the device has and how big
//     each bank is. Both are queried on the host at runtime (see below), so a
//     shader that asks for bank 3 is only wrong on a device with fewer banks.
//
// Required from the host:
//   * Vulkan device extension VK_NV_PUSH_CONSTANT_BANK (extension number 581,
//     revision 1; enable VK_NV_PUSH_CONSTANT_BANK_EXTENSION_NAME at
//     vkCreateDevice),
//   * the feature bit VkPhysicalDevicePushConstantBankFeaturesNV::
//     pushConstantBank, chained through VkDeviceCreateInfo::pNext,
//   * the limits VkPhysicalDevicePushConstantBankPropertiesNV::
//     maxGraphicsPushConstantBanks / maxComputePushConstantBanks (and the
//     ...PushDataBanks variants when push *data* is mapped through
//     VK_EXT_descriptor_heap). The bank argument of the attribute must be below
//     the limit that applies to this shader's stage. Ordinary push constant
//     sizes still come from VkPhysicalDeviceLimits::maxPushConstantsSize, which
//     bounds each bank.
//
// Runtime use: banks do not change how the data reaches the GPU, only where it
// lands. The traditional path keeps working unchanged for bank 0:
//
//   vkCmdPushConstants(cmd, layout, stageFlags, offset, size, pValues);
//
// Any other bank needs VkPushConstantsInfo (VK_KHR_maintenance6) with a
// VkPushConstantBankInfoNV chained to it, submitted with vkCmdPushConstants2:
//
//   VkPushConstantBankInfoNV bankInfo = {
//       VK_STRUCTURE_TYPE_PUSH_CONSTANT_BANK_INFO_NV, nullptr, /*bank*/ 1 };
//   VkPushConstantsInfo pushInfo = {
//       VK_STRUCTURE_TYPE_PUSH_CONSTANTS_INFO, &bankInfo, layout, stageFlags,
//       /*offset*/ 64, /*size*/ sizeof(PerFrame), pValues };
//   vkCmdPushConstants2(cmd, &pushInfo);
//
// The offset passed here is the byte offset inside the bank, i.e. it already
// includes the MemberOffsetNV base offset the shader was compiled with: the
// shader reads member i of bank b at MemberOffsetNV + Offset(i). Under a
// descriptor heap the same information is given to the driver by chaining
// VkPushConstantBankInfoNV to VkDescriptorSetAndBindingMappingEXT or
// VkPushDataInfoEXT instead, and the two must agree with the decoration in the
// SPIR-V module.
//
// The two blocks below deliberately use different banks: with only one block the
// extension would be pointless, and it is exactly the "two push constant blocks"
// case that plain SPIR-V (and therefore DXC without the extension) rejects.
// Note also that the bank number in the source is the only place the shader and
// the host can disagree, and the compiler cannot see the host side - keep the
// two in one place in the application.

struct PerFrame {
  float4x4 viewProj;
};

struct PerDraw {
  float4 tint;
  float4 params;
};

// Bank 0, at the start of the bank: the same placement an ordinary
// [[vk::push_constant]] block gets. BankNV 0 and MemberOffsetNV 0 are omitted
// here on purpose - they are the defaults, so the module stays as small as
// possible (see vk.push-constant-bank.off.hlsl, which pins that leaving the
// attributes out changes nothing).
// OpDecorate %perFrame Block is on the struct type; no BankNV/MemberOffsetNV.
[[vk::push_constant]]
PerFrame perFrame;

// Bank 1, 64 bytes into the bank: the members land at bytes 64 and 80 of bank 1.
//   OpDecorate %perDraw BankNV 1
//   OpDecorate %perDraw MemberOffsetNV 64
//   OpMemberDecorate %type_PushConstant_PerDraw 0 Offset 0
//   OpMemberDecorate %type_PushConstant_PerDraw 1 Offset 16
[[vk::push_constant]]
[[vk::push_constant_bank(1)]]
[[vk::push_constant_bank_offset(64)]]
PerDraw perDraw;

RWStructuredBuffer<float4> output;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  float4 position = mul(perFrame.viewProj, float4(tid.xy, 0.0, 1.0));
  // Reads of perDraw.tint compile to an access chain into bank 1 at byte 64 of
  // the bank; the extra base offset never appears in the instruction stream,
  // only in the MemberOffsetNV decoration above.
  output[tid.x] = position * perDraw.tint + perDraw.params;
}
