// RUN: %dxc -T cs_6_2 -E main -enable-16bit-types -fspv-enable-maintenance9 %s -spirv | FileCheck %s

// L6 for the OpBitCount half of the relaxation: without -fcgl the module goes
// through legalization, spirv-opt and capability trimming, and the single
// narrow-operand OpBitCount must still be there.

// CHECK-DAG: OpCapability Int16
// CHECK-DAG: OpCapability Int64
// CHECK-NOT: OpExtension "SPV_KHR_maintenance9"

// CHECK: [[a16:%[0-9]+]] = OpUConvert %ushort
// CHECK: [[a64:%[0-9]+]] = OpUConvert %ulong
// CHECK: {{%[0-9]+}} = OpBitCount %uint [[a16]]
// CHECK: {{%[0-9]+}} = OpBitCount %uint [[a64]]

RWStructuredBuffer<uint> buf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint16_t a16 = (uint16_t)tid.x;
  uint64_t a64 = tid.x;
  buf[0] = countbits(a16) + countbits(a64);
}

// The 64-bit operand is no longer split in half, so no shift right by 32 and no
// OpIAdd of two half counts remain.
// CHECK-NOT: OpShiftRightLogical
// CHECK: OpFunctionEnd
