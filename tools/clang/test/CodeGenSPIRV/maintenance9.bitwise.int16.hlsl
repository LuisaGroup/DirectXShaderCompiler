// RUN: %dxc -T cs_6_2 -E main -enable-16bit-types -fcgl %s -spirv | FileCheck %s --check-prefix=OFF
// RUN: %dxc -T cs_6_2 -E main -enable-16bit-types -fcgl -fspv-enable-maintenance9 %s -spirv | FileCheck %s --check-prefix=ON

// Audit gate for the bitwise instructions that VK_KHR_maintenance9 does *not*
// touch. The Vulkan 32-bit Base operand rule (VUID-RuntimeSpirv-None-10824)
// only ever covered OpBitReverse, OpBitCount, OpBitFieldInsert,
// OpBitFieldSExtract and OpBitFieldUExtract: OpBitwiseAnd/Or/Xor/Not and the
// three shift instructions have no width rule at all beyond "operands match the
// result", and DXC has always emitted them at the operand's natural width. This
// file pins that, and pins that -fspv-enable-maintenance9 changes nothing here:
// the two RUN lines must produce the same instruction stream.
// The second operand of each shift is masked to 4 bits because HLSL defines
// shifting by more than the width as 0; that masking is unrelated to
// maintenance9 and only makes the emitted sequence deterministic.

// OFF-DAG: OpCapability Int16
// ON-DAG: OpCapability Int16

RWStructuredBuffer<uint> buf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  int16_t a = (int16_t)tid.x;
  int16_t b = (int16_t)tid.y;

// OFF: [[sa:%[0-9]+]] = OpLoad %short %a
// OFF: [[sb:%[0-9]+]] = OpLoad %short %b
// OFF-NEXT: {{%[0-9]+}} = OpBitwiseAnd %short [[sa]] [[sb]]
// ON: [[sa:%[0-9]+]] = OpLoad %short %a
// ON: [[sb:%[0-9]+]] = OpLoad %short %b
// ON-NEXT: {{%[0-9]+}} = OpBitwiseAnd %short [[sa]] [[sb]]
  int16_t r = (a & b) | (a ^ b) | ~a;

// OFF: {{%[0-9]+}} = OpBitwiseXor %short
// OFF: {{%[0-9]+}} = OpBitwiseOr %short
// OFF: {{%[0-9]+}} = OpNot %short
// ON: {{%[0-9]+}} = OpBitwiseXor %short
// ON: {{%[0-9]+}} = OpBitwiseOr %short
// ON: {{%[0-9]+}} = OpNot %short

// OFF: [[lr:%[0-9]+]] = OpLoad %short %r
// OFF: {{%[0-9]+}} = OpShiftLeftLogical %short [[lr]]
// OFF: [[rr:%[0-9]+]] = OpLoad %short %r
// OFF: {{%[0-9]+}} = OpShiftRightArithmetic %short [[rr]]
// ON: [[lr:%[0-9]+]] = OpLoad %short %r
// ON: {{%[0-9]+}} = OpShiftLeftLogical %short [[lr]]
// ON: [[rr:%[0-9]+]] = OpLoad %short %r
// ON: {{%[0-9]+}} = OpShiftRightArithmetic %short [[rr]]
  r = r << 1;
  r = r >> 1;

  uint16_t u = (uint16_t)a;
  uint16_t w = (uint16_t)b;
  uint16_t q = (u & w) | (u ^ w) | ~u;

// OFF: {{%[0-9]+}} = OpBitwiseAnd %ushort
// OFF: {{%[0-9]+}} = OpBitwiseXor %ushort
// OFF: {{%[0-9]+}} = OpBitwiseOr %ushort
// OFF: {{%[0-9]+}} = OpNot %ushort
// ON: {{%[0-9]+}} = OpBitwiseAnd %ushort
// ON: {{%[0-9]+}} = OpBitwiseXor %ushort
// ON: {{%[0-9]+}} = OpBitwiseOr %ushort
// ON: {{%[0-9]+}} = OpNot %ushort

// OFF: [[lq:%[0-9]+]] = OpLoad %ushort %q
// OFF: {{%[0-9]+}} = OpShiftLeftLogical %ushort [[lq]]
// OFF: [[rq:%[0-9]+]] = OpLoad %ushort %q
// OFF: {{%[0-9]+}} = OpShiftRightLogical %ushort [[rq]]
// ON: [[lq:%[0-9]+]] = OpLoad %ushort %q
// ON: {{%[0-9]+}} = OpShiftLeftLogical %ushort [[lq]]
// ON: [[rq:%[0-9]+]] = OpLoad %ushort %q
// ON: {{%[0-9]+}} = OpShiftRightLogical %ushort [[rq]]
  q = q << 1;
  q = q >> 1;

  buf[0] = r + q;

// Every assertion above names the operand's own 16-bit type as the result type,
// which is what rules out a 32-bit widening step; the two prefixes must agree.
// OFF: OpFunctionEnd
// ON: OpFunctionEnd
}
