// RUN: %dxc -T cs_6_0 -E main %s -spirv -fspv-extension=SPV_ARM_graph -fspv-extension=SPV_ARM_tensors | FileCheck %s

// L6 gate: the graph survives the shipped post-processing.
//
// The RUN line does not pass -fcgl, so the module goes through legalization, the
// optimizer and capability trimming before validation (SpirvEmitter.cpp:1041-1105;
// the capability-trimming pass runs even at -Od). Two things can go wrong only
// here, and this file is what catches them:
//
//  * spirv-opt does not know the OpGraph*ARM instructions. It inlines the HLSL
//    entry-point wrapper, drops the now-unused function, and must leave the graph
//    region intact: the graph type, the interface variables, the graph object, its
//    entry point, the body, the outputs and OpGraphEndARM.
//  * capability trimming could remove GraphARM (and TensorsARM), which would leave
//    the module with graph instructions and no capability - invalid, and caught by
//    the validation dxc runs on the result.
//
// The interesting part of the comparison with arm.graph.hlsl is what is *gone*:
// the wrapper function and its OpFunctionCall are optimized away, and the ids
// change, so this file asserts the graph itself, not the ids. It is a separate
// file rather than a second RUN line on arm.graph.hlsl because the emitted module
// is a different one - the pre-optimizer test pins the emitter's own output.

#include <vk/arm/graph.h>
#include <vk/arm/tensors.h>
#include <vk/arm/tosa.h>

using Tens = vk::arm::tosa::Tensor<float>;

// The capability and the extension survive trimming: both are still needed by
// what the module contains, and the trimming pass must not decide otherwise.
// CHECK: OpCapability GraphARM
// CHECK: OpCapability TensorsARM
// CHECK: OpExtension "SPV_ARM_graph"
// CHECK: OpExtension "SPV_ARM_tensors"

// The interface variables and their decorations survive, and are still the ones
// OpGraphEntryPointARM names.
// CHECK: OpDecorate %[[IN0:[A-Za-z0-9_]+]] DescriptorSet 0
// CHECK: OpDecorate %[[IN0]] Binding 0
// CHECK: OpDecorate %[[IN1:[A-Za-z0-9_]+]] DescriptorSet 0
// CHECK: OpDecorate %[[IN1]] Binding 1
// CHECK: OpDecorate %[[OUT0:[A-Za-z0-9_]+]] DescriptorSet 0
// CHECK: OpDecorate %[[OUT0]] Binding 2

// The graph type and its interface.
// CHECK: %[[TENSOR:[A-Za-z0-9_]+]] = OpTypeTensorARM %float
// CHECK: %[[GRAPH_TYPE:[A-Za-z0-9_]+]] = OpTypeGraphARM 2 %[[TENSOR]] %[[TENSOR]] %[[TENSOR]]
// CHECK: %[[IN0]] = OpVariable
// CHECK: %[[IN1]] = OpVariable
// CHECK: %[[OUT0]] = OpVariable

// The graph region, still in the last module section and still in order.
// CHECK: OpGraphEntryPointARM %[[GRAPH:[0-9]+]] "main" %[[IN0]] %[[IN1]] %[[OUT0]]
// CHECK: %[[GRAPH]] = OpGraphARM %[[GRAPH_TYPE]]
// CHECK: %[[GIN0:[0-9]+]] = OpGraphInputARM %[[TENSOR]] %uint_0
// CHECK: %[[GIN1:[0-9]+]] = OpGraphInputARM %[[TENSOR]] %uint_1
// CHECK: %[[SUM:[0-9]+]] = OpExtInst %[[TENSOR]] {{.*}} ADD %[[GIN0]] %[[GIN1]]
// CHECK: OpGraphSetOutputARM %[[SUM]] %uint_0
// CHECK-NOT: OpGraphSetOutputARM
// CHECK: OpGraphEndARM
// CHECK-NOT: OpGraph

// The empty compute entry point is still there (it is what the module was
// compiled for), but the HLSL wrapper around it is gone: the optimizer inlined it.
// CHECK-NOT: OpFunctionCall

[numthreads(1, 1, 1)]
void main() {
  vk::arm::GraphBegin();
  Tens a = vk::arm::GraphInput<Tens>(0);
  Tens b = vk::arm::GraphInput<Tens>(1);
  vk::arm::GraphSetOutput(vk::arm::tosa::Add(a, b), 0);
  vk::arm::GraphEnd();
}
