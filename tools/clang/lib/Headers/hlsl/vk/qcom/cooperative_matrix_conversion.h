// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef _HLSL_VK_QCOM_COOPERATIVE_MATRIX_CONVERSION_H_
#define _HLSL_VK_QCOM_COOPERATIVE_MATRIX_CONVERSION_H_

#if __SPIRV_MAJOR_VERSION__ == 1 && __SPIRV_MINOR_VERSION__ < 6
#error "CooperativeMatrixConversionQCOM requires a minimum of SPIR-V 1.6"
#endif

#include <vk/khr/cooperative_matrix.h>

namespace vk {
namespace qcom {

// Bitcast between compatible 1D arrays. The SPIR-V opcode is
// OpBitCastArrayQCOM (4497), which requires CooperativeMatrixConversionQCOM
// (4496) capability.
// The result is written through the result array parameter (passed by reference
// via the builtin's ext_reference attribute).
template <typename ResultType, typename ArrayType>
void bitCastArray(ArrayType array, ResultType result);

// Build a cooperative matrix from a subgroup of invocations' array data.
// The SPIR-V opcode is OpCompositeConstructCoopMatQCOM (4540), which requires
// CooperativeMatrixConversionQCOM (4496) capability.
// The array must be a fixed-size array (e.g., groupshared float[N]), not an
// RWStructuredBuffer, because the SPIR-V instruction requires OpTypeArray.
template <typename ComponentType, Scope scope, uint rows, uint columns,
          CooperativeMatrixUse use, typename ArrayType>
khr::CooperativeMatrix<ComponentType, scope, rows, columns, use>
compositeConstructCooperativeMatrix(ArrayType array);

// Cooperate with other invocations to extract rows/columns of a cooperative
// matrix into per-invocation arrays. The SPIR-V opcode is
// OpCompositeExtractCoopMatQCOM (4541), which requires
// CooperativeMatrixConversionQCOM (4496) capability.
// The result is written through the result array parameter (passed by reference
// via the builtin's ext_reference attribute).
template <typename ResultArrayType, typename ComponentType, Scope scope,
          uint rows, uint columns, CooperativeMatrixUse use>
void compositeExtractCooperativeMatrix(
    khr::CooperativeMatrix<ComponentType, scope, rows, columns, use> matrix,
    ResultArrayType resultArray);

// Extract a sub-array from a source array at the given index.
// The SPIR-V opcode is OpExtractSubArrayQCOM (4542), which requires
// CooperativeMatrixConversionQCOM (4496) capability.
// The result is written through the result array parameter (passed by reference
// via the builtin's ext_reference attribute).
template <typename ResultType, typename ArrayType>
void extractSubArray(ArrayType array, uint index, ResultType result);

} // namespace qcom
} // namespace vk

#include <vk/qcom/cooperative_matrix_conversion.impl>
#endif // _HLSL_VK_QCOM_COOPERATIVE_MATRIX_CONVERSION_H_
