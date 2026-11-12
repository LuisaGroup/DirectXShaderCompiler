// RUN: %dxc -T cs_6_0 -E main -fcgl %s -spirv -fspv-extension=SPV_ARM_graph -fspv-extension=SPV_ARM_tensors | FileCheck %s

// L1/L2 gates for the SPV_ARM_graph graph region.
//
// The surface is <vk/arm/graph.h>: four declaration-only entry points that
// declare a data graph instead of emitting instructions into the shader body.
// This file pins the module a graph produces - the capability, the extension, the
// graph type, the graph object, its entry point, its body, and OpGraphEndARM, in
// the only order SPIRV-Tools accepts.
//
// The order is not a convention. SPIRV-Tools' graph region state machine
// (GraphScopedInstructions in validate_layout.cpp) accepts OpGraphInputARM only
// in its "begin" and "inputs" states, OpGraphSetOutputARM only from
// "begin"/"inputs"/"body"/"outputs", and OpGraphEndARM only from "outputs", and
// it rejects OpGraphEntryPointARM inside a body - so the region is exactly
//   OpGraphEntryPointARM, OpGraphARM, inputs..., body..., outputs...,
//   OpGraphEndARM
// and the CHECK lines below are in that order, which is what pins it.
//
// Why both extensions: a graph's inputs and outputs are tensors, so the module
// needs OpCapability TensorsARM and OpExtension "SPV_ARM_tensors" as well as
// GraphARM and "SPV_ARM_graph". An explicit -fspv-extension list is an
// allow-list, so a graph of tensors needs both named on the command line -
// arm.graph.extension.error.hlsl pins that.

#include <vk/arm/graph.h>
#include <vk/arm/tensors.h>
#include <vk/arm/tosa.h>

using Tens = vk::arm::tosa::Tensor<float>;

// L1: exactly one GraphARM capability and exactly one SPV_ARM_graph extension.
// Each CHECK-NOT is anchored between two CHECKs so that it is not vacuous: the
// first runs over the rest of the capability block, the second over the rest of
// the extension block.
// CHECK: OpCapability GraphARM
// CHECK-NOT: OpCapability GraphARM
// CHECK: OpCapability TensorsARM
// CHECK: OpExtension "SPV_ARM_graph"
// CHECK-NOT: OpExtension "SPV_ARM_graph"
// CHECK: OpExtension "SPV_ARM_tensors"
// CHECK: %[[TOSA:[0-9]+]] = OpExtInstImport "TOSA.001000.1"
// CHECK: OpMemoryModel Logical GLSL450

// L1: the graph is not a new entry-point *kind* in the module header: the shader
// keeps its OpEntryPoint, and the graph is an additional module-scope object. The
// entry point's name is the name OpGraphEntryPointARM gives the graph.
// CHECK: OpEntryPoint GLCompute %[[MAIN:[A-Za-z0-9_]+]] "main"

// L2: the interface variables' decorations come first in the module (the
// annotation section precedes the type section), so they are what pins the
// names: one UniformConstant variable per graph I/O, in graph type order, with
// the DescriptorSet/Binding pair the compiler assigns - set 0, and binding =
// position in the graph type's I/O list (inputs 0..N-1, then outputs). Vulkan
// requires both decorations on every UniformConstant variable, and HLSL has no
// way to declare one of these variables, so the compiler synthesizes them and
// the host has to bind the tensor descriptors to exactly these numbers.
// CHECK: OpDecorate %[[IN0:[A-Za-z0-9_]+]] DescriptorSet 0
// CHECK: OpDecorate %[[IN0]] Binding 0
// CHECK: OpDecorate %[[IN1:[A-Za-z0-9_]+]] DescriptorSet 0
// CHECK: OpDecorate %[[IN1]] Binding 1
// CHECK: OpDecorate %[[OUT0:[A-Za-z0-9_]+]] DescriptorSet 0
// CHECK: OpDecorate %[[OUT0]] Binding 2

// L2: the graph type. OpTypeGraphARM is "IdResult, LiteralInteger NumInputs,
// IdRef... InOutTypes": two inputs, then three tensor types (two inputs and one
// output). The literal 2 is the operand that says how many of the type operands
// are inputs, so it is asserted here rather than left to L3: a wrong count with at
// least one output left over still validates.
// CHECK: %[[TENSOR:[A-Za-z0-9_]+]] = OpTypeTensorARM %float
// CHECK: %[[PTR_TENSOR:[A-Za-z0-9_]+]] = OpTypePointer UniformConstant %[[TENSOR]]
// CHECK: %[[GRAPH_TYPE:[A-Za-z0-9_]+]] = OpTypeGraphARM 2 %[[TENSOR]] %[[TENSOR]] %[[TENSOR]]

// L2: the interface variables themselves. SPIRV-Tools requires each of them to be
// an OpVariable in UniformConstant storage whose pointee type is the graph type's
// I/O type at the same position.
// CHECK: %[[IN0]] = OpVariable %[[PTR_TENSOR]] UniformConstant
// CHECK: %[[IN1]] = OpVariable %[[PTR_TENSOR]] UniformConstant
// CHECK: %[[OUT0]] = OpVariable %[[PTR_TENSOR]] UniformConstant

// L2: the graph region, in the last section of the module. OpGraphEntryPointARM
// names the graph by its forward reference (the graph id is defined by the
// OpGraphARM below it), takes the shader entry point's name as a literal string,
// and lists one interface variable per graph I/O - SPIRV-Tools checks that the
// count matches the graph type's I/O count and that each pointee type matches.
// CHECK: OpGraphEntryPointARM %[[GRAPH:[0-9]+]] "main" %[[IN0]] %[[IN1]] %[[OUT0]]
// CHECK: %[[GRAPH]] = OpGraphARM %[[GRAPH_TYPE]]

// L2: the graph inputs, read by index. The index has to be the <id> of a 32-bit
// integer constant instruction (SPIRV-Tools, VUID 9931) and it selects both the
// input type in the graph type and the interface variable above, so the two
// indices are captured and used by the body instruction below: a transposed index
// is a different graph and this is what detects it.
// CHECK: %[[GIN0:[0-9]+]] = OpGraphInputARM %[[TENSOR]] %uint_0
// CHECK: %[[GIN1:[0-9]+]] = OpGraphInputARM %[[TENSOR]] %uint_1

// L2: the graph body. SPV_ARM_graph defines the graph's structure, not its
// operations: the operations come from an extended instruction set, and
// SPIRV-Tools rejects every other opcode in this section ("Op... cannot appear in
// the graph definitions section"). ADD is TOSA opcode 14 and takes its two data
// operands in order.
// CHECK: %[[SUM:[0-9]+]] = OpExtInst %[[TENSOR]] %[[TOSA]] ADD %[[GIN0]] %[[GIN1]]

// L2: the output, then the end of the region. OpGraphEndARM must be preceded by
// at least one OpGraphSetOutputARM, and nothing may follow it in the region.
// CHECK: OpGraphSetOutputARM %[[SUM]] %uint_0
// CHECK-NOT: OpGraphSetOutputARM
// CHECK: OpGraphEndARM
// The graph region is the last section of the module: these two run from
// OpGraphEndARM to the end of the file, so a second OpGraphEndARM, a graph
// instruction after it, or a body instruction after the outputs is a failure.
// CHECK-NOT: OpGraph
// CHECK-NOT: OpExtInst

// L3 (module validity) is implicit: the RUN line does not pass -Vd, so dxc
// validates the module (SpirvEmitter::spirvToolsValidate), and SPIRV-Tools is
// what rejects a missing capability, a malformed graph type, a wrong number of
// interface variables or a wrong opcode in the body.
//
// What this file cannot prove: that the graph computes anything. No CI driver
// implements VK_ARM_data_graph, so the encoding is all that is pinned. The host
// has to create the tensor descriptors and bind them to DescriptorSet 0 /
// Binding 0..2 (see <vk/arm/graph.h>).

[numthreads(1, 1, 1)]
void main() {
  // OpGraphARM, and the graph's name and interface are derived from this entry
  // point.
  vk::arm::GraphBegin();

  // OpGraphInputARM %uint_0 / %uint_1, in order: the index also selects the
  // input type of OpTypeGraphARM.
  Tens a = vk::arm::GraphInput<Tens>(0);
  Tens b = vk::arm::GraphInput<Tens>(1);

  // An OpExtInst of the TOSA set - the only kind of instruction a graph body may
  // contain.
  Tens sum = vk::arm::tosa::Add(a, b);

  // OpGraphSetOutputARM %uint_0, then OpGraphEndARM.
  vk::arm::GraphSetOutput(sum, 0);
  vk::arm::GraphEnd();
}
