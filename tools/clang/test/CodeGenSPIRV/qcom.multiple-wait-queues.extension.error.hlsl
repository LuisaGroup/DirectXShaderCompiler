// RUN: not %dxc -T cs_6_0 -E main -fcgl -spirv %s 2>&1 | FileCheck %s

// VK_QCOM_shader_multiple_wait_queues is opt-in (G29/L4.extension).
//
// SPV_QCOM_multiple_wait_queues is registered as an extension that is not
// enabled by default (FeatureManager::enabledByDefault), so
// [[vk::multiple_wait_queues]] is rejected unless the RUN line passes
// -fspv-extension=SPV_QCOM_multiple_wait_queues. The default code generation of
// every existing shader is therefore unchanged: nothing can acquire the
// MultipleWaitQueuesQCOM capability by accident, and a driver without
// VK_QCOM_shader_multiple_wait_queues is never handed a module that declares it.
//
// The annotation is new syntax, so there is no shader in the wild that relies on
// the old behaviour, but silently dropping the hint (and emitting the loop as an
// ordinary OpLoopMerge ... None) would claim a hint the driver never receives.
// The error is emitted once per annotated loop, from
// SpirvEmitter::translateLoopAttributes, before any module is written; the
// loop control bit itself is not set in that case.
//
// The positive half is qcom.multiple-wait-queues.hlsl; the off path (no
// annotation, no flag, byte-identical loop control) is
// qcom.multiple-wait-queues.off.hlsl.
//
// The message spells the attribute out as [[vk::multiple_wait_queues]], so the
// CHECK lines escape the double brackets ({{...}} is FileCheck's regex syntax).

RWStructuredBuffer<int> data;

[numthreads(1, 1, 1)]
void main() {
  int limit = data[0];

  // CHECK: error: '{{\[\[}}vk::multiple_wait_queues{{\]\]}}' requires the SPV_QCOM_multiple_wait_queues extension; pass -fspv-extension=SPV_QCOM_multiple_wait_queues to enable it
  [[vk::multiple_wait_queues]]
  for (int i = 0; i < limit; ++i) {
    data[1] = i;
  }

  // The wait queue count does not change the diagnostic.
  // CHECK: error: '{{\[\[}}vk::multiple_wait_queues{{\]\]}}' requires the SPV_QCOM_multiple_wait_queues extension; pass -fspv-extension=SPV_QCOM_multiple_wait_queues to enable it
  [[vk::multiple_wait_queues(3)]]
  while (limit > 0) {
    limit = limit - 1;
  }
}
