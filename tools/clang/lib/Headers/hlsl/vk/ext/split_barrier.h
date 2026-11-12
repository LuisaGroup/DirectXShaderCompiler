// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Split barriers: VK_EXT_shader_split_barrier / SPV_EXT_split_barrier.
//
// A control barrier synchronizes every invocation: each invocation waits until
// all of them have arrived. A *split* barrier makes the two halves explicit, so
// an invocation can announce that it has arrived, keep working on something that
// does not depend on the other invocations, and only then wait for the rest:
//
//     vk::SplitBarrierArrive();   // I am done with the data I publish
//     ...independent work...
//     vk::SplitBarrierWait();     // wait for the other invocations to arrive
//
// The arrive and the wait lower to OpControlBarrierArriveEXT and
// OpControlBarrierWaitEXT with the same execution and memory scopes that
// GroupMemoryBarrierWithGroupSync() uses: execution scope Workgroup, memory
// scope Workgroup, WorkgroupMemory memory class. The arrive carries the Release
// order and the wait carries the Acquire order, so workgroup memory written
// before the arrive is visible to every invocation after its wait.
//
// Notes and limitations (see docs/SPIR-V.rst):
//   - Nothing is ordered at the arrive itself. Reads and writes of workgroup
//     memory that another invocation publishes are only guaranteed after the
//     wait, and only for the memory class above.
//   - A wait must be executed by every invocation of the group exactly once and
//     must be *dominated* by the matching arrive. SPIRV-Tools cannot verify the
//     pairing - the instructions carry no token - and neither can this compiler,
//     so the pairing is the programmer's responsibility.
//   - Compute stages only (Vulkan allows the SplitBarrierEXT capability in
//     compute pipelines), and only when the extension is enabled with
//     -fspv-extension=SPV_EXT_split_barrier.
//
// The two entry points below are compiler builtins: they have no definition
// anywhere, and SPIR-V CodeGen emits the barrier instruction in place of the
// call (SpirvEmitter::processSplitBarrierEXT). They must be called directly from
// the function that should contain the barrier - wrapping them in an HLSL
// function puts the barrier in that function instead.

#ifndef _HLSL_VK_EXT_SPLIT_BARRIER_H_
#define _HLSL_VK_EXT_SPLIT_BARRIER_H_

namespace vk {

// Arrive at the workgroup split barrier. Lowers to OpControlBarrierArriveEXT
// (execution scope Workgroup, memory scope Workgroup,
// MemorySemantics WorkgroupMemory | Release).
void SplitBarrierArrive();

// Wait for the workgroup split barrier. Lowers to OpControlBarrierWaitEXT
// (execution scope Workgroup, memory scope Workgroup,
// MemorySemantics WorkgroupMemory | Acquire).
void SplitBarrierWait();

} // namespace vk

#endif // _HLSL_VK_EXT_SPLIT_BARRIER_H_
