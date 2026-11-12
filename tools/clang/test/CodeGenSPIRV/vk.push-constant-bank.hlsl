// RUN: %dxc -T vs_6_0 -E main -fcgl -fspv-extension=SPV_NV_push_constant_bank %s -spirv | FileCheck %s

// VK_NV_push_constant_bank / SPV_NV_push_constant_bank (F15, gates G15/L0,
// G15/L1, G15/L2.bank and G15/L2.offset).
//
// The extension adds no instruction, only two decorations:
//
//   BankNV         5397  the push constant bank the block lives in
//   MemberOffsetNV 5358  a base byte offset added to every member offset of the
//                        block
//
// Despite its name MemberOffsetNV decorates the push constant *variable*, not a
// structure member: the registry text of SPV_NV_push_constant_bank says "Apply
// to a variable with PushConstant storage class to specify a base offset (in
// bytes) that is added to all member offsets within the block", and the SPIR-V
// example in the VK_NV_push_constant_bank proposal decorates the variable with
// both decorations ("OpDecorate %pc BankNV 0" / "OpDecorate %pc MemberOffsetNV
// 64"). Both are therefore plain OpDecorate on the OpVariable, so no
// OpMemberDecorateIdEXT / DescriptorHeapEXT path is needed.
//
// Both decorations require the PushConstantBanksNV capability, which requires
// Shader and SPV_NV_push_constant_bank. Emitting the capability without the
// extension, or the decoration without the capability, is a validation error,
// so a passing compile is the L3 gate: nothing here disables validation.
//
// The values asserted below come from the attribute arguments (bank 3, offset
// 64). A test that only matched the decoration names would still pass if the
// arguments were dropped.

struct S {
  float4 a;
  float4 b;
};

// CHECK: OpCapability Shader
// CHECK: OpCapability PushConstantBanksNV
// CHECK-NOT: OpCapability PushConstantBanksNV
// CHECK: OpExtension "SPV_NV_push_constant_bank"
// CHECK-NOT: OpExtension "SPV_NV_push_constant_bank"
// The literal path must not acquire the descriptor-heap capability or extension
// that the ID-valued decoration form (OpMemberDecorateIdEXT) would need.
// CHECK-NOT: OpCapability DescriptorHeapEXT
// CHECK-NOT: OpExtension "SPV_EXT_descriptor_heap"
// CHECK: OpMemoryModel Logical GLSL450

// Both decorations land on the variable, with the literal from each attribute.
// CHECK: OpDecorate %pcs BankNV 3
// CHECK: OpDecorate %pcs MemberOffsetNV 64
[[vk::push_constant]]
[[vk::push_constant_bank(3)]]
[[vk::push_constant_bank_offset(64)]]
S pcs;

// The block itself is unchanged: still a Block-decorated struct in the
// PushConstant storage class, with the ordinary member offsets.
// CHECK: OpMemberDecorate %type_PushConstant_S 0 Offset 0
// CHECK: OpMemberDecorate %type_PushConstant_S 1 Offset 16
// CHECK: OpDecorate %type_PushConstant_S Block
// CHECK: %pcs = OpVariable %_ptr_PushConstant_type_PushConstant_S PushConstant

float4 main() : A {
  return pcs.a + pcs.b;
}
