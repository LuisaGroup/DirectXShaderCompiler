// RUN: %dxc -T cs_6_0 -E main -spirv -fspv-extension=SPV_QCOM_multiple_wait_queues %s | FileCheck %s

// VK_QCOM_shader_multiple_wait_queues after legalization and optimization
// (G29/L6).
//
// No -fcgl: this is the module that ships, after DXC's spirv-opt pass list and
// the capability-trimming pass have run. Two things can only break here, and only
// this RUN line catches them:
//   * the optimizer dropping or rewriting the loop that carries the hint, so the
//     MultipleWaitQueuesQCOM bit - and with it any evidence that the driver was
//     told - disappears;
//   * capability trimming removing MultipleWaitQueuesQCOM, because it is used by
//     a loop control bit rather than by an instruction.
// Both are asserted below, and the compile itself is the validity gate: dxc
// validates every module it emits, and this RUN line keeps validation enabled.
//
// Recorded behaviour (it is observable, so it is pinned here): DXC's shipped pass
// list does not unroll these loops, not even the [unroll] one with a constant trip
// count of 4 - the OpLoopMerge and its control mask are still there afterwards.
// That is consistent with the -fcgl test: the SPIR-V backend itself never unrolls,
// it only sets the Unroll bit, and the pass list that follows keeps the loop. A
// loop that *is* unrolled - by a driver's own spirv-opt invocation, or by a future
// unrolling pass - loses the OpLoopMerge it was annotated on, and with it the bit.
// The hint is then silently gone, which is why it is documented as a
// compilation-time hint on the loop, not as module-level state.
//
// Block names are not in this module (no -Zi), so the operands are matched by
// shape only.

RWStructuredBuffer<float> data;
RWStructuredBuffer<uint> counts;
RWStructuredBuffer<float> outv;

// The capability and the extension survive capability trimming.
// CHECK: OpCapability MultipleWaitQueuesQCOM
// CHECK: OpExtension "SPV_QCOM_multiple_wait_queues"
// CHECK-NOT: OpCapability MultipleWaitQueuesQCOM
// CHECK-NOT: OpExtension "SPV_QCOM_multiple_wait_queues"
// CHECK: OpMemoryModel Logical GLSL450

[numthreads(64, 1, 1)]
void main() {
  uint count = counts[0];
  float acc = 0.0;

  // A loop whose trip count comes from a buffer: the mask and its literal operand
  // (the wait queue count) are unchanged from the -fcgl module.
  // CHECK: OpLoopMerge {{%[0-9]+}} {{%[0-9]+}} MultipleWaitQueuesQCOM 2
  // CHECK-NEXT: OpBranchConditional {{%[0-9]+}} {{%[0-9]+}} {{%[0-9]+}}
  [[vk::multiple_wait_queues(2)]]
  for (uint i = 0; i < count; ++i) {
    acc = acc + data[i];
  }

  // The [unroll] case keeps both bits: see the recorded behaviour above.
  // CHECK: OpLoopMerge {{%[0-9]+}} {{%[0-9]+}} Unroll|MultipleWaitQueuesQCOM 0
  // CHECK-NEXT: OpBranchConditional {{%[0-9]+}} {{%[0-9]+}} {{%[0-9]+}}
  [[vk::multiple_wait_queues]] [unroll]
  for (int j = 0; j < 4; ++j) {
    acc = acc * data[j];
  }

  outv[1] = acc;

  // Nothing after the last annotated loop sets the bit again, and the last loop
  // merge in the module is the [unroll] one asserted above.
  // CHECK-NOT: MultipleWaitQueuesQCOM
  // CHECK: OpReturn
  // CHECK: OpFunctionEnd
}
