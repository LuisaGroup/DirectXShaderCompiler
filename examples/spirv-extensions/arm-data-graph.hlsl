// RUN: %dxc -T cs_6_0 -E main -spirv -fcgl -fspv-extension=SPV_ARM_graph -fspv-extension=SPV_ARM_tensors %s

// Data graphs with VK_ARM_data_graph / SPV_ARM_graph.
//
// A data graph is not a shader in the "one invocation, one function" sense. It is a
// module-scope object that describes dataflow over *complete tensors* - inputs, a
// body of tensor operations, outputs - and the runtime hands the whole graph to an
// accelerator instead of executing it once per invocation. VK_ARM_data_graph adds a
// pipeline type of its own for that, so the host creates a graph pipeline from this
// module rather than a compute pipeline:
//
//   VkDataGraphPipelineCreateInfoARM -> the module, the entry point name, and one
//                                       tensor per graph I/O
//   VkTensorCreateInfoARM            -> vkCreateTensorARM per graph I/O
//   VkTensorDescriptionARM           -> element type, dimensionCount, dimensions
//   vkUpdateDescriptorSets           -> VK_DESCRIPTOR_TYPE_STORAGE_TENSOR_ARM at
//                                       binding 0..N (see below)
//   vkCreateDataGraphPipelinesARM    -> the graph pipeline
//
// The host also has to enable the VK_ARM_data_graph device extension and its
// feature bits, and VK_ARM_tensors for the tensors themselves. None of that is
// something the compiler can check, and no open-source driver implements the
// extension yet, so this file pins the *encoding*: the compile below validates
// because dxc runs SPIRV-Tools on everything it emits unless -Vd is passed.
//
// ## The structure the compiler emits
//
//   OpCapability GraphARM
//   OpCapability TensorsARM
//   OpExtension "SPV_ARM_graph"
//   OpExtension "SPV_ARM_tensors"
//   ...
//   %t   = OpTypeTensorARM %float                  ; the I/O type (a graph *must*
//   %g   = OpTypeGraphARM 2 %t %t %t               ; use tensors: 2 in, 1 out)
//   %in0 = OpVariable %ptr_t UniformConstant       ; DescriptorSet 0, Binding 0
//   %in1 = OpVariable %ptr_t UniformConstant       ; DescriptorSet 0, Binding 1
//   %out = OpVariable %ptr_t UniformConstant       ; DescriptorSet 0, Binding 2
//   %main = OpFunction ... OpFunctionEnd           ; the shader entry point, empty
//   OpGraphEntryPointARM %g "main" %in0 %in1 %out
//   %g    = OpGraphARM %t
//   %v0   = OpGraphInputARM %t %uint_0
//   %v1   = OpGraphInputARM %t %uint_1
//   %r    = OpExtInst %t %tosa ADD %v0 %v1
//   OpGraphSetOutputARM %r %uint_0
//   OpGraphEndARM
//
// The order of those last six groups is the only order SPIRV-Tools accepts: the
// graph region has a state machine (inputs may follow OpGraphARM or another input,
// outputs must follow the body, OpGraphEndARM must follow at least one output, and
// OpGraphEntryPointARM may not appear inside a body), and the region is the last
// section of the module, after every function.
//
// ## What this expresses, and what it does not
//
// Expressed: one graph per module, tensor inputs and outputs, a body of extended
// instructions (here TOSA, <vk/arm/tosa.h>), and the interface variables with the
// DescriptorSet/Binding numbers the host binds to. The graph's name is the shader
// entry point's name.
//
// Not expressed, and documented in <vk/arm/graph.h>: an array-of-tensors input or
// output (SPV_ARM_graph allows one with an ElementIndex operand, HLSL cannot spell
// the type), OpGraphConstantARM (a tensor of literals needs the Shape operand the
// tensor type cannot carry), more than one graph per module, a graph in a
// non-compute stage, and a "pure" graph module - the module keeps the shader's
// OpEntryPoint and its empty entry function, which SPIRV-Tools accepts but which a
// host that consumes the graph should ignore.
//
// The graph's inputs and outputs are declared as graph values, not as shader
// resources: HLSL has no way to declare a tensor descriptor, so the compiler
// synthesizes the three UniformConstant variables, and a local in the declaring
// function is a *name* for a graph value rather than a memory object (a graph body
// may contain no OpVariable, OpLoad or OpStore).

#include <vk/arm/graph.h>
#include <vk/arm/tensors.h>
#include <vk/arm/tosa.h>

// The I/O type of the graph. The TOSA operations are declared over their own
// unranked vk::arm::tosa::Tensor<ElementType>, so a graph whose body is TOSA
// operations is declared over that type; vk::arm::Tensor<float, 2> (the ranked
// spelling of <vk/arm/tensors.h>) is the type to use for a graph whose I/O need a
// rank and whose body does not use TOSA. Both lower to OpTypeTensorARM.
using Tens = vk::arm::tosa::Tensor<float>;

[numthreads(1, 1, 1)]
void main() {
  // OpGraphARM. Everything up to GraphEnd describes the graph region; the entry
  // point's body is a declaration, not code.
  vk::arm::GraphBegin();

  // Two inputs. The index is a compile-time constant and also selects the input
  // type of OpTypeGraphARM and the interface variable, so the inputs are declared
  // in order starting from 0.
  Tens a = vk::arm::GraphInput<Tens>(0);
  Tens b = vk::arm::GraphInput<Tens>(1);

  // The graph body: an extended instruction of the TOSA set. This is the only kind
  // of operation a graph region may contain - SPV_ARM_graph defines the structure
  // of a graph, the extended instruction set defines its operations.
  Tens sum = vk::arm::tosa::Add(a, b);

  // One output, then the end of the region. A graph must set at least one output:
  // every OpTypeGraphARM has at least one output type.
  vk::arm::GraphSetOutput(sum, 0);
  vk::arm::GraphEnd();
}
