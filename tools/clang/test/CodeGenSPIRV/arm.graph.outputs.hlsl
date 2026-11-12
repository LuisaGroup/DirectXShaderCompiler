// RUN: %dxc -T cs_6_0 -E main -fcgl %s -spirv -fspv-extension=SPV_ARM_graph -fspv-extension=SPV_ARM_tensors | FileCheck %s

// L2 gate for the graph's I/O list: two inputs, two outputs.
//
// OpTypeGraphARM's operands are "LiteralInteger NumInputs, IdRef... InOutTypes",
// and the *order* of the types is the order of OpGraphEntryPointARM's interface
// list: the inputs first, then the outputs. Within each group the position is
// the index the corresponding OpGraphInputARM / OpGraphSetOutputARM reads or
// writes, so a graph whose indices or interface variables are permuted is a
// different graph that still validates - SPIRV-Tools only checks that every
// index is in range and that the types line up with the index that is used.
// This file pins the mapping so that a compiler-side permutation is caught:
//
//   input  0 -> %graph_input0  -> DescriptorSet 0 / Binding 0
//   input  1 -> %graph_input1  -> DescriptorSet 0 / Binding 1
//   output 0 -> %graph_output0 -> DescriptorSet 0 / Binding 2
//   output 1 -> %graph_output1 -> DescriptorSet 0 / Binding 3
//
// Output 0 is the sum of the two inputs and output 1 is input 1 itself, so the
// two OpGraphSetOutputARM instructions name *different* values: a swapped operand
// pair is visible in the CHECK lines below, whereas an output written twice would
// not be.

#include <vk/arm/graph.h>
#include <vk/arm/tensors.h>
#include <vk/arm/tosa.h>

using Tens = vk::arm::tosa::Tensor<float>;

// CHECK: OpCapability GraphARM
// CHECK: OpExtension "SPV_ARM_graph"
// CHECK: %[[TOSA:[0-9]+]] = OpExtInstImport "TOSA.001000.1"

// The interface variables, in graph type order: the bindings are the position in
// that list, and they are the numbers the host has to bind the tensor descriptors
// to.
// CHECK: OpDecorate %[[IN0:[A-Za-z0-9_]+]] Binding 0
// CHECK: OpDecorate %[[IN1:[A-Za-z0-9_]+]] Binding 1
// CHECK: OpDecorate %[[OUT0:[A-Za-z0-9_]+]] Binding 2
// CHECK: OpDecorate %[[OUT1:[A-Za-z0-9_]+]] Binding 3

// NumInputs is 2 and four type operands follow: two inputs and two outputs. The
// graph type has to have at least one output, and it is NumInputs that says where
// the output list starts.
// CHECK: %[[TENSOR:[A-Za-z0-9_]+]] = OpTypeTensorARM %float
// CHECK: %[[GRAPH_TYPE:[A-Za-z0-9_]+]] = OpTypeGraphARM 2 %[[TENSOR]] %[[TENSOR]] %[[TENSOR]] %[[TENSOR]]

// The interface list of OpGraphEntryPointARM, in the same order, with one
// variable per I/O (SPIRV-Tools checks the count against the graph type and each
// pointee type against the corresponding operand).
// CHECK: OpGraphEntryPointARM %[[GRAPH:[0-9]+]] "main" %[[IN0]] %[[IN1]] %[[OUT0]] %[[OUT1]]
// CHECK: %[[GRAPH]] = OpGraphARM %[[GRAPH_TYPE]]

// The inputs, by index.
// CHECK: %[[GIN0:[0-9]+]] = OpGraphInputARM %[[TENSOR]] %uint_0
// CHECK: %[[GIN1:[0-9]+]] = OpGraphInputARM %[[TENSOR]] %uint_1

// The body and the two outputs. The indices are asserted because a swapped output
// index is a silent dataflow change: it still validates.
// CHECK: %[[SUM:[0-9]+]] = OpExtInst %[[TENSOR]] %[[TOSA]] ADD %[[GIN0]] %[[GIN1]]
// CHECK: OpGraphSetOutputARM %[[SUM]] %uint_0
// Output 1 is input 1 itself, so the operand of the second
// OpGraphSetOutputARM is the *input instruction*, not the sum: a compiler that
// swapped the two output values would still produce a valid module, and this is
// what detects it.
// CHECK: OpGraphSetOutputARM %[[GIN1]] %uint_1
// CHECK-NOT: OpGraphSetOutputARM
// CHECK: OpGraphEndARM
// CHECK-NOT: OpGraph

[numthreads(1, 1, 1)]
void main() {
  vk::arm::GraphBegin();
  Tens a = vk::arm::GraphInput<Tens>(0);
  Tens b = vk::arm::GraphInput<Tens>(1);
  // Output 0 is the TOSA sum; output 1 is the second input, unchanged.
  vk::arm::GraphSetOutput(vk::arm::tosa::Add(a, b), 0);
  vk::arm::GraphSetOutput(b, 1);
  vk::arm::GraphEnd();
}
