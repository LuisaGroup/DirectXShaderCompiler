// RUN: %dxc -T vs_6_0 -E main -fcgl -fspv-extension=SPV_NV_push_constant_bank %s -spirv | FileCheck %s

// VK_NV_push_constant_bank off path (F15, gate G15/L5).
//
// -fspv-extension=SPV_NV_push_constant_bank is on the command line but the
// shader uses neither [[vk::push_constant_bank]] nor
// [[vk::push_constant_bank_offset]], so the module must be exactly what DXC
// emitted before the extension existed: no BankNV, no MemberOffsetNV, no
// PushConstantBanksNV capability and no OpExtension "SPV_NV_push_constant_bank".
// Requesting an extension must never change the encoding of a shader that does
// not use the corresponding annotations - in particular, an unused
// PushConstantBanksNV capability would tell the driver to expect banked push
// constants that no decoration describes.
//
// The byte-identity half of G15/L5 is checked out of band: the -Fc disassembly
// of vk.push-constant.hlsl, vk.push-constant.offset.hlsl,
// vk.push-constant.constantbuffer.hlsl, vk.push-constant.anon-struct.hlsl and
// vk.push-constant.static.hlsl was captured before the implementation and is
// bit-for-bit identical afterwards (see the F15 report). Those files are not
// modified, so their own RUN lines stay the primary gate.
//
// The CHECK-NOTs are anchored between two CHECKs so that the region they cover
// is the whole capability/extension block and the whole decoration block; a
// bare trailing CHECK-NOT would match nothing.

struct S {
  float4 a;
  float4 b;
};

// CHECK: OpCapability Shader
// CHECK-NOT: OpCapability PushConstantBanksNV
// CHECK-NOT: OpExtension "SPV_NV_push_constant_bank"
// CHECK: OpMemoryModel Logical GLSL450

[[vk::push_constant]]
S pcs;

// The whole decoration block: only the historical Location / Offset / Block
// decorations may appear, and the block keeps its ordinary single-variable
// PushConstant encoding.
// CHECK-NOT: BankNV
// CHECK-NOT: MemberOffsetNV
// CHECK: OpMemberDecorate %type_PushConstant_S 0 Offset 0
// CHECK: OpMemberDecorate %type_PushConstant_S 1 Offset 16
// CHECK: OpDecorate %type_PushConstant_S Block
// CHECK: %pcs = OpVariable %_ptr_PushConstant_type_PushConstant_S PushConstant

float4 main() : A {
  return pcs.a + pcs.b;
}
