// RUN: not %dxc -T vs_6_0 -E main -fcgl -fspv-extension=SPV_NV_push_constant_bank -spirv %s 2>&1 | FileCheck %s

// VK_NV_push_constant_bank duplicate attribute (F15, gate G15/L4.dup-attribute).
//
// [[vk::push_constant_bank(N)]] carries the bank index as a literal, so two
// copies on one declaration are contradictory: there is exactly one BankNV
// decoration per variable and no rule that says which of the two arguments
// would win. Emitting both would produce two BankNV decorations on the same
// variable (an invalid module - the same decoration may not be applied twice),
// and emitting the first one would silently ignore what the author wrote. Clang
// in this tree does not diagnose duplicate attributes of the same kind, so the
// check is explicit (SpirvEmitter::validateVKAttributes).
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

// CHECK: error: '{{\[\[}}vk::push_constant_bank{{\]\]}}' cannot be applied more than once to the same declaration
[[vk::push_constant]]
[[vk::push_constant_bank(1)]] [[vk::push_constant_bank(2)]]
S pcs;

float4 main() : A {
  return pcs.a;
}
