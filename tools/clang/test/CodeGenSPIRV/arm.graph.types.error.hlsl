// RUN: not %dxc -T cs_6_0 -E main -fcgl %s -spirv -fspv-extension=SPV_ARM_graph -fspv-extension=SPV_ARM_tensors 2>&1 | FileCheck %s

// L4 gate: a graph's inputs and outputs are tensors.
//
// OpTypeGraphARM's InOutTypes operands have to be "Graph Interface Types", which
// SPIRV-Tools defines as OpTypeTensorARM or an array of it
// (IsGraphInterfaceType in validate_graph.cpp: "I/O type %id is not a Graph
// Interface Type"). A graph over floats would be rejected by the validator, so it
// is rejected here - with the type the graph could have used named in the message.
//
// A tensor is spelled vk::arm::Tensor<ElementType, Rank> (ranked) or
// vk::arm::tosa::Tensor<ElementType> (unranked, the type <vk/arm/tosa.h>'s
// operations are declared over); both lower to OpTypeTensorARM. A plain HLSL
// scalar - or a vector, or a struct - does not.
//
// CHECK: error: the type of a data graph input must be a tensor type (vk::arm::tensors::Tensor<ElementType, Rank>, which lowers to OpTypeTensorARM): SPV_ARM_graph requires every graph input and output type to be OpTypeTensorARM or an array of it
// The refused input has no value, so storing it and writing it to an output are
// reported too: a local in a graph declaration is a name for a graph value, and
// there is none.
// CHECK: error: a value is read in a data graph declaration before it is given one
// CHECK: error: the value of a data graph output must be a tensor

#include <vk/arm/graph.h>

[numthreads(1, 1, 1)]
void main() {
  vk::arm::GraphBegin();
  // 'float' is not a graph interface type: the graph's inputs and outputs are
  // whole tensors, not per-invocation scalars.
  float a = vk::arm::GraphInput<float>(0);
  vk::arm::GraphSetOutput(a, 0);
  vk::arm::GraphEnd();
}
