// RUN: not %dxc -T vs_6_0 -E main -fcgl -fspv-extension=SPV_NV_push_constant_bank -spirv %s 2>&1 | FileCheck %s

// VK_NV_push_constant_bank keeps push constant blocks unique per bank (F15,
// gate G15/L4.dup).
//
// The extension relaxes "at most one push constant block" to "at most one block
// per bank" (SpirvEmitter::validateVKAttributes), because the whole point is to
// put several blocks into different hardware banks. It does not allow two
// blocks in the same bank: they would both claim the same range of the bank's
// push constant memory, the host has no way to give them different offsets
// without a MemberOffsetNV per block, and spirv-val's push-constant interface
// rule is lifted by the capability rather than by any per-bank bookkeeping. So
// the same-bank case stays an error and the message names the bank.
//
// This gate exists before the relaxation in the implementation order, and it is
// the reason the relaxed rule cannot be "no rule at all".
//
// Note that a block without [[vk::push_constant_bank(N)]] is in bank 0
// (SPV_NV_push_constant_bank: "If not present, the bank is assumed to be 0"), so
// it is the implicit bank member of this comparison.
//
// The positive half is vk.push-constant-bank.two-banks.hlsl; the unchanged
// single-block rule with the extension off is vk.push-constant.multiple.hlsl.

struct A {
  float4 a;
};

struct B {
  float4 b;
};

[[vk::push_constant]]
[[vk::push_constant_bank(1)]]
A pcsA;

// CHECK: error: cannot have more than one push constant block in bank 1
// CHECK: note: push constant block previously defined here
[[vk::push_constant]]
[[vk::push_constant_bank(1)]]
B pcsB;

float4 main() : A {
  return pcsA.a + pcsB.b;
}
