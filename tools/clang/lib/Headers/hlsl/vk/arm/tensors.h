// Copyright (c) 2026 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Tensors: VK_ARM_tensors / SPV_ARM_tensors.
//
// A tensor is a handle to a multi-dimensional array of one scalar element type
// that the host creates, binds to memory and hands to the shader as a
// descriptor - the same shape as an image or an acceleration structure, with a
// rank and an element type instead of a format and a dimensionality:
//
//   #include <vk/arm/tensors.h>
//
//   using namespace vk::arm;
//   Tensor<float, 2> t = ...;              // OpTypeTensorARM %float %uint_2
//   Coordinates<2> c = MakeCoordinates(0, 1);
//   float v = TensorRead(t, c);            // OpTensorReadARM
//   TensorWrite(t, c, v + 1.0);            // OpTensorWriteARM
//   uint w = TensorSize<0>(t);             // OpTensorQuerySizeARM
//
// ## The type
//
// HLSL has no tensor type, so the type is an inline SPIR-V type built with the
// same machinery <vk/ext/long_vector.h> and <vk/arm/tosa.h> use:
//
//   Tensor<float, 2>  ->  %t = OpTypeTensorARM %float %uint_2
//
// OpTypeTensorARM (4163) takes its element type as a type operand (not as a
// result type) and its *Rank* as the id of a 32-bit integer constant, which is
// what vk::integral_constant<uint, Rank> produces. Its third operand, *Shape*,
// is the id of an OpConstantComposite of an integer array whose length equals
// Rank; the vk:: template-argument machinery can carry types and integer
// constants but not a composite constant, so Shape is not expressible here and
// the type is ranked but unshaped. SPIRV-Tools accepts that (the Shape operand
// is optional), a tensor read or write needs only the rank, and the shape of a
// tensor is a property of the descriptor the host created anyway.
//
// Rank is capped at 4: Vulkan requires every implementation that supports
// VK_ARM_tensors to report a maxTensorDimensionCount of at least 4, so 1..4 is
// the range a shader can rely on, and a higher rank is refused here (by the
// template below) and by SPIR-V CodeGen instead of compiling and then failing
// at pipeline creation.
//
// ## The operations
//
// The three operations are [[vk::ext_instruction]] declarations, so they have no
// definition anywhere and SPIR-V CodeGen emits the instruction in place of the
// call. The operand order is the instruction's, and it is not the order the
// names suggest:
//
//   TensorRead(t, c)     ->  %r = OpTensorReadARM %float %t %c
//   TensorWrite(t, c, v) ->  OpTensorWriteARM %t %c %v        (no result id)
//   TensorSize<d>(t)     ->  %r = OpTensorQuerySizeARM %uint %t %uint_<d>
//
// * *Coordinates* is an id of an OpTypeArray whose element type is an integer
//   and whose length equals the rank - not a vector, and not N separate
//   operands. Coordinates<Rank> is that type, and MakeCoordinates builds one with
//   OpCompositeConstruct (80). SPIRV-Tools checks the array length against the
//   tensor's rank, so a rank-2 tensor needs a two-element array; the overloads
//   below cover ranks 1 to 4.
// * TensorWrite returns nothing. The value written is an ordinary operand, which
//   is what distinguishes it from a form that would pass an out-parameter.
// * The *Dimension* operand of OpTensorQuerySizeARM must name a constant
//   instruction, so TensorSize takes the dimension as a template argument;
//   TensorQuerySize is available for callers that pass a constant expression.
// * The optional trailing *TensorOperands* mask (NontemporalARM,
//   OutOfBoundsValueARM, MakeElementAvailableARM, MakeElementVisibleARM,
//   NonPrivateElementARM; see SPV_ARM_tensors) is not exposed. An HLSL parameter
//   list cannot add or drop a trailing operand conditionally, and the
//   OutOfBoundsValueARM form additionally needs a value after the mask, so the
//   three declarations below emit no mask at all. A caller that needs one can
//   declare the instruction directly - the mask is a literal bit mask followed
//   by its values:
//
//     [[vk::ext_instruction(/* OpTensorReadARM */ 4164)]]
//     float ReadOutOfBounds(Tensor<float, 2> t, Coordinates<2> c,
//                           [[vk::ext_literal]] uint mask, float oob);
//
// ## Module surface
//
// OpTypeTensorARM is defined by SPV_ARM_tensors, so the *type* is what makes a
// module require OpCapability TensorsARM (4174) and
// OpExtension "SPV_ARM_tensors": SPIR-V CodeGen derives both from the type
// itself (the SpirvIntrinsicType case in CapabilityVisitor), which is what lets
// -fspv-extension select the extension and refuse it. Nothing in this header
// requests a capability or an extension directly, and including it and using
// nothing from it adds nothing to the module.
//
// SPV_ARM_tensors is enabled by default, so no command-line flag is needed;
// naming it in an explicit -fspv-extension list is accepted, and leaving it out
// of such a list is a compile error rather than a module that declares an
// extension the host never asked for. The extension adds no new requirements to
// the target environment: it is not part of any Vulkan version, and a module
// with the capability validates for vulkan1.0.
//
// ## Where a tensor value comes from
//
// This is the honest limit of the landing. VK_ARM_tensors makes a tensor a
// *descriptor* type - SPIRV-Tools lists OpTypeTensorARM next to OpTypeImage and
// OpTypeAccelerationStructureKHR among the types a UniformConstant variable may
// have - but HLSL has no resource-object spelling for it, and no way to ask for
// a UniformConstant variable of an arbitrary opaque type: a global of tensor
// type is placed in $Globals, which is a uniform block (rejected here, see
// below), and [vk::binding] on it is refused with "variable 'x' will be placed
// in $Globals so cannot have vk::binding attribute". A tensor *resource* is
// therefore not expressible from HLSL today; it needs a front-end feature (a
// new resource type like RaytracingAccelerationStructure, or a data-graph entry
// point). What a shader can do in the meantime:
//
// * Take the value from a TOSA operation: <vk/arm/tosa.h> declares every TOSA
//   operation over OpTypeTensorARM, so a ranked tensor can be produced by, or
//   passed through, an [[vk::ext_instruction]] declared with this header's type
//   as its result type.
// * Declare an uninitialized local of tensor type and load the handle from it.
//   That is a valid module (OpVariable in Function storage, OpLoad, then the
//   three operations); it is what the gates in
//   tools/clang/test/CodeGenSPIRV/arm.tensors*.hlsl compile, and the *value* of
//   the handle is whatever the implementation puts there, so a shader that does
//   this and runs is reading an undefined resource.
//
// ## What is diagnosed rather than miscompiled
//
// * A non-scalar element type (Tensor<float2, 2>): a type-alias instantiation
//   error here, and a CodeGen error for a hand-written
//   vk::SpirvOpaqueType, because SPIRV-Tools rejects
//   "OpTypeTensorARM Element Type <id> is not a scalar type".
// * A rank outside 1..4 (Tensor<float, 0>, Tensor<float, 5>): the same, with
//   the extension's rank rules and Vulkan's maxTensorDimensionCount named.
// * A tensor in stage input or output, and a tensor as a member of a uniform,
//   storage buffer or push constant block (including an HLSL global, which lands
//   in $Globals): CodeGen errors, because both validate structurally and then
//   cannot be a valid Vulkan module.
// * Use without the extension: an explicit -fspv-extension list that omits
//   SPV_ARM_tensors is a compile error naming the extension.
//
// ## What the host has to do
//
// The compiler cannot check any of this:
//
// * Create the tensor with vkCreateTensorARM, bind memory to it, and write its
//   descriptor through the usual descriptor update path; a descriptor that is
//   never written, or whose element type and rank do not match the type in the
//   module, fails at pipeline creation or reads garbage.
// * Enable the VK_ARM_tensors device extension and its tensorFeatures, and keep
//   the descriptor within the device's maxDescriptorSetStorageTensors and
//   maxPerStageDescriptor*StorageTensors limits.
// * Tensors are storage tensors: shaderTensorSupportedStages requires
//   VK_SHADER_STAGE_COMPUTE_BIT, so a module that uses one belongs to a compute
//   pipeline.
// * The rank of the descriptor (VkTensorDescriptionARM::dimensionCount) must be
//   at most maxTensorDimensionCount, and each dimension at most
//   maxPerDimensionTensorElements; this header only guarantees the first four
//   dimensions.
// * Numeric conformance is the implementation's. No CI in this repository
//   executes a tensor instruction, so the gates pin the encoding, not the
//   arithmetic.
//
// See docs/SPIR-V.rst ("Arm tensors") and
// examples/spirv-extensions/arm-tensors.hlsl.

#ifndef _HLSL_VK_ARM_TENSORS_H_
#define _HLSL_VK_ARM_TENSORS_H_

namespace vk {
namespace arm {

namespace tensors_detail {

// The element types OpTypeTensorARM accepts here. SPIRV-Tools rejects a
// non-scalar element type, so a vector or matrix is refused rather than lowered
// into a module the validator refuses. The list is the scalar types an ordinary
// HLSL shader can spell; 8-bit integers, 64-bit integers, bfloat16_t and the
// float8 encodings are not listed because VK_ARM_tensors describes a tensor with
// a VkFormat, and this header has no spelling for those formats' shader-side
// element types.
template <typename ElementType> struct IsScalarElement {
  static const bool value = false;
};
template <> struct IsScalarElement<bool> {
  static const bool value = true;
};
template <> struct IsScalarElement<int> {
  static const bool value = true;
};
template <> struct IsScalarElement<uint> {
  static const bool value = true;
};
template <> struct IsScalarElement<half> {
  static const bool value = true;
};
template <> struct IsScalarElement<min16float> {
  static const bool value = true;
};
template <> struct IsScalarElement<float> {
  static const bool value = true;
};
template <> struct IsScalarElement<double> {
  static const bool value = true;
};

// The diagnostic types. Each has a definition for `true` only, so instantiating
// one with `false` is the error, and the note names the check that failed:
//   error: implicit instantiation of undefined template
//          'vk::arm::tensors_detail::ElementTypeIsScalar<false>'
//          'vk::arm::tensors_detail::RankIsSupported<false>'
//          'vk::arm::tensors_detail::DimensionIsInRank<false>'
template <bool supported> struct ElementTypeIsScalar;
template <> struct ElementTypeIsScalar<true> {
  using ok = int;
};

template <bool supported> struct RankIsSupported;
template <> struct RankIsSupported<true> {
  using ok = int;
};

template <bool inRank> struct DimensionIsInRank;
template <> struct DimensionIsInRank<true> {
  using ok = int;
};

// A non-deduced context: `typename Identity<T>::type` is a parameter type that
// template argument deduction does not look at. The value written by TensorWrite
// is of the tensor's element type, so without this a call such as
// TensorWrite(t, c, 1.0) would deduce ElementType twice - from the literal
// (HLSL types `1.0` as literal float) and from the tensor - and fail; with it,
// ElementType comes from the tensor alone and the value converts to it.
template <typename T> struct Identity {
  using type = T;
};

} // namespace tensors_detail

// A tensor of Rank dimensions with elements of type ElementType. Lowers to
//   %t = OpTypeTensorARM %ElementType %uint_<Rank>
// Rank is an ordinary integral template parameter, so it has to be a constant;
// the two check parameters are non-deduced and exist only to reject an
// unsupported element type or rank with a front-end diagnostic.
template <typename ElementType, uint Rank,
          typename ElementTypeCheck = typename tensors_detail::ElementTypeIsScalar<
              tensors_detail::IsScalarElement<ElementType>::value>::ok,
          typename RankCheck = typename tensors_detail::RankIsSupported<
              (Rank >= 1 && Rank <= 4)>::ok>
using Tensor = vk::SpirvOpaqueType</* OpTypeTensorARM */ 4163, ElementType,
                                   vk::integral_constant<uint, Rank> >;

// The coordinates of one element of a Rank-dimensional tensor: an OpTypeArray
// of Rank unsigned integers, which is the operand type OpTensorReadARM and
// OpTensorWriteARM require (SPIRV-Tools checks both the element type and the
// length against the tensor's rank). Built with MakeCoordinates below.
template <uint Rank>
using Coordinates = vk::SpirvOpaqueType</* OpTypeArray */ 28, uint,
                                        vk::integral_constant<uint, Rank> >;

// Builds the coordinates of an element, one integer per dimension and in
// dimension order. Lowers to OpCompositeConstruct (80):
//   %c = OpCompositeConstruct %coordinates %i0 %i1
// One overload per rank this header supports, because an HLSL function
// declaration cannot take a variable number of arguments. A coordinate is an
// index into the corresponding dimension of the tensor; the implementation is
// free to check it against the descriptor's shape, and the
// OutOfBoundsValueARM tensor operand is how a shader asks for a defined value
// when it is out of range (see the file header).
[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] Coordinates<1>
MakeCoordinates(uint i0);

[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] Coordinates<2>
MakeCoordinates(uint i0, uint i1);

[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] Coordinates<3>
MakeCoordinates(uint i0, uint i1, uint i2);

[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] Coordinates<4>
MakeCoordinates(uint i0, uint i1, uint i2, uint i3);

// Reads the element at `coordinates` from the tensor. Lowers to
//   %r = OpTensorReadARM %ElementType %tensor %coordinates
// The result type is the tensor's element type; SPIRV-Tools checks the two
// agree.
template <typename ElementType, uint Rank>
[[vk::ext_instruction(/* OpTensorReadARM */ 4164)]] ElementType
TensorRead(Tensor<ElementType, Rank> tensor, Coordinates<Rank> coordinates);

// Writes `object` to the element at `coordinates`. Lowers to
//   OpTensorWriteARM %tensor %coordinates %object
// The instruction has no result id, so the function returns nothing, and the
// value is an ordinary operand - not an out-parameter. The value's type is a
// non-deduced context (`typename tensors_detail::Identity<ElementType>::type`),
// so ElementType comes from the tensor alone and a literal converts to it:
// TensorWrite(halfTensor, c, 1.0) writes a half, and the operand is an
// OpConstant of the element type.
template <typename ElementType, uint Rank>
[[vk::ext_instruction(/* OpTensorWriteARM */ 4165)]] void
TensorWrite(Tensor<ElementType, Rank> tensor, Coordinates<Rank> coordinates,
            typename tensors_detail::Identity<ElementType>::type object);

// Returns the size of dimension `dimension` of the tensor. Lowers to
//   %r = OpTensorQuerySizeARM %uint %tensor %dimension
// `dimension` must name a constant instruction (SPIRV-Tools: "Dimension must
// come from a constant instruction of scalar integer type"), so prefer
// TensorSize<dimension>() below, which takes it as a template argument.
template <typename ElementType, uint Rank>
[[vk::ext_instruction(/* OpTensorQuerySizeARM */ 4166)]] uint
TensorQuerySize(Tensor<ElementType, Rank> tensor, uint dimension);

// Returns the size of dimension Dimension of the tensor, where Dimension is a
// compile-time constant smaller than the tensor's rank. The dimension is a
// template argument, so the constant-instruction requirement of
// OpTensorQuerySizeARM cannot be missed, and a dimension outside the rank is a
// front-end diagnostic rather than a module SPIRV-Tools rejects.
template <uint Dimension, typename ElementType, uint Rank,
          typename DimensionCheck = typename tensors_detail::DimensionIsInRank<
              (Dimension < Rank)>::ok>
uint TensorSize(Tensor<ElementType, Rank> tensor) {
  return TensorQuerySize(tensor, Dimension);
}

} // namespace arm
} // namespace vk

#endif // _HLSL_VK_ARM_TENSORS_H_
