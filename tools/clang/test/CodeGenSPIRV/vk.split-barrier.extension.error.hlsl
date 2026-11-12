// RUN: not %dxc -T cs_6_0 -E main -fcgl -spirv %s 2>&1 | FileCheck %s

// SPV_EXT_split_barrier is opt-in: the extension is not enabled by default
// (FeatureManager::enabledByDefault), so the entry points are rejected unless
// -fspv-extension=SPV_EXT_split_barrier is given (G14/L4).
//
// The diagnostic replaces the silent alternative: without it, a split barrier
// would either lower to a classic OpControlBarrier (dropping the whole point of
// the extension) or emit an instruction whose capability the driver was never
// asked to enable.
//
// The failure is a compile error, so no module is produced at all - there is
// nothing that could contain an OpControlBarrierArriveEXT without the extension.

#include <vk/ext/split_barrier.h>

groupshared uint g_shared;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  g_shared = tid.x;
  // CHECK: error: 'vk::SplitBarrierArrive' requires the SPV_EXT_split_barrier extension; pass -fspv-extension=SPV_EXT_split_barrier to enable it
  vk::SplitBarrierArrive();
  g_shared = g_shared + tid.y;
  // CHECK: error: 'vk::SplitBarrierWait' requires the SPV_EXT_split_barrier extension; pass -fspv-extension=SPV_EXT_split_barrier to enable it
  vk::SplitBarrierWait();
}
