// RUN: %dxc -T cs_6_2 -E main -enable-16bit-types -fcgl -fspv-enable-maintenance9 %s -spirv | FileCheck %s

// VK_KHR_maintenance9 removes the Vulkan rule (VUID-RuntimeSpirv-None-10824)
// that required the Base operand of OpBitReverse to be a 32-bit integer.
// With -fspv-enable-maintenance9 the instruction is therefore emitted at the
// operand's natural width: one instruction for 16-bit and for 64-bit operands,
// instead of the widening / low-high-splitting sequences that are still
// produced without the flag (see maintenance9.off.hlsl).
// The extension itself has no OpExtension and no OpCapability, so nothing in
// the capability block changes; only the instruction stream does.
// 8-bit operands are covered by maintenance9.bitwise.int8.hlsl instead, because
// the HLSL builtin cannot reach them: reversebits' Sema overload set is
// 16/32/64-bit only, so a uint8_t argument is promoted to int before the
// intrinsic and the operation happens on 32 bits either way.

// CHECK-DAG: OpCapability Int16
// CHECK-DAG: OpCapability Int64
// CHECK-NOT: OpExtension "SPV_KHR_maintenance9"

[numthreads(1, 1, 1)]
void main() {
  uint  a;
  uint4 b;
  uint16_t c;
  uint16_t4 d;
  uint64_t e;
  uint64_t4 f;

// CHECK: [[a:%[0-9]+]] = OpLoad %uint %a
// CHECK-NEXT: {{%[0-9]+}} = OpBitReverse %uint [[a]]
  uint  ar  = reversebits(a);
// CHECK: [[b:%[0-9]+]] = OpLoad %v4uint %b
// CHECK-NEXT: {{%[0-9]+}} = OpBitReverse %v4uint [[b]]
  uint4 br = reversebits(b);

// 16-bit: a single OpBitReverse %ushort. The emulation used to widen to uint,
// reverse, shift right by 16 and truncate; none of those may remain.
// CHECK: [[c:%[0-9]+]] = OpLoad %ushort %c
// CHECK-NEXT: {{%[0-9]+}} = OpBitReverse %ushort [[c]]
  uint16_t cr = reversebits(c);
// CHECK: [[d:%[0-9]+]] = OpLoad %v4ushort %d
// CHECK-NEXT: {{%[0-9]+}} = OpBitReverse %v4ushort [[d]]
  uint16_t4 dr = reversebits(d);

// 64-bit: a single OpBitReverse %ulong instead of two 32-bit reversals, two
// UConverts, a shift, a shift-left and an OpBitwiseOr.
// CHECK: [[e:%[0-9]+]] = OpLoad %ulong %e
// CHECK-NEXT: {{%[0-9]+}} = OpBitReverse %ulong [[e]]
  uint64_t er = reversebits(e);
// CHECK: [[f:%[0-9]+]] = OpLoad %v4ulong %f
// CHECK-NEXT: {{%[0-9]+}} = OpBitReverse %v4ulong [[f]]
  uint64_t4 fr = reversebits(f);

// Nothing left over from the pre-maintenance9 emulation anywhere in the
// function body: no 16-bit widening, no 64-bit half splitting.
// CHECK-NOT: OpShiftRightLogical
// CHECK-NOT: OpBitwiseOr
// CHECK: OpFunctionEnd
}
