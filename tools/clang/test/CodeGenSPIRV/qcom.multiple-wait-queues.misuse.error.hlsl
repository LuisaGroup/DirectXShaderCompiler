// RUN: not %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-extension=SPV_QCOM_multiple_wait_queues %s 2>&1 | FileCheck %s

// VK_QCOM_shader_multiple_wait_queues misuse diagnostics (G29/L4.misuse).
//
// [[vk::multiple_wait_queues]] is a loop annotation: it becomes one bit of that
// loop's OpLoopMerge Loop Control mask. Anything that is not a for, while or do
// statement has no OpLoopMerge to put the bit on, so the annotation would either
// be dropped silently or attach to nothing. Both are reported as errors rather
// than warnings (contrast with the HLSL [branch]/[flatten] family, which warns):
// a shader author who wrote the hint expects the driver to be told about it.
//
// Duplicates are errors as well. Two copies of the attribute on one statement
// would be OR-ed into the same mask bit and the second one would vanish without
// trace, which is exactly the silent loss the diagnostic exists to prevent.
//
// Note that a misplaced annotation is a frontend error, so no module is produced
// at all - there is nothing that could contain a partially annotated loop.
//
// The diagnostic spells the attribute out as [[vk::multiple_wait_queues]], so the
// CHECK lines escape the double brackets ({{...}} is FileCheck's regex syntax); a
// bare [[...]] would be parsed as a FileCheck pattern variable.

RWStructuredBuffer<int> data;

[numthreads(1, 1, 1)]
void main() {
  int limit = data[0];

  // CHECK: error: '{{\[\[}}vk::multiple_wait_queues{{\]\]}}' can only be applied to 'for', 'while' and 'do' loop statements
  [[vk::multiple_wait_queues]]
  if (limit > 0) {
    data[1] = 1;
  }

  // CHECK: error: '{{\[\[}}vk::multiple_wait_queues{{\]\]}}' can only be applied to 'for', 'while' and 'do' loop statements
  [[vk::multiple_wait_queues]]
  switch (limit) {
  default:
    data[2] = 2;
  }

  // CHECK: error: '{{\[\[}}vk::multiple_wait_queues{{\]\]}}' can only be applied to 'for', 'while' and 'do' loop statements
  [[vk::multiple_wait_queues]]
  {
    data[3] = 3;
  }

  // A correct annotation plus a duplicate of it on the same loop statement.
  // CHECK: error: '{{\[\[}}vk::multiple_wait_queues{{\]\]}}' cannot be applied more than once to the same statement
  [[vk::multiple_wait_queues]] [[vk::multiple_wait_queues]]
  for (int i = 0; i < 4; ++i) {
    data[4] = i;
  }
}
