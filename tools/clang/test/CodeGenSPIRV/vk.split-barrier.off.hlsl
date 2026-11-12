// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv %s | FileCheck %s

// SPV_EXT_split_barrier off path (G14/L5).
//
// No -fspv-extension=SPV_EXT_split_barrier here: the feature must not appear in
// the module at all - no SplitBarrierEXT capability, no SPV_EXT_split_barrier
// extension, no split barrier instruction - and the classic barriers must keep
// their exact previous encoding: GroupMemoryBarrierWithGroupSync() is still
// OpControlBarrier with (Workgroup, Workgroup, WorkgroupMemory |
// AcquireRelease = 264).
//
// The pre-existing barrier tests (intrinsics.*memorybarrier*.hlsl) stay
// unmodified; this file is the anchored negative half of the same statement.
// The positive half (using the entry points without the flag is an error, not a
// silent fallback) is vk.split-barrier.extension.error.hlsl.

#include <vk/ext/split_barrier.h>

groupshared uint g_data[64];

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  g_data[tid.x] = tid.x;
  GroupMemoryBarrierWithGroupSync();
  g_data[tid.x] = g_data[63 - tid.x];
}

// Anchored negative: the capability and the extension would be in the header
// block between OpCapability Shader and OpMemoryModel.
// CHECK: OpCapability Shader
// CHECK-NOT: SplitBarrierEXT
// CHECK-NOT: SPV_EXT_split_barrier
// CHECK: OpMemoryModel Logical GLSL450

// The classic barrier is unchanged, and no split barrier is emitted anywhere in
// the function; the region ends at the OpReturn that follows it.
// CHECK: OpControlBarrier [[WG:%uint_2]] [[WG]] [[ACQREL:%uint_264]]
// CHECK-NOT: OpControlBarrierArriveEXT
// CHECK-NOT: OpControlBarrierWaitEXT
// CHECK-NOT: OpMemoryBarrier
// CHECK: OpReturn
