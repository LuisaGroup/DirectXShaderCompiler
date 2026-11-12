// RUN: %dxc -T cs_6_2 -E main -enable-16bit-types -fspv-enable-maintenance9 %s -spirv | FileCheck %s

// L6: the narrow-width OpBitReverse must survive the shipped post-processing.
// Without -fcgl DXC runs legalization, spirv-opt and capability trimming before
// validation; a pass that re-introduces the widening sequence, or that drops the
// 16-bit instruction, would only be caught here.

// CHECK-DAG: OpCapability Int16
// CHECK-DAG: OpCapability Int64
// CHECK-NOT: OpExtension "SPV_KHR_maintenance9"

// The optimizer is free to schedule the two operand conversions before the two
// reversals, so the assertions are on operand identity rather than adjacency.
// CHECK: [[a16:%[0-9]+]] = OpUConvert %ushort
// CHECK: [[a64:%[0-9]+]] = OpUConvert %ulong
// CHECK: {{%[0-9]+}} = OpBitReverse %ushort [[a16]]
// CHECK: {{%[0-9]+}} = OpBitReverse %ulong [[a64]]

RWStructuredBuffer<uint> buf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint16_t a16 = (uint16_t)tid.x;
  uint64_t a64 = tid.x;
  buf[0] = reversebits(a16) + (uint)reversebits(a64);
}

// CHECK-NOT: OpShiftRightLogical
// CHECK: OpFunctionEnd
