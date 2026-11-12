// RUN: not %dxc -T ps_6_0 -E main -fcgl %s -spirv -fspv-extension=SPV_ARM_graph -fspv-extension=SPV_ARM_tensors 2>&1 | FileCheck %s

// L4 gate: a data graph is a compute-pipeline object.
//
// VK_ARM_data_graph creates graph pipelines, which are compute-family pipelines,
// and the module this landing emits keeps the shader's own OpEntryPoint next to the
// graph. A graph declared by a pixel (or vertex, or mesh) entry point would
// therefore be a module whose shader entry point belongs to a stage no graph
// pipeline can be created from. The vertex/fragment stage is refused here rather
// than being turned into a module that validates and that no host can use.
//
// This is a policy check, not a validator rule: OpGraphEntryPointARM carries no
// execution model - the graph has none - so SPIRV-Tools has nothing to check. That
// is exactly why the diagnostic has to exist on the compiler side.
//
// CHECK: error: 'vk::arm::GraphBegin' is only available in compute shaders: a VK_ARM_data_graph pipeline is a compute pipeline, and a module that declares a graph keeps the entry point it was compiled for
// The declaration is reported once: the entry points that follow a 'GraphBegin'
// that failed are skipped rather than repeating a message that would suggest the
// shader never opened a graph when it did.
// CHECK-NOT: error:

#include <vk/arm/graph.h>
#include <vk/arm/tensors.h>

using Tens = vk::arm::Tensor<float, 2>;

float4 main() : SV_Target {
  vk::arm::GraphBegin();
  Tens a = vk::arm::GraphInput<Tens>(0);
  vk::arm::GraphSetOutput(a, 0);
  vk::arm::GraphEnd();
  return 0;
}
