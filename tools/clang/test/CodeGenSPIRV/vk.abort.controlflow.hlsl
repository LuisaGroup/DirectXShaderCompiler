// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-extension=SPV_KHR_abort %s -spirv | FileCheck %s

// SPV_KHR_abort inside structured control flow (G6/L3, the CFG risk of the plan).
//
// OpAbortKHR ends its block with no successors
// (source/val/validate_cfg.cpp registers it next to OpKill, OpReturn and
// OpUnreachable, and spvOpcodeIsAbort() lists it). The failure mode this test
// guards against is a *dangling structured-control-flow edge*: the emitter opens a
// new block for the statements after the abort, that block is unreachable and is
// therefore dropped, and if the construct had already recorded it as a merge or
// continue target - or if the abort itself had been given a successor - the module
// would reference a label that is never emitted, or a branch target with no
// OpLabel. Either way SPIRV-Tools rejects the module and the compile fails, which
// is the L3 evidence here: no -Vd, so a passing compile is a validated module.
//
// The abort therefore appears in three places that all have continuation points:
//   * inside an `if` inside a `for` - the selection merge, the loop merge and the
//     loop continue target must all still be emitted and still be reachable from
//     the paths that do not abort;
//   * in a `switch` case - the case block ends in the abort, the other cases and
//     the default still branch to the switch merge.
//
// The CHECK lines pin both halves: every OpAbortKHR is followed immediately by a
// label of another block (it is the last instruction of its block, and the block
// has no branch), and the loop/switch merges still exist and still terminate the
// function with OpReturn.

#include <vk/ext/abort.h>

RWStructuredBuffer<uint> buf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint sum = 0;
  for (uint i = 0; i < 4; ++i) {
    if (buf[i] == 0xFFFFFFFFu) {
      vk::Abort(i);
    }
    sum += buf[i];
  }
  switch (tid.x) {
  case 1:
    vk::Abort(0x11);
    break;
  case 2:
    sum += 2;
    break;
  default:
    break;
  }
  buf[0] = sum;
}

// L1: unchanged by the control flow.
// CHECK:      OpCapability Shader
// CHECK-NEXT: OpCapability AbortKHR
// CHECK-NEXT: OpExtension "SPV_KHR_abort"
// CHECK-NEXT: OpMemoryModel Logical GLSL450
// The loop keeps its header, its merge and its continue target.
// CHECK:      OpLoopMerge [[FOR_MERGE:%[0-9A-Za-z_]+]] [[FOR_CONT:%[0-9A-Za-z_]+]] None
// CHECK-NEXT: OpBranchConditional {{%[0-9A-Za-z_]+}} {{%[0-9A-Za-z_]+}} [[FOR_MERGE]]
// The then-block of the inner `if` is exactly the abort, and the block after it is
// the next label - no branch is emitted from an aborted block.
// CHECK:      OpSelectionMerge [[IF_MERGE:%[0-9A-Za-z_]+]] None
// CHECK:      OpAbortKHR %uint {{%[0-9A-Za-z_]+}}
// CHECK-NEXT: [[IF_MERGE]] = OpLabel
// The code that does not abort still reaches the loop's continue target.
// CHECK:      OpBranch [[FOR_CONT]]
// CHECK-NEXT: [[FOR_CONT]] = OpLabel
// CHECK:      OpBranch
// The switch keeps every case, and the aborting case is a block of its own.
// CHECK:      OpSwitch {{%[0-9A-Za-z_]+}} {{%[0-9A-Za-z_]+}} 1 {{%[0-9A-Za-z_]+}} 2 {{%[0-9A-Za-z_]+}}
// CHECK:      OpAbortKHR %uint %uint_17
// CHECK-NEXT: OpLabel
// The function still ends with the switch merge's return.
// CHECK:      OpReturn
// CHECK-NEXT: OpFunctionEnd
