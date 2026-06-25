// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef _HLSL_VK_NV_TENSOR_ADDRESSING_H_
#define _HLSL_VK_NV_TENSOR_ADDRESSING_H_

#if __SPIRV_MAJOR_VERSION__ == 1 && __SPIRV_MINOR_VERSION__ < 6
#error "TensorAddressing requires a minimum of SPIR-V 1.6"
#endif

#include <vk/spirv.h>

namespace vk {
namespace nv {

// Tensor Clamp Mode (matches SPIR-V enum values)
enum TensorClampMode {
  TensorClampModeUndefinedNV = 0,
  TensorClampModeConstantNV = 1,
  TensorClampModeClampToEdgeNV = 2,
  TensorClampModeMax = 0x7fffffff,
};

// Opaque tensor layout type. Represents the memory layout of a tensor.
// Dim is the number of dimensions (1-5). ClampMode specifies out-of-bounds
// behavior. The SPIR-V type is OpTypeTensorLayoutNV (5370).
template <uint Dim, uint ClampMode>
struct TensorLayout {
  // clang-format off
  using SpirvLayoutType = vk::SpirvOpaqueType<
      /* OpTypeTensorLayoutNV */ 5370,
      vk::integral_constant<uint, Dim>,
      vk::integral_constant<uint, ClampMode> >;

  [[vk::ext_extension("SPV_NV_tensor_addressing")]]
  [[vk::ext_capability(/* TensorAddressingNV */ 5439)]]
  SpirvLayoutType _layout;
  // clang-format on
};

// Opaque tensor view type. Represents a view into a tensor.
// Dim is the number of dimensions (1-5). HasDimensions indicates whether
// the view has explicit dimensions. Perm0 and Perm1 specify the dimension
// permutation for 2D views (identity: Perm0=0, Perm1=1).
// The SPIR-V type is OpTypeTensorViewNV (5371).
template <uint Dim, bool HasDimensions, uint Perm0 = 0, uint Perm1 = 1>
struct TensorView {
  // clang-format off
  using SpirvViewType = vk::SpirvOpaqueType<
      /* OpTypeTensorViewNV */ 5371,
      vk::integral_constant<uint, Dim>,
      vk::integral_constant<bool, HasDimensions>,
      vk::integral_constant<uint, Perm0>,
      vk::integral_constant<uint, Perm1> >;

  [[vk::ext_extension("SPV_NV_tensor_addressing")]]
  [[vk::ext_capability(/* TensorAddressingNV */ 5439)]]
  SpirvViewType _view;
  // clang-format on
};

// --- Tensor Layout Functions ---

// Create a default tensor layout with the given dimension count and clamp mode.
template <uint Dim, uint ClampMode>
TensorLayout<Dim, ClampMode> createTensorLayout();

// Set the size of a tensor dimension. Returns a new TensorLayout.
template <uint Dim, uint ClampMode>
TensorLayout<Dim, ClampMode> tensorLayoutSetDimension(
    TensorLayout<Dim, ClampMode> layout, uint dim, uint size);

// Set the stride of a tensor dimension. Returns a new TensorLayout.
template <uint Dim, uint ClampMode>
TensorLayout<Dim, ClampMode> tensorLayoutSetStride(
    TensorLayout<Dim, ClampMode> layout, uint dim, uint stride);

// Set the block size of a tensor dimension. Returns a new TensorLayout.
template <uint Dim, uint ClampMode>
TensorLayout<Dim, ClampMode> tensorLayoutSetBlockSize(
    TensorLayout<Dim, ClampMode> layout, uint dim, uint blockSize);

// Slice a sub-region from the tensor layout. Returns a new TensorLayout.
template <uint Dim, uint ClampMode>
TensorLayout<Dim, ClampMode> tensorLayoutSlice(
    TensorLayout<Dim, ClampMode> layout, uint dim, uint offset, uint span);

// Set the out-of-bounds clamp value. Returns a new TensorLayout.
template <uint Dim, uint ClampMode>
TensorLayout<Dim, ClampMode> tensorLayoutSetClampValue(
    TensorLayout<Dim, ClampMode> layout, uint clampValue);

// --- Tensor View Functions ---

// Create a default tensor view with the given dimension count and permutation.
template <uint Dim, bool HasDimensions, uint Perm0 = 0, uint Perm1 = 1>
TensorView<Dim, HasDimensions, Perm0, Perm1> createTensorView();

// Set the size of a tensor view dimension. Returns a new TensorView.
template <uint Dim, bool HasDimensions, uint Perm0, uint Perm1>
TensorView<Dim, HasDimensions, Perm0, Perm1> tensorViewSetDimension(
    TensorView<Dim, HasDimensions, Perm0, Perm1> view,
    uint dim, uint size);

// Set the stride of a tensor view dimension. Returns a new TensorView.
template <uint Dim, bool HasDimensions, uint Perm0, uint Perm1>
TensorView<Dim, HasDimensions, Perm0, Perm1> tensorViewSetStride(
    TensorView<Dim, HasDimensions, Perm0, Perm1> view,
    uint dim, uint stride);

// Set the clip region of a tensor view. Returns a new TensorView.
template <uint Dim, bool HasDimensions, uint Perm0, uint Perm1>
TensorView<Dim, HasDimensions, Perm0, Perm1> tensorViewSetClip(
    TensorView<Dim, HasDimensions, Perm0, Perm1> view,
    uint rowOffset, uint rowSpan, uint colOffset, uint colSpan);

} // namespace nv
} // namespace vk

#include <vk/nv/tensor_addressing.impl>
#endif // _HLSL_VK_NV_TENSOR_ADDRESSING_H_
