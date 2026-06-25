// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef _HLSL_VK_NV_COOPERATIVE_MATRIX2_H_
#define _HLSL_VK_NV_COOPERATIVE_MATRIX2_H_

#if __SPIRV_MAJOR_VERSION__ == 1 && __SPIRV_MINOR_VERSION__ < 6
#error "CooperativeMatrix2 requires a minimum of SPIR-V 1.6"
#endif

#include <vk/khr/cooperative_matrix.h>
#include <vk/nv/cooperative_vector.h>

namespace vk {
namespace nv {

// Convert a cooperative matrix between Use types (Accumulator ↔ MatrixA/MatrixB)
// without changing the component type. The SPIR-V opcode is
// OpCooperativeMatrixConvertNV (5293), which requires
// CooperativeMatrixConversionsNV (5431) capability.
template <typename ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse NewUse, CooperativeMatrixUse OldUse>
khr::CooperativeMatrix<ComponentType, scope, rows, columns, NewUse>
cooperativeMatrixConvertUse(
    khr::CooperativeMatrix<ComponentType, scope, rows, columns, OldUse> matrix);

// Transpose an M×N Accumulator matrix into an N×M MatrixB matrix.
// The SPIR-V opcode is OpCooperativeMatrixTransposeNV (5390), which requires
// CooperativeMatrixConversionsNV (5431) capability.
template <typename ComponentType, Scope scope, uint rows, uint columns>
khr::CooperativeMatrix<ComponentType, scope, columns, rows,
                       CooperativeMatrixUseMatrixBKHR>
cooperativeMatrixTranspose(
    khr::CooperativeMatrix<ComponentType, scope, rows, columns,
                           CooperativeMatrixUseMatrixAccumulatorKHR> matrix);

// Reduce a cooperative matrix by rows using a combine function. The combineOp
// is the SPIR-V opcode for the combine operation (e.g., 128 for OpIAdd).
// The SPIR-V opcode is OpCooperativeMatrixReduceNV (5366), which requires
// CooperativeMatrixReductionsNV (5430) capability.
// The result is a CooperativeVector with 'columns' components.
template <typename ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse use>
CooperativeVector<ComponentType, columns>
cooperativeMatrixReduceRow(
    khr::CooperativeMatrix<ComponentType, scope, rows, columns, use> matrix,
    uint combineOp);

// Reduce a cooperative matrix by columns using a combine function. The combineOp
// is the SPIR-V opcode for the combine operation (e.g., 128 for OpIAdd).
// The SPIR-V opcode is OpCooperativeMatrixReduceNV (5366), which requires
// CooperativeMatrixReductionsNV (5430) capability.
// The result is a CooperativeVector with 'rows' components.
template <typename ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse use>
CooperativeVector<ComponentType, rows>
cooperativeMatrixReduceColumn(
    khr::CooperativeMatrix<ComponentType, scope, rows, columns, use> matrix,
    uint combineOp);

// Reduce a cooperative matrix by 2x2 neighborhoods using a combine function.
// The combineOp is the SPIR-V opcode for the combine operation
// (e.g., 128 for OpIAdd). The SPIR-V opcode is OpCooperativeMatrixReduceNV
// (5366), which requires CooperativeMatrixReductionsNV (5430) capability.
// The result is a CooperativeMatrix with rows/2 × columns/2 dimensions.
template <typename ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse use>
khr::CooperativeMatrix<ComponentType, scope, rows / 2, columns / 2, use>
cooperativeMatrixReduce2x2(
    khr::CooperativeMatrix<ComponentType, scope, rows, columns, use> matrix,
    uint combineOp);

// Apply a user-defined SPIR-V function to each element of a cooperative
// matrix. The functionId is an IdRef to a SPIR-V function. The SPIR-V opcode
// is OpCooperativeMatrixPerElementOpNV (5369), which requires
// CooperativeMatrixPerElementOperationsNV (5432) capability.
//
// Note: Passing a function ID requires the function to be declared as a
// SPIR-V function that takes (row, col, value) and returns the new value.
template <typename ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse use>
khr::CooperativeMatrix<ComponentType, scope, rows, columns, use>
cooperativeMatrixPerElementOp(
    khr::CooperativeMatrix<ComponentType, scope, rows, columns, use> matrix,
    uint functionId);

} // namespace nv
} // namespace vk

#include <vk/nv/cooperative_matrix2.impl>
#endif // _HLSL_VK_NV_COOPERATIVE_MATRIX2_H_
