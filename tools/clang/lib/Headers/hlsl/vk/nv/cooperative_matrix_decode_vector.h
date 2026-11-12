// Copyright (c) 2026 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Cooperative-matrix block loads through a decode function:
// VK_NV_cooperative_matrix_decode_vector /
// SPV_NV_cooperative_matrix_decode_vector.
//
// A cooperative matrix can be loaded from a *tensor* with
// OpCooperativeMatrixLoadTensorNV (5367, SPV_NV_cooperative_matrix2). Its
// trailing TensorAddressingOperands operand is a bit mask followed by one operand
// per set bit; SPV_NV_cooperative_matrix_decode_vector adds the DecodeVectorFunc
// bit (0x0004), whose operand names a function that decodes a *vector* of
// block-adjacent elements in one call instead of the single scalar element the
// DecodeFunc bit (0x0002) decodes.
//
//     %m  = OpCooperativeMatrixLoadTensorNV %mat %ptr %object %layout None
//           DecodeFunc|DecodeVectorFunc %decode_scalar %decode_vector
//
//    #include <vk/nv/cooperative_matrix_decode_vector.h>
//
//    using Mat = vk::khr::CooperativeMatrixA<half, vk::ScopeWorkgroup, 16, 16>;
//    groupshared half g_data[256];
//    using Layout = vk::nv::TensorLayout<2, vk::nv::TensorClampModeClampToEdge>;
//
//    Layout layout = vk::nv::CreateTensorLayout<2,
//                                               vk::nv::TensorClampModeClampToEdge>();
//    Mat m = vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV<4>(
//        g_data, source, layout);
//
// What this header provides:
// * vk::nv::TensorLayout, the OpTypeTensorLayoutNV (5370) *type*. Both of its
//   operands are <id>s in the grammar snapshot this tree vendors
//   (external/SPIRV-Headers, spirv.core.grammar.json: "Dim" and "ClampMode" are
//   both IdRef), and SPIRV-Tools dereferences both
//   (ValidateTypeTensorLayoutNV: "OpTypeTensorLayoutNV Dim <id> ... is not a
//   32-bit integer", "... ClampMode <id> ..."), so both are written as
//   vk::integral_constant<uint, N> - an <id> of an OpConstant - and not as
//   literals. Dim must be between 1 and 5 and ClampMode must be one of the five
//   TensorClampMode enumerators; both are checked by SPIR-V CodeGen.
// * vk::nv::CreateTensorLayout, a [[vk::ext_instruction]] wrapper for
//   OpCreateTensorLayoutNV (5372): "OpCreateTensorLayoutNV %layout" with no
//   operands, producing the value the load takes as its TensorLayout operand.
// * vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV, the block load itself.
//   It is a compiler builtin rather than a header function template with a
//   friendlier name because the pointer operand has to keep its Workgroup or
//   StorageBuffer storage class: a wrapper function would leave the load inside
//   that wrapper, where the pointer is a Function-storage parameter, and SPIRV-Tools
//   rejects a module whose load pointer is not Workgroup, StorageBuffer or
//   PhysicalStorageBuffer.
//
// The decode functions are *compiler builtins*, not [[vk::ext_instruction]]
// wrappers, for the same reason <vk/khr/cooperative_matrix.h> declares
// __builtin_spv_CooperativeMatrixReduceEXT that way: the DecodeFunc and
// DecodeVectorFunc operands are the <id>s of *functions*, and SPIR-V has no
// operand form that can name an HLSL function. SPIR-V CodeGen synthesizes the
// pair and passes their ids, which is exactly what the extension asks for:
//   %decode_scalar = OpFunction %f16 None %functy_f16
//   %decode_vector = OpFunction %v4f16 None %functy_v4f16
// Because the two functions return OpUndef, only the encoding is defined - HLSL
// cannot express the decode itself yet. This is the same limitation the scalar
// DecodeFunc form already has in this tree (docs/SPIR-V.rst, "NV cooperative
// matrix decode vector").
//
// Why the functions have the signature they have
// (external/SPIRV-Tools, ValidateCooperativeMatrixLoadStoreTensorNV):
// * DecodeFunc returns the matrix *component type*; DecodeVectorFunc returns a
//   vector of it whose length is 2, 4 or 8. DecodeVectorFunc additionally
//   requires DecodeFunc to be present, so both operands are always emitted and
//   this header has no scalar-only form ("DecodeVectorFunc requires DecodeFunc to
//   also be specified").
// * The first parameter must be a pointer in the PhysicalStorageBuffer storage
//   class ("first parameter must be pointer to PhysicalStorageBuffer"). SPIR-V
//   CodeGen adds OpCapability PhysicalStorageBufferAddresses and
//   OpExtension "SPV_KHR_physical_storage_buffer" from the pointer type itself
//   (CapabilityVisitor::addCapabilityForType), and the capability promotes the
//   module's addressing model to PhysicalStorageBuffer64, so the memory model of
//   the module becomes OpMemoryModel PhysicalStorageBuffer64 Vulkan rather than
//   Logical GLSL450. The capability trimmer drops the extension string for a
//   Vulkan 1.2+ target, where the extension is core; -fcgl shows the module
//   before that pass.
// * The second and third parameters must be arrays of 32-bit integers whose
//   length equals the Dim of the tensor layout ("second/third parameter must be
//   array of 32-bit integer with dimension equal to the tensor dimension"), which
//   is where the Dim template argument of TensorLayout is used.
//
// The decode-vector width: the first template argument of
// __builtin_spv_CooperativeMatrixLoadTensorNV selects the
// length of the vector the synthesized function returns. 2 and 4 are provided; 8
// is legal SPIR-V but needs OpCapability LongVectorEXT for the OpTypeVector with
// eight components (SPV_EXT_long_vector, see <vk/ext/long_vector.h>), which this
// header does not request.
//
// Module surface:
// * OpExtension "SPV_NV_cooperative_matrix_decode_vector" and
//   OpCapability CooperativeMatrixDecodeVectorNV (5447) plus its prerequisite
//   CooperativeMatrixBlockLoadsNV (5434) are added by SPIR-V CodeGen from the
//   instruction (CapabilityVisitor), not by [[vk::ext_capability]] /
//   [[vk::ext_extension]] on the declarations below: those attributes write the
//   capability and the extension string unconditionally, so -fspv-extension could
//   neither select nor refuse them. The extension is opt-in; see
//   FeatureManager::enabledByDefault.
// * The base of the instruction, SPV_NV_cooperative_matrix2, is not optional:
//   OpCooperativeMatrixLoadTensorNV (5367), OpTypeTensorLayoutNV (5370),
//   OpCreateTensorLayoutNV (5372), OpCapability CooperativeMatrixTensorAddressingNV
//   (5433) and CooperativeMatrixBlockLoadsNV (5434) are all defined by it, and
//   OpTypeTensorLayoutNV additionally needs OpCapability TensorAddressingNV (5439)
//   from SPV_NV_tensor_addressing. All of them are emitted whenever this header is
//   used, and all of them have to be listed with -fspv-extension as well when an
//   explicit list is given.
// * A cooperative matrix needs SPIR-V 1.6 (<vk/khr/cooperative_matrix.h> raises
//   #error below that), so the target environment has to be at least
//   -fspv-target-env=vulkan1.3, as for every other cooperative matrix feature.
//
// Known gaps, documented rather than miscompiled:
// * Only the tensor form of the load is provided. OpCooperativeMatrixLoadTensorNV
//   *without* TensorAddressingOperands, and the store
//   (OpCooperativeMatrixStoreTensorNV, 5368, which SPIRV-Tools rejects together
//   with DecodeFunc / DecodeVectorFunc: "OpCooperativeMatrixStoreTensorNV does not
//   support DecodeFunc or DecodeVectorFunc"), are separate pieces of surface.
// * The synthesized decode functions return OpUndef, so a shader built with this
//   header is a valid *encoding* of the decode-vector load and nothing more.
// * bfloat16_t components are not accepted: the component type is checked by
//   SPIR-V CodeGen and bfloat16_t would additionally need BFloat16TypeKHR for the
//   OpTypeVector of the decode-vector function.
// * A groupshared array is the shape that produces the pointer operand the
//   validator accepts (Workgroup, StorageBuffer or PhysicalStorageBuffer). A
//   function-local array argument has the right shape with the wrong storage
//   class, which the front end cannot see through [[vk::ext_reference]]; SPIRV-Tools
//   rejects that module.
//
// Required from the host - the compiler cannot check any of this:
// * the VK_NV_cooperative_matrix_decode_vector device extension, and the
//   cooperativeMatrixDecodeVector feature bit it adds,
// * VK_NV_cooperative_matrix2 (SPV_NV_cooperative_matrix2) and VK_NV_tensor_addressing
//   (SPV_NV_tensor_addressing) with their feature bits, since the base instruction
//   comes from them,
// * VK_KHR_cooperative_matrix with the cooperative matrix properties of the stage,
//   as for every cooperative matrix feature,
// * VK_KHR_buffer_device_address / physical storage buffer support: the decode
//   function's first parameter is a PhysicalStorageBuffer pointer,
// * the maximum vector length and the tensor dimensions the device reports, and the
//   clamp mode it supports. A shader that exceeds them still compiles and fails
//   pipeline creation.
//
// See docs/SPIR-V.rst ("NV cooperative matrix decode vector") and
// examples/spirv-extensions/nv-cooperative-matrix-decode-vector.hlsl.

#ifndef _HLSL_VK_NV_COOPERATIVE_MATRIX_DECODE_VECTOR_H_
#define _HLSL_VK_NV_COOPERATIVE_MATRIX_DECODE_VECTOR_H_

#include <vk/khr/cooperative_matrix.h>
#include <vk/spirv.h>

namespace vk {
namespace nv {

// The TensorClampMode operand of OpTypeTensorLayoutNV (5370). It is an <id> of a
// 32-bit integer constant in the encoding SPIRV-Tools accepts, not a literal, so
// the enumerators double as the values to pass to TensorLayout's template
// argument. 0 (Undefined) and values above 4 (RepeatMirrored) are rejected by the
// validator, and diagnosed by SPIR-V CodeGen.
enum TensorClampMode {
  TensorClampModeUndefined = 0,
  TensorClampModeConstant = 1,
  TensorClampModeClampToEdge = 2,
  TensorClampModeRepeat = 3,
  TensorClampModeRepeatMirrored = 4,
};

// The TensorAddressingOperands bit mask of OpCooperativeMatrixLoadTensorNV
// (5367) and OpCooperativeMatrixStoreTensorNV (5368). Only the two decode
// function bits are named here: this header always emits
// DecodeFunc|DecodeVectorFunc, because the validator requires DecodeFunc whenever
// DecodeVectorFunc is set.
enum TensorAddressingOperandsMask {
  TensorAddressingOperandsMaskNone = 0,
  TensorAddressingOperandsTensorViewMask = 0x00000001,
  TensorAddressingOperandsDecodeFuncMask = 0x00000002,
  TensorAddressingOperandsDecodeVectorFuncMask = 0x00000004,
};

// A tensor layout, i.e. %layout = OpTypeTensorLayoutNV %dim %clampMode
// (OpTypeTensorLayoutNV, 5370), where both operands are the <id>s of 32-bit
// integer constants. The layout describes how a cooperative matrix is laid out in
// the tensor memory a block load reads.
template <uint dim, uint clampMode>
using TensorLayout = vk::SpirvOpaqueType</* OpTypeTensorLayoutNV */ 5370,
                                       vk::integral_constant<uint, dim>,
                                       vk::integral_constant<uint, clampMode> >;

// Creates a tensor layout value: %tl = OpCreateTensorLayoutNV %layout
// (OpCreateTensorLayoutNV, 5372 - the Result Type is the whole instruction, the
// opcode has no operands). The value is what
// OpCooperativeMatrixLoadTensorNV takes as its TensorLayout operand.
template <uint dim, uint clampMode>
[[vk::ext_instruction(/* OpCreateTensorLayoutNV */ 5372)]] TensorLayout<dim, clampMode>
CreateTensorLayout();

// Loads a cooperative matrix block through a decode function *pair*:
//
//   %m = OpCooperativeMatrixLoadTensorNV %mat %data %source %layout None
//        DecodeFunc|DecodeVectorFunc %decode_scalar %decode_vector
//
// Operands, in the instruction's order: the pointer the block is read from
// (`data`, a [[vk::ext_reference]] parameter so that it stays a pointer),
// the source cooperative matrix (`source`), and the tensor layout. The
// MemoryAccess operand is MaskNone (there is no overload with it yet), and the
// TensorAddressingOperands operand is the pair of synthesized functions
// described at the top of this file.
//
// vectorLength is the length of the vector the synthesized DecodeVectorFunc
// function returns; only 2 and 4 are accepted. It is a template argument and not
// a parameter because SPIR-V has no operand for it: the operand is the function,
// and the length is part of that function's return type. A wrong length is a
// compile error, and nothing extra is added to the instruction.
template <uint vectorLength, uint dim, uint clampMode, class MatrixType,
          class DataType>
MatrixType __builtin_spv_CooperativeMatrixLoadTensorNV(
    [[vk::ext_reference]] DataType data, MatrixType source,
    TensorLayout<dim, clampMode> layout);
} // namespace nv
} // namespace vk

#endif // _HLSL_VK_NV_COOPERATIVE_MATRIX_DECODE_VECTOR_H_
