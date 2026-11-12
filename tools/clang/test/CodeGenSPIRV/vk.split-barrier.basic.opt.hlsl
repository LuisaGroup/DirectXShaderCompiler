// RUN: %dxc -T cs_6_0 -E main -spirv -fspv-extension=SPV_EXT_split_barrier %s | FileCheck %s

// SPV_EXT_split_barrier after legalization and optimization (G14/L6).
//
// No -fcgl: the module below is what ships, after DXC's spirv-opt pass list and
// the capability-trimming pass have run. Two things can only break here -
// spirv-opt dropping/moving one half of the pair (or merging it back into a
// plain OpControlBarrier), and capability trimming removing SplitBarrierEXT
// because it does not see a user of it. Both are asserted below, and the
// compile itself is the validity gate: dxc validates every module it emits, and
// this RUN line keeps validation enabled.
//
// The optimizer must not reorder the halves around the work between them: the
// arrive has to stay before the independent computation and the wait after it.

#include <vk/ext/split_barrier.h>

groupshared uint g_produced[64];
groupshared uint g_consumed[64];

RWStructuredBuffer<uint> g_out : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint index = tid.x;

  g_produced[index] = index * index;
  vk::SplitBarrierArrive();

  uint independent = index + 7;
  independent *= 3;
  g_consumed[index] = independent;

  vk::SplitBarrierWait();

  uint sum = g_produced[index] + g_produced[63 - index];
  g_out[index] = sum;
}

// The capability and the extension survive capability trimming.
// CHECK: OpCapability SplitBarrierEXT
// CHECK: OpExtension "SPV_EXT_split_barrier"

// The arrive survives, with the same operands as in the -fcgl module:
// Workgroup execution scope, Workgroup memory scope,
// WorkgroupMemory | Release = 260.
// CHECK: OpControlBarrierArriveEXT [[WG:%uint_2]] [[WG]] [[RELEASE:%uint_260]]

// The independent work is still between the halves, and no plain barrier was
// introduced in its place.
// CHECK-NOT: OpControlBarrier {{%[0-9A-Za-z_]+}}
// CHECK: OpIAdd %uint {{%[0-9A-Za-z_]+}} %uint_7
// CHECK: OpIMul %uint {{%[0-9A-Za-z_]+}} %uint_3

// The wait survives, with the same scopes and WorkgroupMemory | Acquire = 258.
// CHECK: OpControlBarrierWaitEXT [[WG]] [[WG]] [[ACQUIRE:%uint_258]]

// The wait comes after the arrive and is not duplicated.
// CHECK-NOT: OpControlBarrierArriveEXT
// CHECK-NOT: OpControlBarrierWaitEXT
// CHECK: OpReturn
