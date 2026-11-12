// RUN: %dxc -T cs_6_0 -E main -spirv -fspv-extension=SPV_KHR_abort %s

// Reporting an unrecoverable condition from a shader with VK_KHR_shader_abort /
// SPV_KHR_abort.
//
// OpAbortKHR (5121) does two things at once: it stops the invocation that
// executes it and it hands a message to the client API. SPV_KHR_abort describes
// the contract as
//
//   "Ceases all further processing in the invocation that executes it. Only
//    instructions executed before OpAbortKHR will have side effects. Other
//    invocations in the same Device scope instance will also be terminated in
//    finite time, though may reach completion."
//
// A module that contains the instruction declares OpCapability AbortKHR (5120)
// and OpExtension "SPV_KHR_abort". The extension is off by default here: DXC
// emits both only with -fspv-extension=SPV_KHR_abort, and without that flag the
// call below is a compile error rather than a module the host never asked for.
//
// What the abort is not:
//
// * It is not a barrier and it does not synchronize. Other invocations keep
//   running until they are terminated "in finite time", so the only data the
//   application can trust is the data written before the abort.
// * It is not `discard`. `discard` demotes the invocation to a helper invocation
//   (or kills it) and lets the rest of the shader run; an abort ends the
//   invocation. A fragment shader that aborts contains neither OpKill nor
//   OpDemoteToHelperInvocation.
// * It is not a printf. Nothing is formatted: the operands are a message type and
//   a message value, and the bytes of that value are what the host receives.
//
// The message in this example is the single uint the entry point takes, which is
// what the two operands of the instruction are derived from:
//
//   %uint = OpTypeInt 32 0                    <- "Message Type" (operand 4)
//   %code = OpIAdd %uint ...                  <- "Message"      (operand 5)
//   OpAbortKHR %uint %code
//
// Encoding a package number and a failing lane index into it is enough for a
// host to tell which part of a dispatch tripped. A larger or string-shaped
// message would need a layout convention for the message type (SPV_KHR_abort's
// own example packs a format string and its arguments into a struct laid out
// with scalar rules and stores the string as an OpConstantDataKHR of bytes);
// HLSL has no equivalent surface, so this compiler emits the scalar form only
// and the module does not need the dependent ConstantDataKHR capability.
//
// What the host has to do is invisible to the compiler:
//
// * enable VkPhysicalDeviceShaderAbortFeaturesKHR::shaderAbort at device creation
//   (VK_KHR_shader_abort) before creating a pipeline that contains the abort;
// * expect the device to be lost. An abort is not recoverable: Vulkan asks the
//   implementation to trigger device loss within finite time;
// * collect the message afterwards. With VK_KHR_device_fault enabled as well,
//   chain VkDeviceFaultShaderAbortMessageInfoKHR into the pNext of
//   VkDeviceFaultDebugInfoKHR and read pMessageData as a sequence of
//   8-byte-aligned length/message pairs - several invocations may each report one.
//   VkPhysicalDeviceShaderAbortPropertiesKHR::maxShaderAbortMessageSize (at least
//   65536 bytes) bounds a single message.
//
// The abort terminates the block it is in, so the statements written after it are
// unreachable: the emitter places them in a block with no predecessor and does not
// emit them. Anything the host must see has to happen before the call.

#include <vk/ext/abort.h>

// A deliberately small input so the abort is easy to trigger.
RWStructuredBuffer<uint> gValues;
RWStructuredBuffer<uint> gResults;

static const uint kInvalidValue = 0xFFFFFFFFu;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  const uint index = tid.x;
  const uint value = gValues[index];

  // Invariant the rest of the shader relies on: a sentinel never reaches the
  // arithmetic below. Report the index that broke it and stop this invocation.
  if (value == kInvalidValue) {
    // The message: 0xAB000000 tags the abort, the low 16 bits carry the index.
    vk::Abort(0xAB000000u | (index & 0xFFFFu));
    // Unreachable. Nothing after vk::Abort() is emitted: an abort ends the
    // invocation, it does not fall through.
  }

  gResults[index] = value * 2;
}
