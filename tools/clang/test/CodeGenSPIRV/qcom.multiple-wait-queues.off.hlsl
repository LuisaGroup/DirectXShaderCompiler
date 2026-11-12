// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv %s | FileCheck %s

// VK_QCOM_shader_multiple_wait_queues off path (G29/L4.off, G29/L5).
//
// No [[vk::multiple_wait_queues]] and no
// -fspv-extension=SPV_QCOM_multiple_wait_queues here: the feature must not appear
// in the module at all, and every ordinary loop must keep exactly the Loop
// Control it had before the annotation existed. The OpLoopMerge encoding is
// shared code, so this is the region that could regress:
//   for              -> None
//   [unroll] for     -> Unroll
//   [loop] while     -> DontUnroll
//   do-while         -> None
// The anchored CHECK-NOTs below are the negative half of the L1 gate: the
// capability and the extension would sit in the header between OpCapability
// Shader and OpMemoryModel.
//
// The stricter form of this gate is that the pre-existing loop tests
// (cf.for.*.hlsl, cf.while.*.hlsl, cf.do.*.hlsl and the debug-info tests that
// assert an OpLoopMerge) still pass unmodified; they do, and none of them was
// touched by this change.
//
// The positive half - using the annotation without the flag is an error, not a
// silent fallback - is qcom.multiple-wait-queues.extension.error.hlsl.

RWStructuredBuffer<int> data;

// CHECK: OpCapability Shader
// CHECK-NOT: OpCapability MultipleWaitQueuesQCOM
// CHECK-NOT: OpExtension "SPV_QCOM_multiple_wait_queues"
// CHECK: OpMemoryModel Logical GLSL450

[numthreads(1, 1, 1)]
void main() {
  int limit = data[0];

  // CHECK-LABEL: %for_check = OpLabel
  // CHECK: OpLoopMerge %for_merge %for_continue None
  // CHECK-NEXT: OpBranchConditional {{%[0-9]+}} %for_body %for_merge
  for (int i = 0; i < limit; ++i) {
    data[1] = i;
  }

  // CHECK-LABEL: %for_check_0 = OpLabel
  // CHECK: OpLoopMerge %for_merge_0 %for_continue_0 Unroll
  // CHECK-NEXT: OpBranchConditional {{%[0-9]+}} %for_body_0 %for_merge_0
  [unroll]
  for (int i = 0; i < 4; ++i) {
    data[2] = i;
  }

  // CHECK-LABEL: %while_check = OpLabel
  // CHECK: OpLoopMerge %while_merge %while_continue DontUnroll
  // CHECK-NEXT: OpBranchConditional {{%[0-9]+}} %while_body %while_merge
  [loop]
  while (limit > 0) {
    limit = limit - 1;
  }

  // CHECK-LABEL: %do_while_header = OpLabel
  // CHECK-NEXT: OpLoopMerge %do_while_merge %do_while_continue None
  // CHECK-NEXT: OpBranch %do_while_body
  do {
    limit = limit + 1;
  } while (limit < 10);

  // Nothing anywhere in the function sets the bit either; the region checked
  // ends at the OpReturn that closes main.
  // CHECK-NOT: MultipleWaitQueuesQCOM
  // CHECK: OpReturn
}
