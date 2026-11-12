// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-extension=SPV_KHR_abort %s -spirv | FileCheck %s

// SPV_KHR_abort: an abort inside a non-entry-point function (G6/P1).
//
// The plan left this open: is OpAbortKHR legal in a helper function, or only in
// an entry point? The primary sources answer yes, and the answer is what makes
// vk::Abort usable from HLSL at all (any call the emitter does not inline by
// hand ends up in a function of its own):
//
// * SPV_KHR_abort states exactly one structural rule for the instruction, "This
//   instruction must be the last instruction in a block." It attaches no
//   execution-model restriction and no entry-point restriction.
// * SPIRV-Tools implements exactly that: validate_misc.cpp registers no
//   RegisterExecutionModelLimitation for OpAbortKHR (compare OpKill, OpKill's
//   neighbours in validate_cfg.cpp do), and validate_cfg.cpp ends the *current
//   block* on it. A function whose block has no successor needs no return path,
//   which is the same shape OpKill and OpUnreachable already produce in helper
//   functions.
// * The capability is a module-level declaration, not a per-function one, so a
//   helper that aborts is covered by the same OpCapability AbortKHR.
//
// The test is the evidence rather than the quotation: with the shipped validator, a module with
// an abort in the helper below is validated by SPIRV-Tools before dxc exits, and
// the CHECK lines pin the abort inside the helper's own function instead of the
// entry point.
//
// Note that the abort costs the caller nothing to accept: since the helper never
// returns, the entry function's call site is followed by nothing.

#include <vk/ext/abort.h>

RWStructuredBuffer<uint> outBuf;

// A helper that reports and stops. Its block ends in OpAbortKHR, so it has no
// return path - legal, and the reason the encoder must not append an OpReturn.
void ReportAndStop(uint code) {
  vk::Abort(code);
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  outBuf[0] = tid.x;
  if (tid.x > 7) {
    ReportAndStop(tid.x + 1);
  }
}

// L1: the capability and the extension are declared once for the whole module.
// CHECK:      OpCapability Shader
// CHECK-NEXT: OpCapability AbortKHR
// CHECK-NEXT: OpExtension "SPV_KHR_abort"
// CHECK-NEXT: OpMemoryModel Logical GLSL450
// The helper is emitted as its own function, and its body block is exactly the
// load of the parameter followed by the abort.
// CHECK:      %ReportAndStop = OpFunction %void None {{%[0-9A-Za-z_]+}}
// CHECK:      [[PARAM:%[0-9A-Za-z_]+]] = OpFunctionParameter
// CHECK-NEXT: %bb_entry{{[0-9A-Za-z_]*}} = OpLabel
// CHECK-NEXT: [[CODE:%[0-9A-Za-z_]+]] = OpLoad %uint [[PARAM]]
// CHECK-NEXT: OpAbortKHR %uint [[CODE]]
// The abort is the last instruction of the helper's only block: no OpReturn, no
// OpUnreachable, nothing else.
// CHECK-NEXT: OpFunctionEnd
