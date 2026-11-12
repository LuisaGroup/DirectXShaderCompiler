// RUN: %dxc -T cs_6_2 -E main -enable-16bit-types -fcgl %s -spirv | FileCheck %s

// Off-path identity for -fspv-enable-maintenance9 (L5): without the flag the
// pre-maintenance9 emulation must be produced bit-for-bit as before, because
// the relaxation is only valid on devices that report the maintenance9 feature.
// Same HLSL as maintenance9.reversebits.hlsl / maintenance9.countbits.hlsl, so
// the two files are a direct before/after pair.
// The pre-existing intrinsics.reversebits.hlsl and intrinsics.countbits.hlsl
// stay untouched and are the second half of this gate.

// CHECK-DAG: OpCapability Int16
// CHECK-DAG: OpCapability Int64

RWStructuredBuffer<uint> buf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint16_t a16 = (uint16_t)tid.x;
  uint64_t a64 = tid.x;

// 16-bit reversebits: widen to 32 bits, reverse, shift right by 16, truncate.
// CHECK: [[a16:%[0-9]+]] = OpLoad %ushort %a16
// CHECK-NEXT: [[w:%[0-9]+]] = OpUConvert %uint [[a16]]
// CHECK-NEXT: [[rev:%[0-9]+]] = OpBitReverse %uint [[w]]
// CHECK-NEXT: [[shr:%[0-9]+]] = OpShiftRightLogical %uint [[rev]] %uint_16
// CHECK-NEXT: {{%[0-9]+}} = OpUConvert %ushort [[shr]]
  uint r16 = reversebits(a16);

// 16-bit countbits: widen to 32 bits before counting.
// CHECK: [[a16c:%[0-9]+]] = OpLoad %ushort %a16
// CHECK-NEXT: [[wc:%[0-9]+]] = OpUConvert %uint [[a16c]]
// CHECK-NEXT: {{%[0-9]+}} = OpBitCount %uint [[wc]]
  uint c16 = countbits(a16);

// 64-bit reversebits: reverse both 32-bit halves separately and recombine.
// CHECK: [[a64:%[0-9]+]] = OpLoad %ulong %a64
// CHECK-NEXT: [[lo:%[0-9]+]] = OpUConvert %uint [[a64]]
// CHECK-NEXT: [[hishift:%[0-9]+]] = OpShiftRightLogical %ulong [[a64]] %ulong_32
// CHECK-NEXT: [[hi:%[0-9]+]] = OpUConvert %uint [[hishift]]
// CHECK-NEXT: [[revlo:%[0-9]+]] = OpBitReverse %uint [[lo]]
// CHECK-NEXT: [[revhi:%[0-9]+]] = OpBitReverse %uint [[hi]]
// CHECK-NEXT: [[ulolo:%[0-9]+]] = OpUConvert %ulong [[revlo]]
// CHECK-NEXT: [[ulohi:%[0-9]+]] = OpUConvert %ulong [[revhi]]
// CHECK-NEXT: [[shl:%[0-9]+]] = OpShiftLeftLogical %ulong [[ulolo]] %ulong_32
// CHECK-NEXT: {{%[0-9]+}} = OpBitwiseOr %ulong [[shl]] [[ulohi]]
  uint64_t r64 = reversebits(a64);

// 64-bit countbits: count both 32-bit halves and add them.
// CHECK: [[a64c:%[0-9]+]] = OpLoad %ulong %a64
// CHECK-NEXT: [[clo:%[0-9]+]] = OpUConvert %uint [[a64c]]
// CHECK-NEXT: [[lc:%[0-9]+]] = OpBitCount %uint [[clo]]
// CHECK-NEXT: [[cshift:%[0-9]+]] = OpShiftRightLogical %ulong [[a64c]] %uint_32
// CHECK-NEXT: [[chi32:%[0-9]+]] = OpUConvert %uint [[cshift]]
// CHECK-NEXT: [[hc:%[0-9]+]] = OpBitCount %uint [[chi32]]
// CHECK-NEXT: {{%[0-9]+}} = OpIAdd %uint [[hc]] [[lc]]
  uint c64 = countbits(a64);

  buf[0] = r16 + c16 + (uint)r64 + c64;

// No narrow-width form anywhere in the tail of the function.
// CHECK-NOT: OpBitReverse %ushort
// CHECK-NOT: OpBitReverse %ulong
// CHECK-NOT: OpBitCount %uint %ushort
// CHECK-NOT: OpBitCount %uint %ulong
// CHECK: OpFunctionEnd
}
