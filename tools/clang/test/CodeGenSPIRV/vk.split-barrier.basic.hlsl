// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-extension=SPV_EXT_split_barrier %s | FileCheck %s

// SPV_EXT_split_barrier: the arrive/wait pair, its capability and its
// extension (G14/L0, G14/L1, G14/L2).
//
// OpControlBarrierArriveEXT (6142) and OpControlBarrierWaitEXT (6143) take
// exactly the operands OpControlBarrier (224) takes - (IdScope, IdScope,
// IdMemorySemantics) - and carry no token operand. The pairing therefore has no
// encoding-level witness: the only thing the module can show is that both
// halves name the same scope operands, which is what this test asserts by
// reusing the captured %id of the execution scope, the memory scope and the
// 32-bit integer type.
//
// Execution scope : Workgroup = 0x2 = 2
// Memory scope    : Workgroup = 0x2 = 2
// Semantics, arrive: WorkgroupMemory | Release = 0x100 | 0x4 = 260
// Semantics, wait  : WorkgroupMemory | Acquire = 0x100 | 0x2 = 258
//
// The two semantics values differ on purpose: VK_EXT_shader_split_barrier makes
// the arrive a Release and the wait an Acquire, and SPIRV-Tools rejects
// AcquireRelease (0x108 = 264, the classic barrier form) on either half. The
// scopes are the ones GroupMemoryBarrierWithGroupSync() uses, so a split
// barrier covers exactly the workgroup memory a classic workgroup barrier
// covers.

#include <vk/ext/split_barrier.h>

groupshared uint g_shared;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  g_shared = tid.x;
  vk::SplitBarrierArrive();
  uint value = g_shared;
  vk::SplitBarrierWait();
  g_shared = value + tid.y;
}

// The capability and the extension are emitted once, by the normal extension
// registration path (they disappear when -fspv-extension is dropped; see
// vk.split-barrier.extension.error.hlsl).
// CHECK:      OpCapability SplitBarrierEXT
// CHECK-NEXT: OpExtension "SPV_EXT_split_barrier"

// CHECK-DAG: [[UINT:%[0-9A-Za-z_]+]] = OpTypeInt 32 0
// CHECK-DAG: [[WORKGROUP:%[0-9A-Za-z_]+]] = OpConstant [[UINT]] 2
// CHECK-DAG: [[RELEASE:%[0-9A-Za-z_]+]] = OpConstant [[UINT]] 260
// CHECK-DAG: [[ACQUIRE:%[0-9A-Za-z_]+]] = OpConstant [[UINT]] 258

// Arrive: execution scope, memory scope, release semantics. The same
// [[WORKGROUP]] id is used for both scopes, and it is the id the classic
// barrier uses (see vk.split-barrier.scopes.hlsl).
// CHECK: OpControlBarrierArriveEXT [[WORKGROUP]] [[WORKGROUP]] [[RELEASE]]

// An arrive is not a memory barrier: a lowering that sneaks in a full barrier
// (or a classic control barrier) would silently change the performance story
// that motivates the extension.
// CHECK-NOT: OpMemoryBarrier
// CHECK-NOT: OpControlBarrier {{%[0-9A-Za-z_]+}}

// Wait: the identical scope operands, acquire semantics.
// CHECK: OpControlBarrierWaitEXT [[WORKGROUP]] [[WORKGROUP]] [[ACQUIRE]]
