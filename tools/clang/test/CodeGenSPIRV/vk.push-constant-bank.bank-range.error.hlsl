// RUN: not %dxc -T vs_6_0 -E main -fcgl -fspv-extension=SPV_NV_push_constant_bank -spirv %s 2>&1 | FileCheck %s

// VK_NV_push_constant_bank value range (F15, gate G15/L4.range).
//
// Both decorations take a 32-bit *unsigned* literal: the registry text of
// SPV_NV_push_constant_bank says "The bank index must be a 32-bit unsigned
// integer literal" for BankNV and gives MemberOffsetNV an unsigned base byte
// offset. A negative argument therefore has no encoding - casting it to
// uint32_t would silently produce bank 4294967295, which no driver can bind.
// Sema already warns that the argument must be a uint literal
// (ValidateAttributeIntArg), and the emitter turns the unencodable value into an
// error instead of encoding garbage.
//
// The same check exists for [[vk::push_constant_bank_offset]] (same code path,
// see SpirvEmitter::validateVKAttributes); this file pins the bank spelling.
//
// One diagnostic per file on purpose: the SPIR-V backend stops at the first
// error, so a second failing declaration in the same file would never be
// diagnosed.
//
// The message spells the attribute out as [[vk::push_constant_bank]], so the
// CHECK line escapes the double brackets ({{...}} is FileCheck's regex syntax).

struct S {
  float4 a;
};

// CHECK: warning: attribute 'push_constant_bank' must have a uint literal argument
// CHECK: error: '{{\[\[}}vk::push_constant_bank{{\]\]}}' requires a non-negative bank index
[[vk::push_constant]]
[[vk::push_constant_bank(-1)]]
S pcs;

float4 main() : A {
  return pcs.a;
}
