// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-extension=SPV_KHR_abort %s -spirv | FileCheck %s
// RUN: %dxc -T cs_6_0 -E main_branch -fcgl -fspv-extension=SPV_KHR_abort %s -spirv | FileCheck %s --check-prefix=BRANCH

// SPV_KHR_abort: OpAbortKHR terminates its basic block (G6/L2.term).
//
// "This instruction must be the last instruction in a block." (SPV_KHR_abort).
// SPIRV-Tools treats it as a block end with no successors
// (source/val/validate_cfg.cpp registers it next to OpKill, OpReturn and
// OpUnreachable; spvOpcodeIsAbort() lists it), so a module that appends anything
// to the block fails validation, and DXC validates every module it emits, so the
// compile fails. That is
// why every CHECK-NEXT here requires the line after the abort to be the start of
// another block or the end of the function.
//
// The two runs cover the two shapes the emitter has to get right:
//
// * main: the abort is the last statement of the body. The stores written after
//   it must not be emitted at all - the emitter opens a new basic block for
//   them, the block has no predecessor, and BlockReadableOrderVisitor only walks
//   blocks reachable from the entry block, so the statements are dropped. That is
//   the structural form of "Only instructions executed before OpAbortKHR will
//   have side effects": they cannot execute, so they must not appear.
// * main_branch: the abort sits inside an `if`. The then-block ends in the abort
//   and the code after the abort is dropped as well, while the merge block (still
//   reachable from the false edge) keeps its store and its OpReturn.
//
// The CHECK-NOTs are bounded by the CHECK lines around them, so they exclude the
// near-miss encodings inside the region that could contain them: an OpStore, an
// OpReturn or a second terminator after the abort.

#include <vk/ext/abort.h>

RWStructuredBuffer<uint> outBuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  outBuf[0] = tid.x;
  vk::Abort(1);
  // Unreachable: dropped, never emitted.
  outBuf[1] = 2;
  outBuf[2] = 3;
}

[numthreads(1, 1, 1)]
void main_branch(uint3 tid : SV_DispatchThreadID) {
  outBuf[0] = tid.x;
  if (tid.x > 2) {
    vk::Abort(4);
    // Unreachable: dropped, never emitted.
    outBuf[1] = 5;
  }
  outBuf[2] = 6;
}

// main: the store that precedes the abort is emitted, the abort ends the block,
// and the function ends right after it.
// CHECK:      %bb_entry = OpLabel
// CHECK:      OpStore {{%[0-9A-Za-z_]+}} {{%[0-9A-Za-z_]+}}
// CHECK-NOT:  OpStore
// CHECK-NOT:  OpReturn
// CHECK-NOT:  OpUnreachable
// CHECK:      OpAbortKHR [[UINT:%[0-9A-Za-z_]+]] [[MSG:%[0-9A-Za-z_]+]]
// CHECK-NEXT: OpFunctionEnd

// main_branch: inside the `if`, the abort is the whole then-block.
// BRANCH:        %bb_entry = OpLabel
// BRANCH:        OpBranchConditional {{%[0-9A-Za-z_]+}} [[TRUE:%[0-9A-Za-z_]+]] {{%[0-9A-Za-z_]+}}
// BRANCH:        [[TRUE]] = OpLabel
// BRANCH-NOT:    OpStore
// BRANCH:        OpAbortKHR {{%[0-9A-Za-z_]+}} {{%[0-9A-Za-z_]+}}
// The then-block is the whole block: the next thing emitted is the merge block's
// label, and the merge block is still terminated by its own OpReturn.
// BRANCH-NEXT:   OpLabel
// BRANCH:        OpStore
// BRANCH:        OpReturn
// BRANCH-NEXT:   OpFunctionEnd
