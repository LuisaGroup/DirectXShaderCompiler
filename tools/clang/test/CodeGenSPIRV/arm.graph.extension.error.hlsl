// RUN: not %dxc -T cs_6_0 -E main -fcgl %s -spirv -fspv-extension=SPV_ARM_tensors 2>&1 | FileCheck %s

// L4 gate: SPV_ARM_graph is registered in FeatureManager, so an explicit
// -fspv-extension list is an allow-list and a graph that was not asked for is
// refused - before any code generation, with the diagnostic FeatureManager emits
// for every extension (FeatureManager::requestExtension).
//
// This is what makes the registration real: without the enum entry and the symbol
// mapping, -fspv-extension=SPV_ARM_graph would be "unknown SPIR-V extension", and
// without the requestExtension() call in the emitter the module would be emitted
// with an extension the host never enabled.
//
// SPV_ARM_tensors is named on the command line and SPV_ARM_graph is not, which is
// the interesting shape: the graph's I/O are tensors, so a graph needs *both*
// extensions, and naming only one of them has to fail rather than silently emit
// the other.
//
// CHECK: error: SPIR-V extension 'SPV_ARM_graph' required for data graphs but not permitted to use
// The refusal is the only error: the declaration cannot be turned into a graph,
// so no module is emitted, and the entry points that follow the failed
// 'GraphBegin' are skipped instead of repeating "open the graph first".
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
}
