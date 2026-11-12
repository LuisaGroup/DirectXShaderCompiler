// RUN: not %dxc -T cs_6_0 -E main -fcgl %s -spirv -fspv-extension=SPV_ARM_graph -fspv-extension=SPV_ARM_tensors 2>&1 | FileCheck %s

// L4 gate: a module has at most one graph, and a graph cannot be nested.
//
// SPV_ARM_graph's entry point names one graph (OpGraphEntryPointARM), and this
// landing declares one graph per shader: the graph type, the interface variables
// and the DescriptorSet/Binding numbers the host binds to are all derived from a
// single declaration. A second graph region would need its own entry point and its
// own interface, which is a different feature.
//
// SPIRV-Tools rejects a nested region as a layout error ("Cannot define a graph in
// a graph"), and a second *sibling* region would be accepted by the validator and
// silently share the module's interface variables - so the compiler refuses both
// with one diagnostic, at the second 'GraphBegin'.
//
// CHECK: error: a module may declare at most one data graph: SPV_ARM_graph's OpGraphEntryPointARM names one graph, and a graph region cannot be nested inside another graph
// The first graph is complete and valid, so it is the only error.
// CHECK-NOT: error:

#include <vk/arm/graph.h>
#include <vk/arm/tensors.h>

using Tens = vk::arm::Tensor<float, 2>;

[numthreads(1, 1, 1)]
void main() {
  vk::arm::GraphBegin();
  Tens a = vk::arm::GraphInput<Tens>(0);
  vk::arm::GraphSetOutput(a, 0);
  vk::arm::GraphEnd();

  // A second graph in the same module.
  vk::arm::GraphBegin();
  Tens b = vk::arm::GraphInput<Tens>(0);
  vk::arm::GraphSetOutput(b, 0);
  vk::arm::GraphEnd();
}
