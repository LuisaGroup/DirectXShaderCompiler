// RUN: %dxc -T cs_6_0 -E main -spirv -fcgl -fspv-extension=SPV_QCOM_multiple_wait_queues %s

// Multiple wait queues with VK_QCOM_shader_multiple_wait_queues
// (SPV_QCOM_multiple_wait_queues).
//
// [[vk::multiple_wait_queues]] on a for, while or do loop marks that loop as one
// the implementation may optimise by keeping several memory fills in flight at
// once, instead of unrolling it. The encoding is a single bit of the loop's loop
// control:
//
//   OpLoopMerge <merge> <continue> MultipleWaitQueuesQCOM <maxWaitQueues>
//   OpCapability MultipleWaitQueuesQCOM                            (4539)
//   OpExtension "SPV_QCOM_multiple_wait_queues"
//
// <maxWaitQueues> is the optional attribute argument: "up to how many wait
// queues the compiler may use", where 0 - the default of the bare
// [[vk::multiple_wait_queues]] spelling - means "all of them". The bit is OR-ed
// into whatever loop control the loop already needs, so
// [[vk::multiple_wait_queues]] [unroll] encodes Unroll|MultipleWaitQueuesQCOM.
//
// This is an encoding-level hint and nothing more: the module records what the
// shader asked for, and the effect is decided by the driver. Concretely,
//   * a driver may ignore the bit entirely, so a shader must not depend on it for
//     correctness - results are identical either way;
//   * it does not imply any memory ordering or synchronisation. Anything an
//     invocation publishes still needs the appropriate barrier;
//   * no test can prove that more than one wait queue is actually used; the
//     compiler can only be tested for emitting the encoding, which is what
//     tools/clang/test/CodeGenSPIRV/qcom.multiple-wait-queues*.hlsl do.
// Whether multiple wait queues help, and how many to ask for, is a tuning
// decision the application has to measure on the target; sweep the argument the
// same way you would sweep an unroll factor.
//
// Required from the host:
//   * Vulkan device extension VK_QCOM_shader_multiple_wait_queues (enable
//     VK_QCOM_SHADER_MULTIPLE_WAIT_QUEUES_EXTENSION_NAME at vkCreateDevice),
//   * feature bit VkPhysicalDeviceShaderMultipleWaitQueuesFeaturesQCOM::
//     shaderMultipleWaitQueues (enable it through VkDeviceCreateInfo::pNext),
//   * and the limit VkPhysicalDeviceShaderMultipleWaitQueuesPropertiesQCOM::
//     maxShaderWaitQueues, which bounds the argument: asking for more queues than
//     the device reports is at best ignored.
// A driver without the extension rejects a module that declares the capability,
// which is why DXC only emits it when -fspv-extension=SPV_QCOM_multiple_wait_queues
// is given (see docs/SPIR-V.rst).
//
// The shape that motivates the extension is a loop of cooperative-matrix
// multiply-adds: unrolling it to hide memory latency multiplies the live register
// count, while a deeper wait-queue pipeline does not.

RWStructuredBuffer<float4> A;
RWStructuredBuffer<float4> B;
RWStructuredBuffer<float4> Result;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  float4 acc = float4(0.0, 0.0, 0.0, 0.0);

  // OpLoopMerge %for_merge %for_continue MultipleWaitQueuesQCOM 0
  // The compiler may use as many wait queues as the device offers.
  [[vk::multiple_wait_queues]]
  for (uint i = 0; i < 8; ++i) {
    acc += A[tid.x + i] * B[tid.x + i];
  }

  // OpLoopMerge %while_merge %while_continue MultipleWaitQueuesQCOM 2
  // The same loop as a while statement, limited to two wait queues. The number is
  // a cap, not a request: an implementation with one queue still accepts it.
  uint remaining = 8;
  [[vk::multiple_wait_queues(2)]]
  while (remaining > 0) {
    acc += A[tid.x] * B[tid.x];
    remaining = remaining - 1;
  }

  // A do-while loop carries the annotation the same way; the OpLoopMerge sits on
  // the branch into the body.
  // OpLoopMerge %do_while_merge %do_while_continue MultipleWaitQueuesQCOM 4
  [[vk::multiple_wait_queues(4)]]
  do {
    acc = acc * 0.5;
  } while (acc.x + acc.y + acc.z + acc.w > 1024.0);

  // The hint composes with the existing loop control instead of replacing it:
  // this loop asks for both Unroll and multiple wait queues.
  // OpLoopMerge %for_merge_0 %for_continue_0 Unroll|MultipleWaitQueuesQCOM 0
  [[vk::multiple_wait_queues]] [unroll]
  for (uint j = 0; j < 4; ++j) {
    acc += A[tid.x + j];
  }

  Result[tid.x] = acc;
}
