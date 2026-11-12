// Copyright (c) 2026 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Data graphs: VK_ARM_data_graph / SPV_ARM_graph.
//
// A data graph is not a shader in the "one invocation, one function" sense. It
// is a module-scope object that describes dataflow over *complete tensors*: a
// graph has inputs, a body of tensor operations, and outputs, and a runtime
// hands the whole graph to an accelerator instead of executing it once per
// invocation:
//
//   #include <vk/arm/graph.h>
//   #include <vk/arm/tensors.h>
//   #include <vk/arm/tosa.h>
//
//   using Tens = vk::arm::tosa::Tensor<float>;
//
//   [numthreads(1, 1, 1)]
//   void main() {
//     vk::arm::GraphBegin();                       // OpGraphARM
//     Tens a = vk::arm::GraphInput<Tens>(0);       // OpGraphInputARM %uint_0
//     Tens b = vk::arm::GraphInput<Tens>(1);       // OpGraphInputARM %uint_1
//     Tens s = vk::arm::tosa::Add(a, b);           // OpExtInst ADD
//     vk::arm::GraphSetOutput(s, 0);               // OpGraphSetOutputARM
//     vk::arm::GraphEnd();                         // OpGraphEndARM
//   }
//
// which is a module consisting of
//
//   OpCapability GraphARM
//   OpExtension "SPV_ARM_graph"
//   ...
//   %t = OpTypeTensorARM %float
//   %g = OpTypeGraphARM 2 %t %t %t          ; 2 inputs, 1 output
//   %in0 = OpVariable %ptr_t UniformConstant ; DescriptorSet 0, Binding 0
//   %in1 = OpVariable %ptr_t UniformConstant ; DescriptorSet 0, Binding 1
//   %out0 = OpVariable %ptr_t UniformConstant ; DescriptorSet 0, Binding 2
//   %main = OpFunction %void None %fn         ; the shader entry point, empty
//   ...
//   OpGraphEntryPointARM %graph "main" %in0 %in1 %out0
//   %graph = OpGraphARM %g
//   %v0 = OpGraphInputARM %t %uint_0
//   %v1 = OpGraphInputARM %t %uint_1
//   %r = OpExtInst %t %tosa ADD %v0 %v1
//   OpGraphSetOutputARM %r %uint_0
//   OpGraphEndARM
//
// The element type of a graph is a tensor, and which *spelling* of the tensor type
// to use is decided by the graph's body: the operations of <vk/arm/tosa.h> are
// declared over its own unranked vk::arm::tosa::Tensor<ElementType>, so a graph
// whose body is TOSA operations uses that type, while a graph whose I/O need a
// rank (and no TOSA operation) uses the ranked vk::arm::Tensor<ElementType, Rank>
// of <vk/arm/tensors.h>, which lowers to OpTypeTensorARM with the rank as an extra
// operand. The two are distinct HLSL types, so they do not mix in one graph.
//
// ## What a graph is, and what this landing is not
//
// SPV_ARM_graph defines the graph's *structure*, not its operations: the body of
// a graph has to be filled with extended instructions (TOSA, <vk/arm/tosa.h>),
// and the graph types are tensors (<vk/arm/tensors.h>). The graph region itself
// is the last section of a SPIR-V module, after every function, and SPIRV-Tools
// accepts the five groups of instructions in exactly one order:
//
//   OpGraphEntryPointARM (outside a body)   - names the graph and its interface
//   OpGraphARM                              - the graph object
//   OpGraphInputARM*                        - reads, must come first in the body
//   body instructions                       - OpExtInst only
//   OpGraphSetOutputARM+                    - writes, must come last
//   OpGraphEndARM                           - closes the region
//
// HLSL has no construct for "a function whose body is a graph", so the four
// entry points below are compiler builtins that *declare* the region: they have
// no definition anywhere, and SPIR-V CodeGen records what they describe instead
// of emitting an instruction into the shader body (SpirvEmitter::
// processArmGraphIntrinsic). The body of the entry point that declares a graph
// is therefore a declaration, not code:
//
//  * A local tensor is a *name for a value*, not a memory object. `Tens a =
//    GraphInput<Tens>(0);` records the input; the emitter emits no OpVariable and
//    no OpStore for `a`, and a later use of `a` is the input's value. A graph
//    body cannot contain an OpVariable, an OpLoad or an OpStore, so this is a
//    renaming, and reading a local before it is given a value is an error.
//  * The graph body is made of extended instructions - the TOSA operations of
//    <vk/arm/tosa.h> - and of nothing else. Any other operation is diagnosed:
//    "only extended instructions can appear in a data graph body".
//  * Any other instruction the shader body would produce is diagnosed too: the
//    entry point that declares a graph may not contain code.
//
// This is a landing, not the finished feature. What it can express: one graph per
// module, tensor inputs and outputs, and a body of extended instructions. What it
// cannot express, and does not pretend to:
//
//  * A graph with an array-of-tensors input or output. SPV_ARM_graph allows one
//    (with an ElementIndex operand on OpGraphInputARM / OpGraphSetOutputARM), but
//    HLSL has no way to spell such a type, so only plain OpTypeTensorARM I/O is
//    accepted here.
//  * OpGraphConstantARM. A graph constant is a tensor of literals, which needs
//    the Shape operand the tensor type cannot carry (see <vk/arm/tensors.h>).
//  * More than one graph in a module, and a graph in a non-compute stage.
//  * A "pure" graph module: the module this landing emits keeps the shader's
//    OpEntryPoint and its (empty) entry function. SPIRV-Tools accepts both, and
//    dropping the shader entry point is a possible follow-up, but a host that
//    consumes the graph should read the graph, not the entry point.
//  * A graph resource in HLSL. A graph's interface variables are synthesized by
//    the compiler, so the shader cannot name them: a graph value can only be
//    consumed by another graph operation, never handed to a non-graph one.
//
// ## Registration, and turning the feature off
//
// SPV_ARM_graph is registered in FeatureManager and enabled by default, so no
// command-line flag is needed. Naming it in an explicit -fspv-extension list is
// accepted, and leaving it out of such a list is a compile error rather than a
// module that declares an extension the host never asked for (an L4 gate). The
// capability (GraphARM, 4191) and OpExtension "SPV_ARM_graph" are requested by
// GraphBegin itself, because nothing else in the module infers them: the graph
// region is not part of the tree CapabilityVisitor walks.
//
// Because a graph's inputs and outputs are tensors, a graph module also declares
// OpCapability TensorsARM and OpExtension "SPV_ARM_tensors". With an explicit
// -fspv-extension list that means naming *both*:
//
//   -T cs_6_0 -E main -spirv -fspv-extension=SPV_ARM_graph \
//                            -fspv-extension=SPV_ARM_tensors
//
// and naming only one of them is a compile error rather than a module that
// declares half of what it needs.
//
// ## What the host has to do
//
// The compiler cannot check any of this, and no CI driver implements
// VK_ARM_data_graph:
//
//  * Enable the VK_ARM_data_graph device extension and its feature bits, and
//    create a graph pipeline (VK_ARM_data_graph adds a pipeline type of its own)
//    from this module.
//  * Create one tensor per graph I/O with vkCreateTensorARM and bind it to the
//    descriptor the compiler assigned: DescriptorSet 0, and Binding 0..N-1 for
//    the inputs followed by N.. for the outputs, in the order the graph declares
//    them. A mismatched element type or rank fails at pipeline creation.
//  * The graph entry point's name is the shader entry point's name ("main" in the
//    example above), which is what OpGraphEntryPointARM names.
//  * Numeric conformance is the implementation's: no CI in this repository
//    executes a single graph operation, so the tests pin the encoding, not the
//    arithmetic.
//
// See docs/SPIR-V.rst ("Arm data graphs") and
// examples/spirv-extensions/arm-data-graph.hlsl.

#ifndef _HLSL_VK_ARM_GRAPH_H_
#define _HLSL_VK_ARM_GRAPH_H_

namespace vk {
namespace arm {

// Opens the module's data graph. Lowers to OpGraphARM and, at the end of the
// module, to OpGraphEntryPointARM; the graph type OpTypeGraphARM is built from
// the inputs and outputs the graph declares, so this call takes no arguments.
//
// It must be the first statement of the function that declares the graph, and
// that function may contain nothing else: the whole body is the declaration. For
// a compute shader that function is the entry point; in a library target it can
// be a helper function, and the graph is then emitted once, at module scope,
// named after that helper. The name OpGraphEntryPointARM gives the graph is the
// name of the declaring function.
//
// The graph is a compute-pipeline object: VK_ARM_data_graph pipelines are compute
// pipelines, so 'GraphBegin' is refused in every other stage.
void GraphBegin();

// Reads graph input Index, which has type TensorType. Lowers to
//   %v = OpGraphInputARM %TensorType %uint_<Index>
// TensorType has to be a tensor type - vk::arm::Tensor<ElementType, Rank> or
// vk::arm::tosa::Tensor<ElementType>, which both lower to OpTypeTensorARM -
// because SPV_ARM_graph requires every graph input and output type to be a tensor
// (or an array of tensors, which HLSL cannot spell).
//
// Index has to be a compile-time constant, because OpGraphInputARM's InputIndex
// is the <id> of a 32-bit integer constant instruction, and it also selects the
// input type in OpTypeGraphARM and the interface variable in
// OpGraphEntryPointARM: the inputs of a graph must therefore be declared in order
// starting from 0, and a transposed index is a compile error rather than a
// silently different graph.
template <typename TensorType>
TensorType GraphInput(uint Index);

// Sets graph output Index to Value. Lowers to
//   OpGraphSetOutputARM %Value %uint_<Index>
// Value has to be a tensor - the output of a graph operation or one of its
// inputs - and, for the same reason as for GraphInput, Index has to be a
// compile-time constant and the outputs have to be set in order starting from 0.
// A graph must set at least one output before GraphEnd.
template <typename TensorType>
void GraphSetOutput(TensorType Value, uint Index);

// Closes the module's data graph: builds OpTypeGraphARM, synthesizes the
// UniformConstant interface variables OpGraphEntryPointARM names (DescriptorSet
// 0, Binding = position in the graph type's I/O list) and ends the region with
// OpGraphEndARM. Nothing of the graph may be declared after it.
void GraphEnd();

} // namespace arm
} // namespace vk

#endif // _HLSL_VK_ARM_GRAPH_H_
