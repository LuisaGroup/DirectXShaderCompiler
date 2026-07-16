// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef _HLSL_VK_SPIRV_H_
#define _HLSL_VK_SPIRV_H_

namespace vk {

enum CooperativeMatrixUse {
  CooperativeMatrixUseMatrixAKHR = 0,
  CooperativeMatrixUseMatrixBKHR = 1,
  CooperativeMatrixUseMatrixAccumulatorKHR = 2,
  CooperativeMatrixUseMax = 0x7fffffff,
};

enum CooperativeMatrixLayout {
  CooperativeMatrixLayoutRowMajorKHR = 0,
  CooperativeMatrixLayoutColumnMajorKHR = 1,
  CooperativeMatrixLayoutRowBlockedInterleavedARM = 4202,
  CooperativeMatrixLayoutColumnBlockedInterleavedARM = 4203,
  CooperativeMatrixLayoutMax = 0x7fffffff,
};

enum CooperativeMatrixOperandsMask {
  CooperativeMatrixOperandsMaskNone = 0,
  CooperativeMatrixOperandsMatrixASignedComponentsKHRMask = 0x00000001,
  CooperativeMatrixOperandsMatrixBSignedComponentsKHRMask = 0x00000002,
  CooperativeMatrixOperandsMatrixCSignedComponentsKHRMask = 0x00000004,
  CooperativeMatrixOperandsMatrixResultSignedComponentsKHRMask = 0x00000008,
  CooperativeMatrixOperandsSaturatingAccumulationKHRMask = 0x00000010,
};

// Cooperative Matrix Reduce Mode (SPV_NV_cooperative_matrix2)
enum CooperativeMatrixReduceMode {
  CooperativeMatrixReduceRow = 0x1,
  CooperativeMatrixReduceColumn = 0x2,
  CooperativeMatrixReduce2x2 = 0x4,
  CooperativeMatrixReduceMax = 0x7fffffff,
};

// Cooperative Vector Matrix Layout (SPV_NV_cooperative_vector)
enum CooperativeVectorMatrixLayout {
  CooperativeVectorMatrixLayoutRowMajorNV = 0,
  CooperativeVectorMatrixLayoutColumnMajorNV = 1,
  CooperativeVectorMatrixLayoutInferencingOptimalNV = 2,
  CooperativeVectorMatrixLayoutTrainingOptimalNV = 3,
  CooperativeVectorMatrixLayoutMax = 0x7fffffff,
};

// Component type interpretations (matches VkComponentTypeKHR / gl_ComponentType*)
enum CooperativeVectorComponentType {
  CooperativeVectorComponentTypeFloat16NV = 0,
  CooperativeVectorComponentTypeFloat32NV = 1,
  CooperativeVectorComponentTypeFloat64NV = 2,
  CooperativeVectorComponentTypeSignedInt8NV = 3,
  CooperativeVectorComponentTypeSignedInt16NV = 4,
  CooperativeVectorComponentTypeSignedInt32NV = 5,
  CooperativeVectorComponentTypeSignedInt64NV = 6,
  CooperativeVectorComponentTypeUnsignedInt8NV = 7,
  CooperativeVectorComponentTypeUnsignedInt16NV = 8,
  CooperativeVectorComponentTypeUnsignedInt32NV = 9,
  CooperativeVectorComponentTypeUnsignedInt64NV = 10,
  CooperativeVectorComponentTypeSignedInt8PackedNV = 1000491000,
  CooperativeVectorComponentTypeUnsignedInt8PackedNV = 1000491001,
  CooperativeVectorComponentTypeFloatE4M3NV = 1000491002,
  CooperativeVectorComponentTypeFloatE5M2NV = 1000491003,
};

enum MemoryAccessMask {
  MemoryAccessMaskNone = 0,
  MemoryAccessVolatileMask = 0x00000001,
  MemoryAccessAlignedMask = 0x00000002,
  MemoryAccessNontemporalMask = 0x00000004,
  MemoryAccessMakePointerAvailableMask = 0x00000008,
  MemoryAccessMakePointerAvailableKHRMask = 0x00000008,
  MemoryAccessMakePointerVisibleMask = 0x00000010,
  MemoryAccessMakePointerVisibleKHRMask = 0x00000010,
  MemoryAccessNonPrivatePointerMask = 0x00000020,
  MemoryAccessNonPrivatePointerKHRMask = 0x00000020,
  MemoryAccessAliasScopeINTELMaskMask = 0x00010000,
  MemoryAccessNoAliasINTELMaskMask = 0x00020000,
};

enum Scope {
  ScopeCrossDevice = 0,
  ScopeDevice = 1,
  ScopeWorkgroup = 2,
  ScopeSubgroup = 3,
  ScopeInvocation = 4,
  ScopeQueueFamily = 5,
  ScopeQueueFamilyKHR = 5,
  ScopeShaderCallKHR = 6,
  ScopeMax = 0x7fffffff,
};

enum StorageClass {
  StorageClassWorkgroup = 4,
};

// An opaque type to represent a Spir-V pointer to the workgroup storage class.
// clang-format off
template <typename PointeeType>
using WorkgroupSpirvPointer = const vk::SpirvOpaqueType<
    /* OpTypePointer */ 32,
    vk::Literal<vk::integral_constant<uint, StorageClassWorkgroup> >,
    PointeeType>;
// clang-format on

// Returns an opaque Spir-V pointer to v. The memory object v's storage class
// modifier must be groupshared. If the incorrect storage class is used, then
// there will be a validation error, and it will not show the correct
template <typename T>
[[vk::ext_instruction(/* OpCopyObject */ 83)]] WorkgroupSpirvPointer<T>
GetGroupSharedAddress([[vk::ext_reference]] T v);

} // namespace vk

#endif // _HLSL_VK_SPIRV_H_
