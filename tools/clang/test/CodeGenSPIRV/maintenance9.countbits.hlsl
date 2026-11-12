// RUN: %dxc -T cs_6_2 -E main -enable-16bit-types -fcgl -fspv-enable-maintenance9 %s -spirv | FileCheck %s

// OpBitCount is covered by the same VK_KHR_maintenance9 relaxation as
// OpBitReverse (VUID-RuntimeSpirv-None-10824, "Expected 32-bit int type for
// Base operand"), so with -fspv-enable-maintenance9 the Base operand keeps its
// natural width instead of being widened to 32 bits (16-bit) or split into two
// 32-bit halves (64-bit). The result type is still a 32-bit uint, which
// OpBitCount allows independently of the Base width.
// Without the flag the same shader produces the sequences asserted in
// maintenance9.off.hlsl.

// CHECK-DAG: OpCapability Int16
// CHECK-DAG: OpCapability Int64
// CHECK-NOT: OpExtension "SPV_KHR_maintenance9"

[numthreads(1, 1, 1)]
void main() {
  uint    u32;
  uint4   v32;
  uint16_t u16;
  uint16_t4 v16;
  int16_t s16;
  uint64_t u64;
  uint64_t4 v64;

// 32-bit: unchanged, one OpBitCount on the loaded value.
// CHECK: [[u32:%[0-9]+]] = OpLoad %uint %u32
// CHECK-NEXT: {{%[0-9]+}} = OpBitCount %uint [[u32]]
  uint ru32 = countbits(u32);
// CHECK: [[v32:%[0-9]+]] = OpLoad %v4uint %v32
// CHECK-NEXT: {{%[0-9]+}} = OpBitCount %v4uint [[v32]]
  uint4 rv32 = countbits(v32);

// 16-bit: one OpBitCount %uint on a %ushort operand. The pre-maintenance9 form
// is OpUConvert %uint (widening) followed by OpBitCount %uint.
// CHECK: [[u16:%[0-9]+]] = OpLoad %ushort %u16
// CHECK-NEXT: {{%[0-9]+}} = OpBitCount %uint [[u16]]
  uint ru16 = countbits(u16);
// CHECK: [[v16:%[0-9]+]] = OpLoad %v4ushort %v16
// CHECK-NEXT: {{%[0-9]+}} = OpBitCount %v4uint [[v16]]
  uint4 rv16 = countbits(v16);
// CHECK: [[s16:%[0-9]+]] = OpLoad %short %s16
// CHECK-NEXT: {{%[0-9]+}} = OpBitCount %uint [[s16]]
  uint rs16 = countbits(s16);

// 64-bit: one OpBitCount %uint on a %ulong operand, instead of two 32-bit
// counts (low half, high half) combined with OpIAdd.
// CHECK: [[u64:%[0-9]+]] = OpLoad %ulong %u64
// CHECK-NEXT: {{%[0-9]+}} = OpBitCount %uint [[u64]]
  uint ru64 = countbits(u64);
// CHECK: [[v64:%[0-9]+]] = OpLoad %v4ulong %v64
// CHECK-NEXT: {{%[0-9]+}} = OpBitCount %v4uint [[v64]]
  uint4 rv64 = countbits(v64);

// CHECK-NOT: OpShiftRightLogical
// CHECK-NOT: OpIAdd
// CHECK: OpFunctionEnd
}
