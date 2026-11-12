// RUN: %dxc -T vs_6_0 -E main -fspv-extension=SPV_NV_push_constant_bank %s -spirv | FileCheck %s

// VK_NV_push_constant_bank after the shipped post-processing (F15, gate
// G15/L6). No -fcgl on purpose: this RUN line goes through HLSL legalization,
// spirv-opt and capability trimming (SpirvEmitter.cpp, "post-processing"), and
// then through spirv-val, so it is the only test that can catch two failure
// modes:
//
//   * the optimizer drops or rewrites the decorated variables (DCE / single
//     store elimination - the SPIR-V Tools passes that were taught about
//     SPV_NV_push_constant_bank only recently, see external/SPIRV-Tools/CHANGES
//     "Support for optimizing SPV_NV_push_constant_bank"), leaving a module that
//     no longer contains the bank the host was told about;
//   * capability trimming removes PushConstantBanksNV, which turns the
//     decorations into an invalid module (the capability is what enables the two
//     decorations, and it is what allows more than one PushConstant variable per
//     entry point for the validator).
//
// Trimming does run here: the pre-legalization module of this shader carries
// MinLod, StorageImageWriteWithoutFormat, StorageImageReadWithoutFormat and
// InterpolationFunction (see vk.push-constant-bank.two-banks.hlsl), and none of
// them survives below. PushConstantBanksNV does survive, together with both
// decorations and both variables.

struct A {
  float4 a;
};

struct B {
  float4 b;
};

// CHECK: OpCapability Shader
// CHECK: OpCapability PushConstantBanksNV
// CHECK-NOT: OpCapability PushConstantBanksNV
// CHECK: OpExtension "SPV_NV_push_constant_bank"
// CHECK-NOT: OpExtension "SPV_NV_push_constant_bank"
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

// CHECK: OpDecorate %type_PushConstant_A Block
// CHECK: OpDecorate %type_PushConstant_B Block
// CHECK: %pcsA = OpVariable %_ptr_PushConstant_type_PushConstant_A PushConstant
// CHECK: %pcsB = OpVariable %_ptr_PushConstant_type_PushConstant_B PushConstant

float4 main() : A {
  return pcsA.a + pcsB.b;
}
