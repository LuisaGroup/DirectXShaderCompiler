// RUN: not %dxc -T cs_6_0 -E main -fcgl %s -spirv -fspv-extension=SPV_ARM_graph -fspv-extension=SPV_ARM_tensors 2>&1 | FileCheck %s

// L4 gate: the entry point that declares a graph may not contain code.
//
// A graph region is a module-scope dataflow description, not per-invocation code,
// and SPV_ARM_graph gives it no encoding for a shader statement: SPIRV-Tools
// accepts only extended instructions (and OpCompositeExtract) in the
// graph-definitions section, and everything else is "Op... cannot appear in the
// graph definitions section". So a shader body that declares a graph is a
// declaration: every value it names has to be a graph input or a graph operation,
// and anything else has nowhere to go.
//
// Two shapes are reported, and this file exercises the second:
//  * an instruction the emitter produces in the entry point - a branch, an
//    arithmetic operation, a call - is found at the end of the function, because
//    the graph declaration is not emitted as code and the instruction would
//    otherwise sit in an empty compute shader next to a graph that ignores it;
//  * a *local variable* of the shader body is a name for a graph value, so a local
//    whose value is not a tensor has no graph value to name. That is this file:
//    'float x = 1.0;' is a store of a float, and a graph region has no OpStore and
//    no non-tensor values.
//
// CHECK: error: a local variable in a data graph declaration must hold a tensor produced by a graph operation: a graph region has no OpVariable and no OpStore, so a value of any other type cannot be part of the graph
// The graph itself is well formed, so there is no second diagnostic.
// CHECK-NOT: error:

#include <vk/arm/graph.h>
#include <vk/arm/tensors.h>

using Tens = vk::arm::Tensor<float, 2>;

[numthreads(1, 1, 1)]
void main() {
  vk::arm::GraphBegin();
  Tens a = vk::arm::GraphInput<Tens>(0);
  vk::arm::GraphSetOutput(a, 0);
  // Not a graph value: there is no tensor here, so there is nothing the graph
  // could contain.
  float x = 1.0;
  vk::arm::GraphEnd();
}
