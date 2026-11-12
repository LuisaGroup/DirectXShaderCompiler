// RUN: %dxc -T cs_6_0 -E main_const -fcgl -fspv-extension=SPV_KHR_abort %s -spirv | FileCheck %s --check-prefix=CONST
// RUN: %dxc -T cs_6_0 -E main_dyn -fcgl -fspv-extension=SPV_KHR_abort %s -spirv | FileCheck %s --check-prefix=DYN

// SPV_KHR_abort: the message operands (G6/L2.message).
//
// OpAbortKHR takes two IdRef operands, "Message Type" and "Message"
// (spirv.core.grammar.json; SPV_KHR_abort: "Message Type is the type of the data
// to be written [...] Message is data that is passed to the client API after
// termination. Message Type must logically match the type of Message."). The
// first operand is therefore a type id and the second one a value id, and a test
// that only asserts "OpAbortKHR" would also pass for a module that aborts with
// the wrong word or with the operands swapped (both are %-ids, so a swapped pair
// still reads like a valid instruction). These two runs tie the operands down:
//
// * The CONST run gives a compile-time message one OpConstant word, and the abort
//   names the id of *that* constant as operand 1 and the id of the 32-bit
//   unsigned integer type as operand 0. The value 0x00C0FFEE (12648430) is
//   asymmetric, so a byte-swapped, sign-extended or truncated encoding of the
//   message changes it.
// * The DYN run gives a message computed at runtime the id of the computing
//   instruction; the type operand stays the same %uint.
//
// The message is a value of a concrete type, not a pointer to a message block:
// SPIRV-Tools (val/validate_misc.cpp, ValidateAbort) rejects a message whose type
// does not logically match the Message Type operand, and
// val/validate_explicit_layout.cpp treats operand 0 as the type whose layout has
// to follow the scalar rules. A scalar has no layout to declare, which is why the
// HLSL surface is a single uint and why no OpConstantDataKHR appears here.

#include <vk/ext/abort.h>

RWStructuredBuffer<uint> buf;

[numthreads(1, 1, 1)]
void main_const() {
  vk::Abort(0x00C0FFEE);
}

[numthreads(1, 1, 1)]
void main_dyn(uint3 tid : SV_DispatchThreadID) {
  vk::Abort(buf[0] ^ tid.x);
}

// CONST:      OpCapability Shader
// CONST-NEXT: OpCapability AbortKHR
// CONST-NEXT: OpExtension "SPV_KHR_abort"
// CONST-NOT:  OpConstantDataKHR
// CONST-DAG:  [[UINT:%[0-9A-Za-z_]+]] = OpTypeInt 32 0
// CONST-DAG:  [[MSG:%[0-9A-Za-z_]+]] = OpConstant [[UINT]] 12648430
// CONST:      %bb_entry = OpLabel
// CONST:      OpAbortKHR [[UINT]] [[MSG]]
// CONST-NEXT: OpFunctionEnd

// DYN:      OpCapability Shader
// DYN-NEXT: OpCapability AbortKHR
// DYN-NEXT: OpExtension "SPV_KHR_abort"
// DYN-NOT:  OpConstantDataKHR
// DYN-DAG:  [[UINT:%[0-9A-Za-z_]+]] = OpTypeInt 32 0
// DYN:      %bb_entry = OpLabel
// DYN:      [[MSG:%[0-9A-Za-z_]+]] = OpBitwiseXor [[UINT]] {{%[0-9A-Za-z_]+}} {{%[0-9A-Za-z_]+}}
// DYN:      OpAbortKHR [[UINT]] [[MSG]]
// DYN-NEXT: OpFunctionEnd
