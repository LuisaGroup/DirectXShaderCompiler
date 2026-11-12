// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 -fcgl -fspv-extension=SPV_QCOM_multiple_wait_queues %s | FileCheck %s

// VK_QCOM_shader_multiple_wait_queues on a cooperative-matrix loop
// (G29/L2.coopmatrix).
//
// The extension exists for exactly this shape: a loop whose body loads
// cooperative matrices and multiplies them. Unrolling such a loop to hide memory
// latency multiplies the live register count, so the alternative the extension
// offers is to let the implementation keep several wait queues in flight for one
// iteration instead of deepening the pipeline by unrolling.
//
// This test asserts that the two capabilities coexist in one module and that the
// loop control bit lands on the loop that contains the cooperative-matrix
// multiply-add - the annotation is not module-wide state, it is one bit of one
// OpLoopMerge. Nothing here claims a driver uses more than one queue: the file is
// encoding-only, like the other gates.
//
// SPV_KHR_cooperative_matrix is enabled by default (it is not opt-in), so only
// SPV_QCOM_multiple_wait_queues has to be named on the RUN line.

#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<int> inputA;
RWStructuredBuffer<int> inputB;
RWStructuredBuffer<int> output;

// Both capabilities, in the header, once each.
// CHECK: OpCapability CooperativeMatrixKHR
// CHECK: OpCapability MultipleWaitQueuesQCOM
// CHECK-NOT: OpCapability MultipleWaitQueuesQCOM
// CHECK: OpExtension "SPV_KHR_cooperative_matrix"
// CHECK: OpExtension "SPV_QCOM_multiple_wait_queues"
// CHECK-NOT: OpExtension "SPV_QCOM_multiple_wait_queues"
// The cooperative matrix type is what makes this loop the intended shape.
// CHECK: OpTypeCooperativeMatrixKHR

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  using MatA = vk::khr::CooperativeMatrixA<int, vk::ScopeSubgroup, 16, 16>;
  using MatB = vk::khr::CooperativeMatrixB<int, vk::ScopeSubgroup, 16, 16>;
  using MatC = vk::khr::CooperativeMatrixAccumulator<int, vk::ScopeSubgroup, 16, 16>;

  MatA matA = MatA::Splat(inputA[tid.x]);
  MatB matB = MatB::Splat(inputB[tid.x]);
  MatC matC = MatC::Splat(0);

  // CHECK-LABEL: %for_check = OpLabel
  // CHECK: OpLoopMerge %for_merge %for_continue MultipleWaitQueuesQCOM 2
  // CHECK-NEXT: OpBranchConditional {{%[0-9]+}} %for_body %for_merge
  [[vk::multiple_wait_queues(2)]]
  for (int k = 0; k < 4; ++k) {
    // The multiply-add belongs to the annotated loop. The header's
    // cooperativeMatrixMultiplyAdd() is a helper function, so the loop body calls
    // it and the OpCooperativeMatrixMulAddKHR itself is in that helper - only the
    // loop that calls it carries the loop control bit. (The instruction is
    // asserted by the pre-existing coopmatrix tests; this file asserts the
    // combination of the cooperative-matrix capability with the loop control
    // bit.)
    // CHECK-LABEL: %for_body = OpLabel
    // CHECK: OpFunctionCall %CooperativeMatrix_1 %vk__khr__cooperativeMatrixMultiplyAdd
    matC = cooperativeMatrixMultiplyAdd(matA, matB, matC);
  }

  output[tid.x] = inputA[tid.x];
}
