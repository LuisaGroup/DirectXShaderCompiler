// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-extension=SPV_KHR_abort %s -spirv | FileCheck %s

// SPV_KHR_abort: vk::Abort() lowers to the OpAbortKHR terminator (G6/L0,
// G6/L1, G6/L2, G6/L3).
//
// OpAbortKHR (5121) has no Result Type and no Result <id>. Its two IdRef
// operands are, in this order, the message *type* and the message *value*
// (SPV_KHR_abort: "| 3 | 5121 | Message Type | Message |"; SPIRV-Tools
// validate_misc.cpp ValidateAbort reads operand 0 as the message type id and
// operand 1 as the value, and rejects a value whose type does not logically
// match it), so both operands are captured here: the abort must name the 32-bit
// unsigned integer type and the constant that the source passed as its message.
//
// The instruction is a block terminator ("This instruction must be the last
// instruction in a block"), which is why the CHECK-NEXT below requires the very
// next line to be OpFunctionEnd: no OpReturn, no OpUnreachable and no second
// terminator may follow it.
//
// The message is a plain 32-bit unsigned scalar and not an OpConstantDataKHR:
// SPV_KHR_abort's "Message Type is the type of the data to be written. [...]
// Message is data that is passed to the client API after termination." makes the
// message a value of a concrete type, and SPIRV-Tools' own OpAbortKHR test
// (val_extension_spv_khr_abort_test.cpp, "Valid") uses an OpConstant %uint for
// it. The constant-data encoding is the *string* form (its example packs
// "test: %u" into an OpTypeArray of bytes decorated UTFEncodedKHR), which needs a
// layout convention HLSL does not have - see docs/SPIR-V.rst. The CHECK-NOTs
// below keep a future change from silently switching this test's message to that
// form without also declaring the dependent ConstantDataKHR capability and
// SPV_KHR_constant_data extension.

#include <vk/ext/abort.h>

RWStructuredBuffer<uint> outBuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  outBuf[0] = tid.x;
  // 0x00C0FFEE = 12648430. The value is asymmetric so a reversed or truncated
  // encoding of the message is visible.
  vk::Abort(0x00C0FFEE);
}

// L1: exactly the capability and the extension the instruction needs. DXC emits
// every capability consecutively and then every extension, and deduplicates both
// (SpirvModule::addCapability/addExtension), so a CHECK-NEXT chain from the
// last pre-existing capability through OpMemoryModel is a proof that AbortKHR
// and "SPV_KHR_abort" appear once each and that nothing else was added to the
// preamble.
// CHECK:      OpCapability Shader
// CHECK-NEXT: OpCapability AbortKHR
// CHECK-NEXT: OpExtension "SPV_KHR_abort"
// CHECK-NEXT: OpMemoryModel Logical GLSL450
// The message form used here must not pull in the constant-data dependency.
// CHECK-NOT:  OpCapability ConstantDataKHR
// CHECK-NOT:  OpExtension "SPV_KHR_constant_data"
// CHECK-NOT:  OpConstantDataKHR
// CHECK-DAG:  [[UINT:%[0-9A-Za-z_]+]] = OpTypeInt 32 0
// CHECK-DAG:  [[MSG:%[0-9A-Za-z_]+]] = OpConstant [[UINT]] 12648430
// L0/L2: the call reached the backend and became the instruction, at the end of
// the entry function's body block.
// CHECK:      %bb_entry = OpLabel
// Anti-false-green: an abort is not a discard. OpKill and
// OpDemoteToHelperInvocation are what `discard` lowers to, and neither may
// appear in a module that only aborts.
// CHECK-NOT:  OpKill
// CHECK-NOT:  OpDemoteToHelperInvocation
// CHECK:      OpAbortKHR [[UINT]] [[MSG]]
// L2.term: the abort terminates its block, so the function ends immediately.
// CHECK-NEXT: OpFunctionEnd
