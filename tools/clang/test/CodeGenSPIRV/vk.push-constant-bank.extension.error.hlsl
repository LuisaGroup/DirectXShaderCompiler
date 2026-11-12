// RUN: not %dxc -T vs_6_0 -E main -fcgl -spirv %s 2>&1 | FileCheck %s

// VK_NV_push_constant_bank is opt-in (F15, gate G15/L4.off).
//
// SPV_NV_push_constant_bank is registered as an extension that is not enabled
// by default (FeatureManager::enabledByDefault), so
// [[vk::push_constant_bank_offset]] (and [[vk::push_constant_bank]]) is
// rejected unless the command line passes
// -fspv-extension=SPV_NV_push_constant_bank. The default code generation of
// every existing shader is therefore unchanged: nothing can acquire the
// PushConstantBanksNV capability by accident, and a driver without
// VK_NV_push_constant_bank is never handed a module that declares it.
//
// The attribute is diagnosed rather than silently dropped. A dropped
// MemberOffsetNV decoration would put the block back at offset 0 of its bank
// while the shader author believes it lives at offset 64, which is a miscompile
// the compiler cannot recover from later: the host maps the shader's banked
// push constant memory from the very decorations that were dropped.
//
// The diagnostic names the flag to pass, because the attribute itself is
// perfectly well formed - only the command line is missing something.
//
// This file uses the offset spelling; vk.push-constant-bank.misuse.error.hlsl
// uses the bank spelling. One diagnostic per file on purpose: the SPIR-V
// backend stops at the first error, so a second failing declaration in the same
// file would never be diagnosed and its CHECK line could never match.
//
// The message spells the attribute out as [[vk::push_constant_bank_offset]], so
// the CHECK lines escape the double brackets ({{...}} is FileCheck's regex
// syntax); a bare [[...]] would be parsed as a FileCheck pattern variable.
//
// The positive half is vk.push-constant-bank.hlsl; the off path (extension
// passed, no attributes) is vk.push-constant-bank.off.hlsl.

struct S {
  float4 a;
};

// CHECK: error: '{{\[\[}}vk::push_constant_bank_offset{{\]\]}}' requires the SPV_NV_push_constant_bank extension; pass -fspv-extension=SPV_NV_push_constant_bank to enable it
[[vk::push_constant]]
[[vk::push_constant_bank_offset(64)]]
S pcs;

float4 main() : A {
  return pcs.a;
}
