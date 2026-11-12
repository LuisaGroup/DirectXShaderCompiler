// RUN: not %dxc -T ps_6_0 -E main -fcgl -spirv -fspv-extension=SPV_EXT_split_barrier %s 2>&1 | FileCheck %s

// SPV_EXT_split_barrier is a compute-stage feature (G14/L4).
//
// SPV_EXT_split_barrier only defines the arrive/wait pair for the GLCompute (and
// Kernel) execution models, and SPIRV-Tools enforces it:
// "The SplitBarrierEXT capability must not be enabled in any stage other than
// GLCompute or Kernel." Catching it in the compiler gives that diagnostic at the
// call site instead of a validation failure at the end of code generation (or,
// worse, a module a driver rejects).

#include <vk/ext/split_barrier.h>

float4 main(float4 position : SV_Position) : SV_Target {
  // CHECK: error: 'vk::SplitBarrierArrive' is only available in compute shaders
  vk::SplitBarrierArrive();
  float4 result = position;
  // CHECK: error: 'vk::SplitBarrierWait' is only available in compute shaders
  vk::SplitBarrierWait();
  return result;
}
