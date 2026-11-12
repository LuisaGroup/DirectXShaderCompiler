// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-extension=SPV_QCOM_multiple_wait_queues %s | FileCheck %s

// VK_QCOM_shader_multiple_wait_queues / SPV_QCOM_multiple_wait_queues:
// [[vk::multiple_wait_queues]] on a loop, its capability and its extension
// (G29/L0, G29/L1, G29/L2, G29/L3).
//
// The whole mechanism is one bit of the OpLoopMerge Loop Control mask:
//   LoopControl MultipleWaitQueuesQCOM = 0x10000000
// provided by
//   OpCapability MultipleWaitQueuesQCOM            (4539)
//   OpExtension "SPV_QCOM_multiple_wait_queues"
//
// The bit is not the whole encoding: the grammar gives the MultipleWaitQueuesQCOM
// enumerant one LiteralInteger parameter ("up to how many wait queues the
// compiler may use, 0 meaning all of them"), so the encoded instruction is
//   OpLoopMerge <merge> <continue> MultipleWaitQueuesQCOM <maxWaitQueues>
// and SPIRV-Tools' binary parser rejects an OpLoopMerge that sets the bit without
// the literal operand ("End of input reached while decoding OpLoopMerge"). The
// numbers below therefore pin the literal as well:
//   [[vk::multiple_wait_queues]]    -> MultipleWaitQueuesQCOM 0  (all queues)
//   [[vk::multiple_wait_queues(2)]] -> MultipleWaitQueuesQCOM 2
//
// This is a hint, not a behavioural feature: nothing in the module can prove that
// a driver uses more than one wait queue, and these tests are encoding-only. See
// docs/SPIR-V.rst, "VK_QCOM_shader_multiple_wait_queues".
//
// Validation (L3): the RUN line keeps validation enabled - dxc validates every
// module it emits - and SPIRV-Tools checks the capability against the mask bit
// because the enumerant declares its capability in spirv.core.grammar.json.

RWStructuredBuffer<int> data;

// CHECK: OpCapability MultipleWaitQueuesQCOM
// The capability and the extension are declared exactly once, in the module
// header, whatever the number of annotated loops.
// CHECK-NOT: OpCapability MultipleWaitQueuesQCOM
// CHECK: OpExtension "SPV_QCOM_multiple_wait_queues"
// CHECK-NOT: OpExtension "SPV_QCOM_multiple_wait_queues"

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  int limit = data[0];

  // A `for` loop.
  // CHECK: OpBranch %for_check
  // CHECK-LABEL: %for_check = OpLabel
  // CHECK: OpLoopMerge %for_merge %for_continue MultipleWaitQueuesQCOM 0
  [[vk::multiple_wait_queues]]
  for (int i = 0; i < limit; ++i) {
    data[1] = i;
  }

  // A `while` loop.
  // CHECK: OpBranch %while_check
  // CHECK-LABEL: %while_check = OpLabel
  // CHECK: OpLoopMerge %while_merge %while_continue MultipleWaitQueuesQCOM 0
  [[vk::multiple_wait_queues]]
  while (limit > 0) {
    limit = limit - 1;
  }

  // A `do`-`while` loop. The OpLoopMerge is on the branch into the body, as for
  // any do-while loop.
  // CHECK: OpBranch %do_while_header
  // CHECK-LABEL: %do_while_header = OpLabel
  // CHECK: OpLoopMerge %do_while_merge %do_while_continue MultipleWaitQueuesQCOM 0
  [[vk::multiple_wait_queues]]
  do {
    limit = limit + 1;
  } while (limit < 10);

  // The optional argument is the literal operand of the loop control: "up to how
  // many wait queues the compiler may use".
  // CHECK-LABEL: %for_check_0 = OpLabel
  // CHECK: OpLoopMerge %for_merge_0 %for_continue_0 MultipleWaitQueuesQCOM 2
  [[vk::multiple_wait_queues(2)]]
  for (int i = 0; i < limit; ++i) {
    data[2] = i;
  }
}
