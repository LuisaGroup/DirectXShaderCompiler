// RUN: %dxc -T cs_6_0 -E main -fspv-extension=SPV_KHR_abort %s -spirv | FileCheck %s

// SPV_KHR_abort through the optimizer (G6/L6).
//
// No -fcgl: SpirvEmitter runs legalization, the shipped spirv-opt pass list and
// capability trimming before validating, so this is the only run where an abort
// can be lost or rewritten. Two things can go wrong only here - a pass can drop
// an instruction it does not treat as a terminator, or it can move the abort into
// a shape that leaves the block without a terminator (inlining hoists a callee
// body into the caller, and the abort is the callee's last instruction) - so the
// assertions below are the same as the -fcgl ones, on the optimized module, plus
// the explicit "nothing follows the abort in its block" adjacency.
//
// The `if` makes the abort live in a conditional branch after inlining, which is
// where a mis-handled terminator shows up: the branch block must end in the abort
// and the merge block must still end in OpReturn.

#include <vk/ext/abort.h>

RWStructuredBuffer<uint> outBuf;

// The helper is inlined by the optimizer, which is the interesting case: the
// abort moves into the caller's branch.
void CheckAndStop(uint code) {
  vk::Abort(code);
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  outBuf[0] = tid.x;
  if (tid.x > 3) {
    CheckAndStop(tid.x | 0x00C0FFEE);
  }
  outBuf[1] = 4;
}

// L1 after optimization: the capability and the extension survive (capability
// trimming keeps what the instructions require) and are still declared once.
// CHECK:      OpCapability Shader
// CHECK-NEXT: OpCapability AbortKHR
// CHECK-NEXT: OpExtension "SPV_KHR_abort"
// CHECK-NEXT: OpMemoryModel Logical GLSL450
// The abort survives inlining as an instruction of the caller's function.
// CHECK:      OpFunction %void None
// CHECK-NOT:  OpFunctionCall
// CHECK:      OpAbortKHR {{%[0-9A-Za-z_]+}} {{%[0-9A-Za-z_]+}}
// The abort is the last instruction of its block: the next emitted line is the
// next block's label or the end of the function.
// CHECK-NEXT: OpLabel
// The merge block is untouched and still returns.
// CHECK:      OpReturn
// CHECK-NEXT: OpFunctionEnd
