// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-extension=SPV_EXT_split_barrier %s | FileCheck %s

// SPV_EXT_split_barrier: the split halves use the scopes a classic workgroup
// barrier uses (G14/L2.scopes).
//
// Both constructs live in the same shader, so the comparison is within one
// module. GroupMemoryBarrierWithGroupSync() is OpControlBarrier with
// (execution scope Workgroup = 2, memory scope Workgroup = 2,
//  WorkgroupMemory | AcquireRelease = 0x100 | 0x8 = 264); the split pair must
// reuse the very same execution- and memory-scope operands, so both barriers
// cover the same set of invocations and the same memory.
//
// Only the ordering differs: an arrive can never be a full barrier (SPIRV-Tools
// rejects AcquireRelease on either half of a split barrier), so the arrive is
// WorkgroupMemory | Release = 260 and the wait is WorkgroupMemory |
// Acquire = 258.

#include <vk/ext/split_barrier.h>

groupshared uint g_data[64];

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint index = tid.x;

  // Classic workgroup barrier: every invocation arrives and waits at once.
  g_data[index] = index;
  GroupMemoryBarrierWithGroupSync();
  uint other = g_data[63 - index];

  // Split barrier: the same workgroup scope, but the arrive and the wait are
  // separated by independent work.
  vk::SplitBarrierArrive();
  uint mine = g_data[index];
  vk::SplitBarrierWait();

  g_data[index] = other + mine;
}

// The workgroup scope constant: ScopeWorkgroup = 2. Capturing the disassembler's
// name for it means every barrier below must name literally this id.
// CHECK-DAG: [[WG:%uint_2]] = OpConstant {{%[0-9A-Za-z_]+}} 2

// Classic barrier: execution scope, memory scope, WorkgroupMemory |
// AcquireRelease.
// CHECK: OpControlBarrier [[WG]] [[WG]] {{%[0-9A-Za-z_]+}}

// Split pair: the same execution scope and the same memory scope ids, so the
// arrive/wait pair is the split form of the barrier above and not a barrier over
// some other scope.
// CHECK: OpControlBarrierArriveEXT [[WG]] [[WG]] {{%[0-9A-Za-z_]+}}
// CHECK: OpControlBarrierWaitEXT [[WG]] [[WG]] {{%[0-9A-Za-z_]+}}
