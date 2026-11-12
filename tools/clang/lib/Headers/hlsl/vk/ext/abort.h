// Copyright (c) 2026 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Shader abort: VK_KHR_shader_abort / SPV_KHR_abort.
//
// VK_KHR_shader_abort gives a shader a way to stop and report why:
//
//   vk::Abort(0x1000 + threadId); // report this invocation and cease
//
// The call lowers to a single instruction, OpAbortKHR (5121):
//
//   OpAbortKHR %uint %message
//
// and a module that contains one declares OpCapability AbortKHR (5120) and
// OpExtension "SPV_KHR_abort". The extension is opt-in: without
// -fspv-extension=SPV_KHR_abort every call is a compile error, because an abort
// is not a recovery point. SPIR-V describes the instruction as follows
// (SPV_KHR_abort, "OpAbortKHR"):
//
//   "Ceases all further processing in the invocation that executes it. Only
//    instructions executed before OpAbortKHR will have side effects. Other
//    invocations in the same Device scope instance will also be terminated in
//    finite time, though may reach completion.
//    Message Type is the type of the data to be written. Message Type must be a
//    concrete type. If the Shader capability is declared, Message Type must have
//    an explicit layout.
//    Message is data that is passed to the client API after termination. Message
//    Type must logically match the type of Message, as defined in OpCopyLogical.
//    This instruction must be the last instruction in a block."
//
// What this means for the HLSL author:
//
// - OpAbortKHR is a terminator, like OpReturn or OpKill, not a call that comes
//   back. The abort therefore ends the invocation: statements written after it
//   are placed in an unreachable block and are not emitted, so "instructions
//   before the abort are the only ones with side effects" holds by construction.
//   Side effects that must be visible to the host have to happen *before* the
//   call.
// - It is not a barrier and it does not synchronize anything. Other invocations
//   of the same device keep running until they are terminated "in finite time",
//   so a shader must not rely on an abort to publish data for other invocations.
// - The message type has to have an explicit layout in a Shader module. A scalar
//   has one implicitly, which is why the entry point below takes a plain uint:
//   the four message bytes are the value, in the host's byte order. Larger or
//   string-shaped messages (the GLSL front end packs a format string and its
//   varargs into a struct laid out with scalar rules) would need a layout
//   convention that HLSL does not define, so they are not expressible here.
// - The message is not a printf format. The host receives the raw bytes; with
//   VK_KHR_device_fault enabled as well it reads them back through
//   VkDeviceFaultShaderAbortMessageInfoKHR as a sequence of 8-byte-aligned
//   length/message pairs.
//
// What the host has to do is invisible to the compiler: the device must enable
// VkPhysicalDeviceShaderAbortFeaturesKHR::shaderAbort before a pipeline
// containing this instruction may be created, and the abort loses the device.
// vkGetDeviceFaultDebugInfoKHR (VK_KHR_device_fault) is how the message is
// collected afterwards. The compiler emits the capability and the extension; it
// cannot check that the feature bit was enabled, and no driver behaviour is
// covered by this compiler's tests.
//
// The entry point below is a compiler builtin: it has no definition anywhere,
// and SPIR-V CodeGen emits OpAbortKHR in place of the call
// (SpirvEmitter::processAbortKHR).
//
// Notes and limitations (see docs/SPIR-V.rst):
// - SPIR-V only. DXIL has no abort instruction, so on the DXIL path the call has
//   no definition and is rejected with "External function used in non-library
//   profile".
// - Available in every shader stage: SPV_KHR_abort attaches no execution-model
//   restriction to OpAbortKHR (SPIRV-Tools' CFG pass treats it as an ordinary
//   block terminator with no successors, next to OpKill and OpUnreachable).
// - Legal inside a helper function. A block that ends in OpAbortKHR simply has no
//   successor, so the containing function needs no return path from that block;
//   wrapping the call in an HLSL function aborts from that function's frame, and
//   because the abort never returns the caller is not resumed either.

#ifndef _HLSL_VK_EXT_ABORT_H_
#define _HLSL_VK_EXT_ABORT_H_

namespace vk {

// Report `message` to the client API and cease all further processing in this
// invocation. Lowers to OpAbortKHR %uint %message, which terminates the
// enclosing basic block.
void Abort(uint message);

} // namespace vk

#endif // _HLSL_VK_EXT_ABORT_H_
