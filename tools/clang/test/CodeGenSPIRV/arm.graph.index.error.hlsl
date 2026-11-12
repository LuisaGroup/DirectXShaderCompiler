// RUN: not %dxc -T cs_6_0 -E main -fcgl %s -spirv -fspv-extension=SPV_ARM_graph -fspv-extension=SPV_ARM_tensors 2>&1 | FileCheck %s

// L4 gate: the graph's input and output indices are not free.
//
// OpGraphInputARM's InputIndex selects both the input type in OpTypeGraphARM and
// the interface variable in OpGraphEntryPointARM, so the index a graph declaration
// uses has to agree with the position of that input in the graph's I/O list.
// SPIRV-Tools checks only that the index is in range and that the result type
// matches the type at that index - it cannot see a declaration whose indices are
// permuted, because a permuted graph is a different valid graph. Allowing the
// compiler to accept `GraphInput(2)` as the second input would therefore be a
// silent dataflow change: exactly the class of mistake the plan's gate table calls
// out.
//
// The rule is "inputs first, in order, starting from 0", and this file uses an
// index that skips one: the graph declares input 0 and then input 2.
//
// CHECK: error: data graph input 2 is out of order: the inputs of a graph must be declared in order starting from 0, because the input index also selects the input type of OpTypeGraphARM and the interface variable of OpGraphEntryPointARM
// The failed input is not added to the graph, so the outputs still line up and no
// second-order diagnostic appears: the only error is the out-of-order index.
// CHECK-NOT: error:

#include <vk/arm/graph.h>
#include <vk/arm/tensors.h>

using Tens = vk::arm::Tensor<float, 2>;

[numthreads(1, 1, 1)]
void main() {
  vk::arm::GraphBegin();
  Tens a = vk::arm::GraphInput<Tens>(0);
  // Input 1 is skipped: the next input has to be 1, not 2.
  Tens b = vk::arm::GraphInput<Tens>(2);
  vk::arm::GraphSetOutput(a, 0);
  vk::arm::GraphEnd();
}
