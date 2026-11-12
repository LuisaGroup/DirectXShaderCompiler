// RUN: %dxc -T vs_6_0 -E main -fcgl -fspv-extension=SPV_NV_push_constant_bank %s -spirv | FileCheck %s

// VK_NV_push_constant_bank (F15, gates G15/L2.multi and G15/L3).
//
// Two push constant blocks in two different banks must coexist. This is the
// only non-mechanical part of the feature: DXC's historical rule
// (SpirvEmitter::validateVKAttributes) allows at most one push constant block
// in a module, and a module that declares more than one is rejected by
// spirv-val ("Entry-point has more than one variable with the PushConstant
// storage class in the interface") unless the module carries the
// PushConstantBanksNV capability. With the extension enabled and a bank per
// block, the rule becomes "at most one block per bank", and the capability that
// lifts the validation rule is emitted from the BankNV/MemberOffsetNV
// decorations themselves (CapabilityVisitor::visit(SpirvDecoration *)).
//
// Note that the second block also carries the base offset, so this file pins
// three decorations across two variables, in emission order: bank of the first
// block, then bank and offset of the second.
//
// The negative half - two blocks in the *same* bank - is
// vk.push-constant-bank.dup-bank.error.hlsl; the same-bank rule with the
// extension switched off is pinned unchanged by the pre-existing
// vk.push-constant.multiple.hlsl.

struct A {
  float4 a;
};

struct B {
  float4 b;
};

// CHECK: OpCapability PushConstantBanksNV
// CHECK: OpExtension "SPV_NV_push_constant_bank"
// CHECK: OpMemoryModel Logical GLSL450

// CHECK: OpDecorate %pcsA BankNV 0
// CHECK: OpDecorate %pcsB BankNV 1
// CHECK: OpDecorate %pcsB MemberOffsetNV 32
[[vk::push_constant]]
[[vk::push_constant_bank(0)]]
A pcsA;

[[vk::push_constant]]
[[vk::push_constant_bank(1)]]
[[vk::push_constant_bank_offset(32)]]
B pcsB;

// Both blocks are ordinary PushConstant variables of their own type, each with
// its own Block decoration.
// CHECK: OpDecorate %type_PushConstant_A Block
// CHECK: OpDecorate %type_PushConstant_B Block
// CHECK: %pcsA = OpVariable %_ptr_PushConstant_type_PushConstant_A PushConstant
// CHECK: %pcsB = OpVariable %_ptr_PushConstant_type_PushConstant_B PushConstant

float4 main() : A {
  return pcsA.a + pcsB.b;
}
