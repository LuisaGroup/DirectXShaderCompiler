// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef _HLSL_VK_KHR_COOPERATIVE_MATRIX_H_
#define _HLSL_VK_KHR_COOPERATIVE_MATRIX_H_

#if __SPIRV_MAJOR_VERSION__ == 1 && __SPIRV_MINOR_VERSION__ < 6
#error "CooperativeMatrix requires a minimum of SPIR-V 1.6"
#endif

#include <vk/spirv.h>

namespace vk {
namespace khr {

// HLSL Change Begin - SPV_KHR_bfloat16 (BFloat16CooperativeMatrixKHR).
// Drives the Matrix*SignedComponentsKHR operands of
// OpCooperativeMatrixMulAddKHR. bfloat16_t defines no arithmetic or comparison
// operators, so the subtraction/comparison probe below cannot be evaluated for
// it, and it has to be specialized. The answer for bfloat16_t is false: those
// operands may only be set when the component type of the corresponding matrix
// is an integer type.
// HLSL Change - VK_ARM_cooperative_matrix_layouts review: probe integers by
// integer division instead of by subtraction. '(T(0) - T(1) < T(0))' is also
// true for floating-point component types, which made a float/half cooperative
// matrix request the Matrix*SignedComponentsKHR operands that the validator only
// allows for integer components. Integer division truncates, so
// '((T(1) / T(2)) * T(2) == T(1)' holds only for floating-point types.
template <typename T> struct HasSignedIntegerComponentType {
  static const bool value = !((T(1) / T(2)) * T(2) == T(1));
};
template <> struct HasSignedIntegerComponentType<bfloat16_t> {
  static const bool value = false;
};
// HLSL Change End

// The base cooperative matrix class. The template arguments correspond to the
// operands in the OpTypeCooperativeMatrixKHR instruction.
template <typename ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse use>
class CooperativeMatrix {
  template <class NewComponentType>
  CooperativeMatrix<NewComponentType, scope, rows, columns, use> cast();

  // Apply OpSNegate or OFNegate, depending on ComponentType, in a element by
  // element manner.
  CooperativeMatrix negate();

  // Apply OpIAdd or OFAdd, depending on ComponentType, in a element by element
  // manner.
  CooperativeMatrix operator+(CooperativeMatrix other);

  // Apply OpISub or OFSub, depending on ComponentType, in a element by element
  // manner.
  CooperativeMatrix operator-(CooperativeMatrix other);

  // Apply OpIMul or OFMul, depending on ComponentType, in a element by element
  // manner.
  CooperativeMatrix operator*(CooperativeMatrix other);

  // Apply OpSDiv, OpUDiv or OFDiv, depending on ComponentType, in a element by
  // element manner.
  CooperativeMatrix operator/(CooperativeMatrix other);

  // Apply OpMatrixTimesScalar in a element by element manner.
  CooperativeMatrix operator*(ComponentType scalar);

  // Store the cooperative matrix using OpCooperativeMatrixStoreKHR to
  // data using the given memory layout, stride, and memory access operands.
  // `NonPrivatePointer` and `MakePointerAvailable` with the workgroup scope
  // will be added to the memory access operands to make the memory coherent.
  //
  // This function uses a SPIR-V pointer because HLSL does not allow groupshared
  // memory object to be passed by reference. The pointer is a hack to get
  // around that.
  //
  // The layout and stride will be passed to the SPIR-V instruction as is. The
  // precise meaning can be found in the specification for
  // SPV_KHR_cooperative_matrix.
  template <uint32_t memoryAccessOperands, CooperativeMatrixLayout layout,
            class Type>
  void Store(WorkgroupSpirvPointer<Type> data, uint32_t stride);

  // Same as above, but uses MemoryAccessMaskNone for the memory access
  // operands.
  template <CooperativeMatrixLayout layout, class Type>
  void Store(WorkgroupSpirvPointer<Type> data, uint32_t stride) {
    Store<MemoryAccessMaskNone, layout>(data, stride);
  }

  // Store the cooperative matrix using OpCooperativeMatrixStoreKHR to
  // data[index] using the given memory layout, stride, and memory access
  // operands. The layout and stride will be passed to the SPIR-V instruction as
  // is. The precise meaning can be found in the specification for
  // SPV_KHR_cooperative_matrix.
  template <uint32_t memoryAccessOperands, CooperativeMatrixLayout layout,
            class Type>
  void Store(RWStructuredBuffer<Type> data, uint32_t index, uint32_t stride);

  // Same as above, but uses MemoryAccessMaskNone for the memory access
  // operands.
  template <CooperativeMatrixLayout layout, class Type>
  void Store(RWStructuredBuffer<Type> data, uint32_t index, uint32_t stride) {
    Store<MemoryAccessMaskNone, layout>(data, index, stride);
  }

  // Store the cooperative matrix using OpCooperativeMatrixStoreKHR to
  // data[index] using the given memory layout, stride, and memory access
  // operands. `NonPrivatePointer` and `MakePointerAvailable` with the
  // QueueFamily scope will be added to the memory access operands to make the
  // memory coherent.
  //
  // The layout and stride will be passed to the SPIR-V instruction as is. The
  // precise meaning can be found in the specification for
  // SPV_KHR_cooperative_matrix.
  template <uint32_t memoryAccessOperands, CooperativeMatrixLayout layout,
            class Type>
  void CoherentStore(globallycoherent RWStructuredBuffer<Type> data,
                     uint32_t index, uint32_t stride);

  // Same as above, but uses MemoryAccessMaskNone for the memory access operands
  // template argument.
  template <CooperativeMatrixLayout layout, class Type>
  void CoherentStore(globallycoherent RWStructuredBuffer<Type> data,
                     uint32_t index, uint32_t stride) {
    CoherentStore<MemoryAccessMaskNone, layout>(data, index, stride);
  }

  // Loads a cooperative matrix using OpCooperativeMatrixLoadKHR from
  // data using the given memory layout, stride, and memory access operands.
  // `NonPrivatePointer` and `MakePointerVisible` with the workgroup scope
  // will be added to the memory access operands to make the memory coherent.
  //
  // This function uses a SPIR-V pointer because HLSL does not allow groupshared
  // memory object to be passed by reference. The pointer is a hack to get
  // around that.
  //
  // The layout and stride will be passed to the SPIR-V instruction as is. The
  // precise meaning can be found in the specification for
  // SPV_KHR_cooperative_matrix.
  template <uint32_t memoryAccessOperands, CooperativeMatrixLayout layout,
            class Type>
  static CooperativeMatrix Load(WorkgroupSpirvPointer<Type> data,
                                uint32_t stride);

  // Same as above, but uses MemoryAccessMaskNone for the memory access
  // operands.
  template <CooperativeMatrixLayout layout, class Type>
  static CooperativeMatrix Load(WorkgroupSpirvPointer<Type> data,
                                uint32_t stride) {
    return Load<MemoryAccessMaskNone, layout>(data, stride);
  }

  // Loads a cooperative matrix using OpCooperativeMatrixLoadKHR from
  // data[index] using the given memory layout, stride, and memory access
  // operands.
  //
  // The layout and stride will be passed to the SPIR-V instruction as is. The
  // precise meaning can be found in the specification for
  // SPV_KHR_cooperative_matrix.
  template <uint32_t memoryAccessOperands, CooperativeMatrixLayout layout,
            class Type>
  static CooperativeMatrix Load(RWStructuredBuffer<Type> data, uint32_t index,
                                uint32_t stride);

  // Same as above, but uses MemoryAccessMaskNone for the memory access
  // operands.
  template <CooperativeMatrixLayout layout, class Type>
  static CooperativeMatrix Load(RWStructuredBuffer<Type> data, uint32_t index,
                                uint32_t stride) {
    return Load<MemoryAccessMaskNone, layout>(data, index, stride);
  }

  // Loads a cooperative matrix using OpCooperativeMatrixLoadKHR from
  // data[index] using the given memory layout, stride, and memory access
  // operands. `NonPrivatePointer` and `MakePointerVisible` with the QueueFamily
  // scope will be added to the memory access operands to make the memory
  // coherent.
  //
  //
  // The layout and stride will be passed to the SPIR-V instruction as is. The
  // precise meaning can be found in the specification for
  // SPV_KHR_cooperative_matrix.
  template <uint32_t memoryAccessOperands, CooperativeMatrixLayout layout,
            class Type>
  static CooperativeMatrix
  CoherentLoad(globallycoherent RWStructuredBuffer<Type> data, uint32_t index,
               uint32_t stride);

  // Same as above, but uses MemoryAccessMaskNone for the memory access operands
  // template argument.
  template <CooperativeMatrixLayout layout, class Type>
  static CooperativeMatrix
  CoherentLoad(globallycoherent RWStructuredBuffer<Type> data, uint32_t index,
               uint32_t stride) {
    return CoherentLoad<MemoryAccessMaskNone, layout>(data, index, stride);
  }

  // Loads a cooperative matrix using OpCooperativeMatrixLoadKHR from
  // data[index] using the given memory layout, stride, and memory access
  // operands. No memory access bits are added to the operands. Since the memory
  // is readonly, there should be no need.
  //
  // The layout and stride will be passed to the SPIR-V instruction as is. The
  // precise meaning can be found in the specification for
  // SPV_KHR_cooperative_matrix.
  template <uint32_t memoryAccessOperands, CooperativeMatrixLayout layout,
            class Type>
  static CooperativeMatrix Load(StructuredBuffer<Type> data, uint32_t index,
                                uint32_t stride);

  // Same as above, but uses MemoryAccessMaskNone for the memory access
  // operands.
  template <CooperativeMatrixLayout layout, class Type>
  static CooperativeMatrix Load(StructuredBuffer<Type> data, uint32_t index,
                                uint32_t stride) {
    return Load<MemoryAccessMaskNone, layout>(data, index, stride);
  }

  // HLSL Change Begin - SPV_ARM_cooperative_matrix_layouts.
  //
  // The blocked-interleaved Arm memory layouts (RowBlockedInterleavedARM and
  // ColumnBlockedInterleavedARM) have their own entry points because their
  // Stride operand must come from a *constant* instruction, which a Stride
  // passed as a function argument can never be: every HLSL parameter is lowered
  // to a pointer and read back with OpLoad. Here the stride is a template
  // argument instead, so it reaches OpCooperativeMatrixLoadKHR /
  // OpCooperativeMatrixStoreKHR as an OpConstant, and the (layout, stride,
  // rows, columns) combination is checked at compile time. The definitions live
  // in <vk/arm/cooperative_matrix_layouts.h>, which include that header.
  //
  // Loads a cooperative matrix using OpCooperativeMatrixLoadKHR with one of the
  // two Arm memory layouts. No memory access bits are added to the operands.
  template <CooperativeMatrixLayout layout, uint32_t stride, class Type>
  static CooperativeMatrix LoadBlockedInterleaved(StructuredBuffer<Type> data,
                                                  uint32_t index);

  // As above, reading from a writable structured buffer.
  template <CooperativeMatrixLayout layout, uint32_t stride, class Type>
  static CooperativeMatrix LoadBlockedInterleaved(RWStructuredBuffer<Type> data,
                                                  uint32_t index);

  // As above, reading from workgroup memory. `NonPrivatePointer` and
  // `MakePointerVisible` with the workgroup scope are added to the memory
  // access operands to make the memory coherent.
  template <CooperativeMatrixLayout layout, uint32_t stride, class Type>
  static CooperativeMatrix LoadBlockedInterleaved(
      WorkgroupSpirvPointer<Type> data);

  // Stores the cooperative matrix using OpCooperativeMatrixStoreKHR with one of
  // the two Arm memory layouts. No memory access bits are added to the
  // operands.
  template <CooperativeMatrixLayout layout, uint32_t stride, class Type>
  void StoreBlockedInterleaved(RWStructuredBuffer<Type> data, uint32_t index);

  // As above, writing to workgroup memory. `NonPrivatePointer` and
  // `MakePointerAvailable` with the workgroup scope are added to the memory
  // access operands to make the memory coherent.
  template <CooperativeMatrixLayout layout, uint32_t stride, class Type>
  void StoreBlockedInterleaved(WorkgroupSpirvPointer<Type> data);
  // HLSL Change End

  // Constructs a cooperative matrix with all values initialized to v. Note that
  // all threads in scope must have the same value for v.
  static CooperativeMatrix Splat(ComponentType v);

  // Returns the result of OpCooperativeMatrixLengthKHR on the current type.￼
  static uint32_t GetLength();

  // Functions to access the elements of the cooperative matrix. The index must
  // be less than GetLength().
  void Set(ComponentType value, uint32_t index);
  ComponentType Get(uint32_t index);

  // HLSL Change Begin - SPV_EXT_cooperative_matrix_maintenance1.
  // Conversions, reductions, per-element operations and index-to-coordinate
  // conversion: VK_EXT_cooperative_matrix_maintenance1 /
  // SPV_EXT_cooperative_matrix_maintenance1. Each of the four entry points below
  // emits one of the extension's four instructions together with its capability
  // (CooperativeMatrixConversionsEXT 5429, CooperativeMatrixReductionsEXT 5430,
  // CooperativeMatrixPerElementOperationsEXT 5432,
  // CooperativeMatrixGetCoordinateEXT 5438) and
  // OpExtension "SPV_EXT_cooperative_matrix_maintenance1". The extension is
  // registered in FeatureManager, so an explicit -fspv-extension= list that
  // leaves it out reports a diagnostic instead of emitting an instruction whose
  // capability the module is not allowed to declare.
  //
  // Reinterprets the same matrix with a different CooperativeMatrixUse. The
  // component type, the scope, the rows and the columns are unchanged - only the
  // use changes - because OpCooperativeMatrixConvertUseEXT requires the two types
  // to have the same shape (external/SPIRV-Tools
  // CooperativeMatrixShapesMatch), and it requires the conversion to go between
  // MatrixAccumulatorKHR and MatrixAKHR / MatrixBKHR. Any other pairing is a
  // compile error (vk::khr::ConvertUseIsSupported<false>).
  // Lowers to OpCooperativeMatrixConvertUseEXT (5293).
  template <CooperativeMatrixUse newUse>
  CooperativeMatrix<ComponentType, scope, rows, columns, newUse> ConvertUse();

  // Reduces this matrix to `newRows` x `newColumns`. `mode` is a
  // CooperativeMatrixReduceMode value - CooperativeMatrixReduceRow,
  // CooperativeMatrixReduceColumn, CooperativeMatrixReduceRow |
  // CooperativeMatrixReduceColumn (a full reduction, which leaves 1x1) or
  // CooperativeMatrixReduce2x2 - and it has to be a compile-time constant: the
  // CooperativeMatrixReduce operand of the instruction is a literal, so a
  // run-time mode cannot be encoded. Passing one is a compile error, as is a
  // result shape that does not match the mode or a matrix whose use is not
  // MatrixAccumulatorKHR (vk::khr::ReduceIsSupported<false>).
  // Lowers to OpCooperativeMatrixReduceEXT (5366) with a compiler-synthesized
  // combine function.
  template <uint newRows, uint newColumns, uint mode>
  CooperativeMatrix<ComponentType, scope, newRows, newColumns,
                    CooperativeMatrixUseMatrixAccumulatorKHR>
  Reduce();

  // Never a valid call: it exists so that Reduce<rows, columns>(mode) - passing
  // the mode as a run-time argument instead of as the third template argument -
  // reports "implicit instantiation of undefined template
  // 'vk::khr::ReduceModeMustBeAConstant<false>'" instead of "no matching member
  // function for call to 'Reduce'". The CooperativeMatrixReduce operand of
  // OpCooperativeMatrixReduceEXT is a literal, so only a constant can be
  // encoded.
  template <uint newRows, uint newColumns>
  CooperativeMatrix<ComponentType, scope, newRows, newColumns,
                    CooperativeMatrixUseMatrixAccumulatorKHR>
  Reduce(uint32_t mode);

  // Applies a per-element operation to every element. The result has the same
  // type as the source: OpCooperativeMatrixPerElementOpEXT requires the result
  // type and the matrix type to be identical.
  // Lowers to OpCooperativeMatrixPerElementOpEXT (5369) with a
  // compiler-synthesized per-element function.
  CooperativeMatrix PerElementOp();

  // Maps element `index` of this matrix to the coordinate of the same element in
  // the source matrix of a different use, as a two-component 32-bit integer
  // vector. The index must be less than GetLength().
  // Lowers to OpCooperativeMatrixGetCoordinateEXT (5363).
  uint2 GetCoordinate(uint32_t index);
  // HLSL Change End - SPV_EXT_cooperative_matrix_maintenance1.

  // HLSL Change - SPV_KHR_bfloat16: the probe is routed through a trait so
  // that it can be specialized for bfloat16_t, which has no operators.
  static const bool hasSignedIntegerComponentType =
      HasSignedIntegerComponentType<ComponentType>::value;

  // clang-format off
  using SpirvMatrixType = vk::SpirvOpaqueType<
      /* OpTypeCooperativeMatrixKHR */ 4456, ComponentType,
      vk::integral_constant<uint, scope>, vk::integral_constant<uint, rows>,
      vk::integral_constant<uint, columns>, vk::integral_constant<uint, use> >;

  [[vk::ext_extension("SPV_KHR_cooperative_matrix")]]
  [[vk::ext_capability(/* CooperativeMatrixKHRCapability */ 6022)]]
  [[vk::ext_capability(/* VulkanMemoryModel */ 5345)]]
  SpirvMatrixType _matrix;
  // clang-format on
};

// Cooperative matrix that can be used in the "a" position of a multiply add
// instruction (r = (a * b) + c).
template <typename ComponentType, Scope scope, uint rows, uint columns>
using CooperativeMatrixA =
    CooperativeMatrix<ComponentType, scope, rows, columns,
                      CooperativeMatrixUseMatrixAKHR>;

// Cooperative matrix that can be used in the "b" position of a multiply add
// instruction (r = (a * b) + c).
template <typename ComponentType, Scope scope, uint rows, uint columns>
using CooperativeMatrixB =
    CooperativeMatrix<ComponentType, scope, rows, columns,
                      CooperativeMatrixUseMatrixBKHR>;

// Cooperative matrix that can be used in the "r" and "c" position of a multiply
// add instruction (r = (a * b) + c).
template <typename ComponentType, Scope scope, uint rows, uint columns>
using CooperativeMatrixAccumulator =
    CooperativeMatrix<ComponentType, scope, rows, columns,
                      CooperativeMatrixUseMatrixAccumulatorKHR>;

// Returns the result of OpCooperativeMatrixMulAddKHR when applied to a, b, and
// c. The cooperative matrix operands are inferred, with the
// SaturatingAccumulationKHR bit not set.
template <typename ComponentType, Scope scope, uint rows, uint columns, uint K>
CooperativeMatrixAccumulator<ComponentType, scope, rows, columns>
cooperativeMatrixMultiplyAdd(
    CooperativeMatrixA<ComponentType, scope, rows, K> a,
    CooperativeMatrixB<ComponentType, scope, K, columns> b,
    CooperativeMatrixAccumulator<ComponentType, scope, rows, columns> c);

// Returns the result of OpCooperativeMatrixMulAddKHR when applied to a, b, and
// c. The cooperative matrix operands are inferred, with the
// SaturatingAccumulationKHR bit set.
template <typename ComponentType, Scope scope, uint rows, uint columns, uint K>
CooperativeMatrixAccumulator<ComponentType, scope, rows, columns>
cooperativeMatrixSaturatingMultiplyAdd(
    CooperativeMatrixA<ComponentType, scope, rows, K> a,
    CooperativeMatrixB<ComponentType, scope, K, columns> b,
    CooperativeMatrixAccumulator<ComponentType, scope, rows, columns> c);

} // namespace khr
} // namespace vk

#include <vk/khr/cooperative_matrix.impl>
#endif // _HLSL_VK_KHR_COOPERATIVE_MATRIX_H_
