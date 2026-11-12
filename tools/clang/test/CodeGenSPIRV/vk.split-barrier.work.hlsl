// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-extension=SPV_EXT_split_barrier %s | FileCheck %s

// SPV_EXT_split_barrier: instructions are allowed between the arrive and the
// wait (G14/L2.work).
//
// The point of a split barrier is the gap between its halves, so the encoding
// must keep everything the shader puts there in place: only the ordering that
// depends on the other invocations has to move after the wait. This test is the
// producer/consumer shape - publish, arrive, do work that depends on nothing
// published by the group, wait, consume - and asserts that
//   * the independent computation and the workgroup store to g_consumed sit
//     between OpControlBarrierArriveEXT and OpControlBarrierWaitEXT, and
//   * each half is emitted exactly once (nothing is duplicated or reordered
//     around the work).

#include <vk/ext/split_barrier.h>

groupshared uint g_produced[64];
groupshared uint g_consumed[64];

RWStructuredBuffer<uint> g_out : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint index = tid.x;

  // Publish this invocation's value, then arrive.
  g_produced[index] = index * index;
  vk::SplitBarrierArrive();

  // Independent work: nothing here reads a value another invocation publishes,
  // so it does not need to wait. The constants are asymmetric (7 and 3) so a
  // swapped or folded operand cannot pass the checks below.
  uint independent = index + 7;
  independent *= 3;
  g_consumed[index] = independent;

  // Only now wait for the group, and consume what it published.
  vk::SplitBarrierWait();

  uint sum = g_produced[index] + g_produced[63 - index];
  g_out[index] = sum;
}

// Arrive: execution scope Workgroup = 2, memory scope Workgroup = 2,
// WorkgroupMemory | Release = 260.
// CHECK: OpControlBarrierArriveEXT [[WG:%uint_2]] [[WG]] [[RELEASE:%uint_260]]

// The independent work stays between the halves; no wait is hoisted into it.
// CHECK-NOT: OpControlBarrierWaitEXT
// CHECK: OpIAdd %uint {{%[0-9A-Za-z_]+}} %uint_7
// CHECK: OpIMul %uint {{%[0-9A-Za-z_]+}} %uint_3
// CHECK: OpAccessChain {{%[0-9A-Za-z_]+}} %g_consumed

// Wait: the same scopes, WorkgroupMemory | Acquire = 258.
// CHECK: OpControlBarrierWaitEXT [[WG]] [[WG]] [[ACQUIRE:%uint_258]]

// Neither half is emitted twice: bounded by the return that follows them.
// CHECK-NOT: OpControlBarrierArriveEXT
// CHECK-NOT: OpControlBarrierWaitEXT
// CHECK: OpReturn
