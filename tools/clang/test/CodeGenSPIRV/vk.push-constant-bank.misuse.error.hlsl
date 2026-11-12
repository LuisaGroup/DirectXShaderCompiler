// RUN: not %dxc -T vs_6_0 -E main -fcgl -fspv-extension=SPV_NV_push_constant_bank -spirv %s 2>&1 | FileCheck %s

// VK_NV_push_constant_bank misuse diagnostics (F15, gate G15/L4.misuse).
//
// BankNV and MemberOffsetNV decorate a *variable in the PushConstant storage
// class*. Without [[vk::push_constant]] there is no such variable, so the
// annotation has no target: DXC would emit an OpDecorate on an ordinary global
// (an invalid module) or drop it silently (a shader that claims a bank the
// driver never sees). Both are unacceptable, so the attribute combination is an
// error, not a warning.
//
// This check is separate from the frontend subject check
// ("'push_constant_bank' attribute only applies to global variables of struct
// type"): that one rejects a non-struct or non-global declaration, while this
// one rejects a well-formed struct global that simply is not a push constant
// block. The extension flag is passed here so that the only diagnostic in this
// file is the missing [[vk::push_constant]].
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

// CHECK: error: '{{\[\[}}vk::push_constant_bank{{\]\]}}' can only be used together with '{{\[\[}}vk::push_constant{{\]\]}}'
[[vk::push_constant_bank(1)]]
S notPushConstant;

float4 main() : A {
  return notPushConstant.a;
}
