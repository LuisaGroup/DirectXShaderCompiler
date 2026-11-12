// RUN: %dxc -T cs_6_0 -E main -spirv -fcgl -HV 2021 -fspv-extension=SPV_ARM_tensors %s

// Tensors with VK_ARM_tensors / SPV_ARM_tensors.
//
// A tensor is a handle to a multi-dimensional array of one scalar element type that
// the host creates, binds to memory and hands to the shader as a descriptor - the
// same shape as an image or an acceleration structure, with a rank and an element
// type instead of a format and a dimensionality:
//
//   VkTensorCreateInfoARM   -> vkCreateTensorARM     (the resource itself)
//   VkTensorDescriptionARM  -> element type, dimensionCount, dimensions, strides
//   vkBindTensorMemoryARM   -> memory behind it
//   vkUpdateDescriptorSets  -> VK_DESCRIPTOR_TYPE_STORAGE_TENSOR_ARM at a binding
//
// On the shader side the extension provides a type and three operations, none of
// which HLSL has a spelling for, so they come from <vk/arm/tensors.h>:
//
//   Tensor<float, 2> t                  %t    = OpTypeTensorARM %float %uint_2
//   Coordinates<2> c = MakeCoordinates  %c    = OpTypeArray %uint %uint_2
//                                       %cc   = OpCompositeConstruct %c %uint_0 %uint_1
//   TensorRead(t, c)                    %v    = OpTensorReadARM %float %t %cc
//   TensorWrite(t, c, x)                      OpTensorWriteARM %t %cc %x   (no result)
//   TensorSize<1>(t)                    %n    = OpTensorQuerySizeARM %uint %t %uint_1
//
// The instruction numbers are 4163 (OpTypeTensorARM), 4164 (OpTensorReadARM),
// 4165 (OpTensorWriteARM) and 4166 (OpTensorQuerySizeARM); the capability is
// TensorsARM (4174). The compiler emits:
//
//   OpCapability TensorsARM
//   OpExtension "SPV_ARM_tensors"
//
// once each, derived from the tensor type itself rather than requested from the
// source, which is what makes -fspv-extension able to refuse the extension: an
// explicit -fspv-extension list that omits SPV_ARM_tensors is a compile error.
// Without an explicit list the extension is on (it is enabled by default), because
// the tensor type already ships as the operand type of every TOSA operation in
// <vk/arm/tosa.h>.
//
// ## The operand orders, which are the whole contract
//
// * The coordinates of an element are ONE operand: an id of an OpTypeArray whose
//   element type is an integer and whose length equals the tensor's rank. Not a
//   vector, and not one operand per dimension. SPIRV-Tools checks the length
//   against the rank, so a rank-2 tensor needs a two-element array - which is what
//   Coordinates<2> is, and MakeCoordinates builds it with OpCompositeConstruct.
// * OpTensorWriteARM has no result id and takes the value as an ordinary operand,
//   in third position, after the tensor and the coordinates.
// * The dimension of OpTensorQuerySizeARM must name a constant instruction, so
//   TensorSize<dimension>() takes it as a template argument; TensorSize also
//   rejects a dimension that is not smaller than the rank, which the validator
//   would otherwise report.
// * Rank and Shape: OpTypeTensorARM's Rank is the id of a 32-bit integer constant
//   and is expressible (it is what makes <vk/arm/tensors.h>'s Tensor ranked);
//   Shape is the id of an OpConstantComposite of an integer array and is not
//   expressible through the vk:: template-argument machinery, so the type is
//   ranked but unshaped. Read, write and query-size only need the rank.
//
// ## Where the tensor value in this file comes from - the honest limit
//
// VK_ARM_tensors makes a tensor a *descriptor* type, but HLSL has no resource
// spelling for it: a global of tensor type is placed in $Globals (a uniform block,
// which the compiler rejects: no host can bind a tensor there), and [vk::binding]
// on such a global is refused with "variable 'x' will be placed in $Globals so
// cannot have vk::binding attribute". A UniformConstant variable of tensor type -
// the descriptor the extension is really about - cannot be declared from HLSL yet.
// That needs a front-end feature: a resource type like RaytracingAccelerationStructure,
// or the data-graph entry point of SPV_ARM_graph. <vk/arm/tensors.h> says so in its
// header comment, and so does docs/SPIR-V.rst ("Arm tensors").
//
// So the two ways a shader can obtain a tensor handle today are both shown below:
// a TOSA operation that produces one (the first section), and an uninitialized
// local (the second). Neither is a bound descriptor, so a shader that runs reads
// whatever the implementation puts in the handle - the module is valid, the data
// is not defined by the shader.
//
// ## What the host has to do - none of it is checkable here
//
// * Enable the VK_ARM_tensors device extension and its tensor features at
//   vkCreateDevice, and query VkPhysicalDeviceTensorPropertiesARM for the limits
//   below.
// * Create the tensor with vkCreateTensorARM and bind memory to it. Its
//   VkTensorDescriptionARM::dimensionCount must be at most
//   maxTensorDimensionCount (Vulkan requires every implementation to support 4,
//   which is the largest rank this header lets a shader declare), each dimension at
//   most maxPerDimensionTensorElements, and its element type must match the element
//   type in the module.
// * Write the descriptor at the binding the pipeline layout assigns, within
//   maxDescriptorSetStorageTensors and maxPerStageDescriptor*StorageTensors. A
//   descriptor that is never written, or written with a mismatched tensor, fails at
//   pipeline creation or reads garbage; the compiler cannot see descriptors.
// * shaderTensorSupportedStages requires VK_SHADER_STAGE_COMPUTE_BIT for the tensor
//   features implemented here, so a module that uses a tensor belongs to a compute
//   pipeline, which is what this example compiles.
// * A driver without VK_ARM_tensors rejects the module: it declares the TensorsARM
//   capability and the SPV_ARM_tensors extension.
// * Nothing here is executed by any CI in this repository, so this file pins the
//   encoding, not the arithmetic.

#include <vk/arm/tensors.h>

RWByteAddressBuffer outBuf : register(u0);

// A TOSA operation declared over the *ranked* tensor type. <vk/arm/tosa.h> declares
// TOSA over an unranked OpTypeTensorARM, because one declaration then serves every
// tensor a caller has; a tensor that is going to be read with OpTensorReadARM needs
// a rank, so the operation is declared here with the ranked type as its result type.
// The set name, the string and the opcode are TOSA's: ADD is 14 in TOSA.001000.1.
// This is what "a tensor value has to come from somewhere" looks like today.
[[vk::ext_instruction(/* TOSA ADD */ 14, "TOSA.001000.1")]] vk::arm::Tensor<float, 2>
TosaAdd(vk::arm::Tensor<float, 2> lhs, vk::arm::Tensor<float, 2> rhs);

[numthreads(64, 1, 1)] void main(uint3 tid : SV_DispatchThreadID) {
  // A rank-2 tensor of floats and the coordinates of one element of it: an
  // OpTypeArray of two uints, built by OpCompositeConstruct.
  vk::arm::Tensor<float, 2> tensor;
  vk::arm::Coordinates<2> coords = vk::arm::MakeCoordinates(tid.x, tid.y);

  // Read the element at (tid.x, tid.y), write it back incremented, and ask for the
  // size of dimension 1. Nothing in the shader knows the shape of the tensor - the
  // descriptor does - so the query is the only way to learn it.
  float value = vk::arm::TensorRead(tensor, coords);       // OpTensorReadARM
  vk::arm::TensorWrite(tensor, coords, value + 1.0);       // OpTensorWriteARM
  uint width = vk::arm::TensorSize<1>(tensor);             // OpTensorQuerySizeARM

  // The first way to obtain a tensor handle: another operation produced it. The
  // result of TosaAdd is a ranked tensor, so it can be read directly.
  vk::arm::Tensor<float, 2> sum = TosaAdd(tensor, tensor);
  float element = vk::arm::TensorRead(sum, coords);

  // The results have to be observable, or the optimizer drops the reads (they are
  // pure) and the capability with them.
  outBuf.Store(tid.x * 8, asuint(value + element));
  outBuf.Store(tid.x * 8 + 4, width);
}
