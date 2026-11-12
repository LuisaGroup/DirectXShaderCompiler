// Copyright (c) 2026 The DirectX Shader Compiler authors
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Arm cooperative matrix memory layouts:
// VK_ARM_cooperative_matrix_layouts / SPV_ARM_cooperative_matrix_layouts.
//
// SPV_ARM_cooperative_matrix_layouts adds two MemoryLayout enumerants to
// OpCooperativeMatrixLoadKHR and OpCooperativeMatrixStoreKHR:
//
//   4202 RowBlockedInterleavedARM
//   4203 ColumnBlockedInterleavedARM
//
// and the CooperativeMatrixLayoutsARM (4201) capability, which implicitly
// declares CooperativeMatrixKHR. A module that uses either enumerant declares
// both the capability and OpExtension "SPV_ARM_cooperative_matrix_layouts";
// CodeGen does that automatically from the MemoryLayout operand of the
// instruction (CapabilityVisitor), and -fspv-extension=SPV_ARM_cooperative_matrix_layouts
// is only needed to make the extension explicit in a restricted allow-list.
//
// The memory layouts
// ------------------
// Both layouts arrange the matrix in 64-byte *blocks*. A block holds a
// sub-matrix of 4 rows and 16 / sizeof(ComponentType) columns - 4 rows *
// (16 / sizeof(ComponentType)) columns * sizeof(ComponentType) bytes = 64 bytes
// - stored in row-major order inside the block. What differs is how the blocks
// themselves are ordered:
//
//   RowBlockedInterleavedARM     blocks in row-major order
//   ColumnBlockedInterleavedARM  blocks in column-major order
//
// and, in both, blocks are interleaved at a 4-byte granularity in groups whose
// size is the *Stride* operand of the load or store.
//
// The Stride operand
// ------------------
// For RowMajorKHR (0) and ColumnMajorKHR (1), Stride is a byte stride: the
// distance between the starts of two consecutive rows (row-major) or columns
// (column-major) and nothing else. For the two Arm layouts it is the
// *interleaving group size*, counted in blocks, and it may only be 1, 2 or 4.
// The extension also requires it to come from a constant instruction, and it
// requires the MemoryLayout operand itself to be a constant instruction.
//
// Because DXC lowers every HLSL function parameter to a pointer and reads it
// back with OpLoad, a Stride passed as a run-time argument can never satisfy
// that rule. The Arm layouts are therefore only reachable through entry points
// that take the stride as a template argument:
//
//   CooperativeMatrix<...>::LoadBlockedInterleaved<layout, stride>(buffer, index)
//   CooperativeMatrix<...>::StoreBlockedInterleaved<layout, stride>(buffer, index)
//
// which pass it to the instruction as an OpConstant. Passing an Arm layout to
// the ordinary Load/Store entry points, which take the stride as an argument, is
// rejected at compile time.
//
// The shape and stride rules
// --------------------------
// SPV_ARM_cooperative_matrix_layouts, Validation Rules, and
// external/SPIRV-Tools/source/val/validate_memory.cpp:
//
//   * Stride must be 1, 2 or 4.
//   * RowBlockedInterleavedARM: Rows must be a multiple of 4 and Columns a
//     multiple of (16 / sizeof(ComponentType)) * Stride.
//   * ColumnBlockedInterleavedARM: Rows must be a multiple of 4 * Stride and
//     Columns a multiple of 16 / sizeof(ComponentType).
//
// The "multiple of 4 rows / 16 bytes of columns" part says that the matrix has
// to tile exactly into whole blocks; the Stride factor says that a row (or
// column) of blocks has to contain whole interleaving groups.
//
// BlockedInterleavedLayout below expresses those rules, and
// LoadBlockedInterleaved / StoreBlockedInterleaved instantiate it: an
// unsupported combination is a compile-time error rather than SPIR-V that
// spirv-val rejects. There is no run-time cost - the checks exist only while
// compiling.
//
// Notes and limitations (see docs/SPIR-V.rst):
// - sizeof(ComponentType) is the size the compiler gives the component type,
//   which is what the emitted OpTypeCooperativeMatrixKHR carries. With the
//   default (min-precision) settings `half` is 4 bytes wide, so a
//   `CooperativeMatrix<half, ...>` needs the same shapes as a `float` one;
//   -enable-16bit-types makes it 2 bytes wide and halves the block width.
// - A host must expose VK_ARM_cooperative_matrix_layouts in
//   VkPhysicalDeviceCooperativeMatrixPropertiesKHR before either layout is
//   accepted, and the matrix shapes it accepts are device specific. The compiler
//   cannot check either.
// - SPV_ARM_cooperative_matrix_layouts is written against SPIR-V 1.6 and
//   requires SPV_KHR_cooperative_matrix, which <vk/khr/cooperative_matrix.h>
//   already requires.

#ifndef _HLSL_VK_ARM_COOPERATIVE_MATRIX_LAYOUTS_H_
#define _HLSL_VK_ARM_COOPERATIVE_MATRIX_LAYOUTS_H_

#include <vk/khr/cooperative_matrix.h>

namespace vk {
namespace arm {

// True when (layout, stride, rows, columns) is a combination
// SPV_ARM_cooperative_matrix_layouts accepts for a cooperative matrix whose
// component type is ComponentType. `BlockedInterleavedLayoutIsSupported<
// BlockedInterleavedLayout<...>::supported>` is the diagnostic that reports the
// `false` case; see <vk/khr/cooperative_matrix.impl>.
template <CooperativeMatrixLayout layout, uint32_t stride,
          typename ComponentType, uint32_t rows, uint32_t columns>
struct BlockedInterleavedLayout {
  // Number of matrix columns covered by one 64-byte block.
  static const uint32_t blockColumns = 16u / sizeof(ComponentType);

  static const bool rowBlocked =
      layout == CooperativeMatrixLayoutRowBlockedInterleavedARM;
  static const bool columnBlocked =
      layout == CooperativeMatrixLayoutColumnBlockedInterleavedARM;
  static const bool layoutSupported = rowBlocked || columnBlocked;

  static const bool strideSupported =
      stride == 1u || stride == 2u || stride == 4u;

  // RowBlocked: whole blocks down the rows, whole interleaving groups across the
  // columns. ColumnBlocked: whole interleaving groups down the rows, whole
  // blocks across the columns.
  static const uint32_t rowsMultiple = rowBlocked ? 4u : 4u * stride;
  static const uint32_t columnsMultiple =
      rowBlocked ? blockColumns * stride : blockColumns;

  // `strideSupported` is tested first: with a stride outside 1/2/4 one of the
  // multiples above is 0, and the remainders must not be evaluated.
  static const bool shapeSupported =
      strideSupported && (rows % rowsMultiple == 0u) &&
      (columns % columnsMultiple == 0u);

  static const bool supported =
      layoutSupported && strideSupported && shapeSupported;
};

} // namespace arm
} // namespace vk

namespace vk {
namespace khr {

template <class ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse use>
template <CooperativeMatrixLayout layout, uint32_t stride, class Type>
CooperativeMatrix<ComponentType, scope, rows, columns, use>
CooperativeMatrix<ComponentType, scope, rows, columns, use>::
    LoadBlockedInterleaved(StructuredBuffer<Type> buffer, uint32_t index) {
  // Instantiating this check with `false` is the diagnostic for a combination
  // SPV_ARM_cooperative_matrix_layouts does not allow.
  typedef typename vk::arm::BlockedInterleavedLayoutIsSupported<
      vk::arm::BlockedInterleavedLayout<layout, stride, ComponentType, rows,
                                        columns>::supported>::ok Checked;
  CooperativeMatrix result;
  result._matrix = __builtin_spv_CooperativeMatrixLoadKHR<SpirvMatrixType>(
      buffer[index], layout, stride, MemoryAccessMaskNone);
  return result;
}

template <class ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse use>
template <CooperativeMatrixLayout layout, uint32_t stride, class Type>
CooperativeMatrix<ComponentType, scope, rows, columns, use>
CooperativeMatrix<ComponentType, scope, rows, columns, use>::
    LoadBlockedInterleaved(RWStructuredBuffer<Type> buffer, uint32_t index) {
  typedef typename vk::arm::BlockedInterleavedLayoutIsSupported<
      vk::arm::BlockedInterleavedLayout<layout, stride, ComponentType, rows,
                                        columns>::supported>::ok Checked;
  CooperativeMatrix result;
  result._matrix = __builtin_spv_CooperativeMatrixLoadKHR<SpirvMatrixType>(
      buffer[index], layout, stride, MemoryAccessMaskNone);
  return result;
}

template <class ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse use>
template <CooperativeMatrixLayout layout, uint32_t stride, class Type>
CooperativeMatrix<ComponentType, scope, rows, columns, use>
CooperativeMatrix<ComponentType, scope, rows, columns, use>::
    LoadBlockedInterleaved(WorkgroupSpirvPointer<Type> buffer) {
  typedef typename vk::arm::BlockedInterleavedLayoutIsSupported<
      vk::arm::BlockedInterleavedLayout<layout, stride, ComponentType, rows,
                                        columns>::supported>::ok Checked;
  CooperativeMatrix result;
  result._matrix =
      __builtin_spv_CooperativeMatrixWorkgroupLoadKHR<SpirvMatrixType>(
          buffer, layout, stride,
          MemoryAccessNonPrivatePointerMask | MemoryAccessMakePointerVisibleMask,
          ScopeWorkgroup);
  return result;
}

template <class ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse use>
template <CooperativeMatrixLayout layout, uint32_t stride, class Type>
void CooperativeMatrix<ComponentType, scope, rows, columns, use>::
    StoreBlockedInterleaved(RWStructuredBuffer<Type> data, uint32_t index) {
  typedef typename vk::arm::BlockedInterleavedLayoutIsSupported<
      vk::arm::BlockedInterleavedLayout<layout, stride, ComponentType, rows,
                                        columns>::supported>::ok Checked;
  __builtin_spv_CooperativeMatrixStoreKHR(data[index], _matrix, layout, stride,
                                          MemoryAccessMaskNone);
}

template <class ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse use>
template <CooperativeMatrixLayout layout, uint32_t stride, class Type>
void CooperativeMatrix<ComponentType, scope, rows, columns, use>::
    StoreBlockedInterleaved(WorkgroupSpirvPointer<Type> data) {
  typedef typename vk::arm::BlockedInterleavedLayoutIsSupported<
      vk::arm::BlockedInterleavedLayout<layout, stride, ComponentType, rows,
                                        columns>::supported>::ok Checked;
  __builtin_spv_CooperativeMatrixWorkgroupStoreKHR(
      data, _matrix, layout, stride,
      MemoryAccessNonPrivatePointerMask | MemoryAccessMakePointerAvailableMask,
      ScopeWorkgroup);
}

} // namespace khr
} // namespace vk

#endif // _HLSL_VK_ARM_COOPERATIVE_MATRIX_LAYOUTS_H_
