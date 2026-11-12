// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-extension=SPV_QCOM_multiple_wait_queues %s | FileCheck %s

// VK_QCOM_shader_multiple_wait_queues: interaction with [unroll] / [loop]
// (G29/L4.unroll).
//
// Decision: the annotation is kept and OR-ed into the loop's existing control
// mask. DXC's SPIR-V backend never removes a loop body: [unroll], [unroll(n)],
// [loop] and [fastopt] only select the OpLoopMerge Loop Control bit (Unroll /
// DontUnroll), and the actual unrolling, if any, is done later by spirv-opt's
// loop-unroll pass (or by the driver). Because the OpLoopMerge still exists when
// the annotation is encoded, the annotation cannot be silently lost here, so
// there is nothing to warn about and nothing to drop:
//   [[vk::multiple_wait_queues]] [unroll]  -> Unroll|MultipleWaitQueuesQCOM
//   [[vk::multiple_wait_queues]] [loop]    -> DontUnroll|MultipleWaitQueuesQCOM
//   [[vk::multiple_wait_queues(4)]] [unroll(8)] -> Unroll|MultipleWaitQueuesQCOM 4
// The last line also shows that the loop control's own literal operand
// (the wait queue count) and the [unroll] count are independent: [unroll(8)]
// only contributes the Unroll bit, so the emitted operands are
// "Unroll|MultipleWaitQueuesQCOM 4".
//
// The order of the two attribute lists matters and is fixed by the HLSL parser:
// C++11 attributes are parsed before the HLSL ones, so [[vk::...]] must come
// first. [unroll] [[vk::multiple_wait_queues]] is a parse error
// ("expected identifier").
//
// The frontend really does not unroll: each loop still has exactly one body
// block with one iteration of the body, guarded by an OpLoopMerge. If the
// backend had unrolled them, there would be no OpLoopMerge at all - which is
// what the .opt test checks for the same shape after spirv-opt.

RWStructuredBuffer<int> data;

// CHECK: OpCapability MultipleWaitQueuesQCOM
// CHECK: OpExtension "SPV_QCOM_multiple_wait_queues"

[numthreads(1, 1, 1)]
void main() {
  int limit = data[0];

  // [unroll] on a `for` loop with a constant trip count.
  // CHECK-LABEL: %for_check = OpLabel
  // CHECK: OpLoopMerge %for_merge %for_continue Unroll|MultipleWaitQueuesQCOM 0
  // CHECK-NEXT: OpBranchConditional {{%[0-9]+}} %for_body %for_merge
  // CHECK-LABEL: %for_body = OpLabel
  [[vk::multiple_wait_queues]] [unroll]
  for (int i = 0; i < 4; ++i) {
    data[1] = i;
  }

  // [loop] (DontUnroll) on a `while` loop.
  // CHECK-LABEL: %while_check = OpLabel
  // CHECK: OpLoopMerge %while_merge %while_continue DontUnroll|MultipleWaitQueuesQCOM 0
  // CHECK-NEXT: OpBranchConditional {{%[0-9]+}} %while_body %while_merge
  // CHECK-LABEL: %while_body = OpLabel
  [[vk::multiple_wait_queues]] [loop]
  while (limit > 0) {
    limit = limit - 1;
  }

  // [unroll(n)] on a `do`-`while` loop, with an explicit wait queue count.
  // CHECK-LABEL: %do_while_header = OpLabel
  // CHECK-NEXT: OpLoopMerge %do_while_merge %do_while_continue Unroll|MultipleWaitQueuesQCOM 4
  // CHECK-NEXT: OpBranch %do_while_body
  // CHECK-LABEL: %do_while_body = OpLabel
  [[vk::multiple_wait_queues(4)]] [unroll(8)]
  do {
    limit = limit + 1;
  } while (limit < 10);

  // CHECK: OpFunctionEnd
}
