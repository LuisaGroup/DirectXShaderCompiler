// RUN: %dxc -T cs_6_0 -E main -spirv -fcgl -fspv-extension=SPV_EXT_split_barrier %s

// Split barriers with SPV_EXT_split_barrier / VK_EXT_shader_split_barrier.
//
// GroupMemoryBarrierWithGroupSync() synchronizes every invocation at one point:
// no invocation continues until all of them have arrived. A split barrier makes
// the two halves separate, so an invocation can announce that it has arrived,
// do work that does not depend on the other invocations, and only then wait:
//
//     vk::SplitBarrierArrive();   // publish, then keep going
//     ...independent work...
//     vk::SplitBarrierWait();     // wait for the rest of the group
//
// The example below is the producer/consumer shape that motivates the
// extension: a compute group stages values in groupshared memory, and the
// amount of independent work each invocation still has to do (index math and a
// second groupshared array) is large enough that waiting immediately would idle
// most of the group.
//
// Ordering rules:
//   * The arrive is a Release and the wait is an Acquire on the Workgroup memory
//     scope, with the same execution scope (Workgroup) the classic barrier uses.
//     The emitted scopes and the memory class (WorkgroupMemory) are identical to
//     GroupMemoryBarrierWithGroupSync(), so both barriers cover the same memory.
//   * Nothing is ordered at the arrive. Anything another invocation publishes is
//     only guaranteed visible after the wait, so a read that depends on the group
//     must be placed after vk::SplitBarrierWait().
//   * The arrive is not a memory barrier on its own; the compiler emits exactly
//     one instruction per call and does not insert any barrier around it.
//
// Pairing: the instructions carry no token operand - OpControlBarrierArriveEXT
// and OpControlBarrierWaitEXT take the same (execution scope, memory scope,
// memory semantics) operands as OpControlBarrier. The compiler therefore cannot
// prove that every wait has a matching arrive, and does not try to: it is the
// shader author's responsibility to make every invocation of the group execute
// one arrive and one wait, with the wait dominated by the arrive and with the
// same scope. A wait that is not preceded by an arrive is undefined behaviour.
//
// Restrictions enforced by the compiler:
//   * compute stages only (VK_EXT_shader_split_barrier defines the pair for
//     compute pipelines; SPIRV-Tools rejects the SplitBarrierEXT capability in
//     any other stage);
//   * the extension is opt-in - without -fspv-extension=SPV_EXT_split_barrier
//     both entry points are compile errors instead of lowering to
//     GroupMemoryBarrierWithGroupSync().
//
// Required from the host:
//   * Vulkan device extension VK_EXT_shader_split_barrier (enable
//     VK_EXT_SHADER_SPLIT_BARRIER_EXTENSION_NAME at vkCreateDevice),
//   * feature bit VkPhysicalDeviceShaderSplitBarrierFeaturesEXT::shaderSplitBarrier
//     (query it via vkGetPhysicalDeviceFeatures2 and enable it by chaining a
//     VkPhysicalDeviceShaderSplitBarrierFeaturesEXT with shaderSplitBarrier set
//     to VK_TRUE into VkDeviceCreateInfo::pNext),
//   * VK_EXT_shader_split_barrier reserves shared memory for the barriers: query
//     VkPhysicalDeviceShaderSplitBarrierPropertiesEXT::splitBarrierReservedSharedMemory
//     and subtract it from maxComputeSharedMemorySize when sizing groupshared
//     arrays, or the pipeline can fail to create even though the shader fits.
//
// Without these the driver rejects a module that declares the SplitBarrierEXT
// capability, which is why DXC only emits it when the extension is enabled (see
// docs/SPIR-V.rst).

#include <vk/ext/split_barrier.h>

// Values published by the group; written before the arrive, read after the wait.
groupshared uint g_published[64];

// Scratch each invocation produces on its own; safe to write between the two
// halves because no other invocation reads it.
groupshared uint g_scratch[64];

RWStructuredBuffer<uint> g_result : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  const uint index = tid.x;

  // Publish this invocation's contribution to the group.
  g_published[index] = index * index + 1;

  // Arrive: the contributions above are released, but this invocation does not
  // wait for anybody. It lowers to OpControlBarrierArriveEXT (execution scope
  // Workgroup, memory scope Workgroup, WorkgroupMemory | Release).
  vk::SplitBarrierArrive();

  // Independent work: it touches only this invocation's own data, so it does not
  // need the rest of the group to have arrived. This gap is the entire point of
  // the extension - in place of a GroupMemoryBarrierWithGroupSync() the group
  // overlaps this work with the slowest invocation's path to the arrive.
  uint independent = index + 7;
  independent *= 3;
  independent ^= index << 1;
  g_scratch[index] = independent;

  // Wait: now the group is complete, and everything published before an arrive
  // is visible. It lowers to OpControlBarrierWaitEXT (execution scope Workgroup,
  // memory scope Workgroup, WorkgroupMemory | Acquire).
  vk::SplitBarrierWait();

  // Safe: these reads are after the wait, so they observe the values the whole
  // group published before its arrive. Reading them between the two halves would
  // be a data race.
  const uint neighbour = 63 - index;
  const uint sum = g_published[index] + g_published[neighbour];

  // The private scratch value is combined with the group result and written out.
  g_result[index] = sum + g_scratch[index];
}
