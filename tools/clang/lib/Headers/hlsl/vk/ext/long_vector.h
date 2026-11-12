// Copyright (c) 2026 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Long vectors: VK_EXT_shader_long_vector / SPV_EXT_long_vector.
//
// SPIR-V limits OpTypeVector to 1..4 components. With the LongVectorEXT
// capability a vector may have an arbitrary positive number of components, and
// OpTypeVectorIdEXT can take the count from a specialization constant. This
// header provides the fixed-size half of that:
//
//   #include <vk/ext/long_vector.h>
//
//   using float8 = vk::ext::LongVector<float, 8>;
//
//   float8   v = vk::ext::Concat(lo, hi); // OpCompositeConstruct, 2 x float4
//   float    x = vk::ext::Get<7>(v);      // OpCompositeExtract, component 7
//   float8   w = vk::ext::Set<7>(v, x);   // OpCompositeInsert, component 7
//
// HLSL has no type of its own for a long vector: the front end rejects
// vector<T, N> for N > 4 with "invalid value, valid range is between 1 and 4
// inclusive", and the "long vector" execution tests under
// tools/clang/unittests/HLSLExec belong to a different target (DXIL, shader
// model 6.9), not to SPIR-V. The type is therefore an inline SPIR-V type, the
// same mechanism <vk/spirv.h> uses for vk::WorkgroupSpirvPointer: a
// vk::SpirvOpaqueType with the OpTypeVector (23) opcode, the component type,
// and the component count as a literal.
//
// This header is a *type plus element access*, not an HLSL arithmetic system.
// SPV_EXT_long_vector allows a long vector in any instruction that already
// accepts vector types and does not constrain the component count, so
// OpLoad/OpStore, the arithmetic instructions and OpVectorShuffle all work on
// the type. HLSL's operators, swizzles and implicit conversions, however, are
// defined in terms of ordinary vectors (float2/float3/float4) and cannot be
// pointed at this type, so a value is built from, and decomposed into, ordinary
// vectors with the three composite instructions below. Anything wider
// (component-wise arithmetic helpers, long-vector swizzles, buffer layout) is a
// separate feature; see docs/SPIR-V.rst.
//
// The three low-level entry points are [[vk::ext_instruction]] declarations, so
// they have no definition anywhere and SPIR-V CodeGen emits the instruction in
// place of the call:
//
//   Concat(lo, hi)      -> OpCompositeConstruct (80)
//   Extract(v, i)       -> OpCompositeExtract  (81), i must be a literal
//   Insert(v, x, i)     -> OpCompositeInsert   (82), i must be a literal
//
// Get<index>() and Set<index>() are ordinary functions that forward a
// compile-time constant, so the index cannot accidentally be a run-time value.
//
// Module surface:
// * OpCapability LongVectorEXT (5425) and OpExtension "SPV_EXT_long_vector",
//   emitted by SPIR-V CodeGen from the type itself (the SpirvIntrinsicType case
//   in CapabilityVisitor) rather than by [[vk::ext_capability]] /
//   [[vk::ext_extension]] on the declarations below. That is what lets
//   -fspv-extension select the extension, and refuse it.
//
// Requirements and restrictions, all diagnosed rather than miscompiled:
// * A target environment of SPIR-V 1.3 or later: SPV_EXT_long_vector is
//   specified as modifications to SPIR-V 1.3, so -fspv-target-env=vulkan1.0
//   (the default, SPIR-V 1.0) is rejected; use vulkan1.1 or above.
// * The extension is opt-in: without -fspv-extension=SPV_EXT_long_vector every
//   use is a compile error, because a driver that does not expose
//   VK_EXT_shader_long_vector rejects a module declaring LongVectorEXT.
// * N must be a compile-time constant greater than four. Four or fewer
//   components is an ordinary vector, and a count that is not a constant is not
//   accepted at all: a count from a specialization constant would need
//   OpTypeVectorIdEXT (5288), which this header deliberately does not provide.
// * Long vectors may only be allocated in Function, Private, UniformConstant,
//   Uniform, Workgroup, StorageBuffer, PhysicalStorageBuffer, PushConstant,
//   ShaderRecordBufferKHR, CrossWorkgroup and Generic storage classes. A long
//   vector in a stage input/output variable is a compile error here, because
//   SPIRV-Tools rejects such a module.
// * Long vectors cannot be the column type of a matrix, and SPV_EXT_long_vector
//   keeps OpTypeVector to 2, 3 or 4 components there.
//
// Required from the host - the compiler cannot check any of this:
// * the VK_EXT_shader_long_vector device extension,
// * its longVector feature bit,
// * the device's limit on the number of components, the maxVectorComponents
//   member of the extension's properties struct. A shader that uses more
//   components than the device reports still compiles, but creating the
//   pipeline fails. Keep N at or below that limit.
//
// See docs/SPIR-V.rst ("Long vectors") and
// examples/spirv-extensions/ext-long-vector.hlsl.

#ifndef _HLSL_VK_EXT_LONG_VECTOR_H_
#define _HLSL_VK_EXT_LONG_VECTOR_H_

namespace vk {
namespace ext {

// A SPIR-V vector type with N components of type T (N > 4). The component count
// is a LiteralInteger operand of OpTypeVector, so it is wrapped in
// vk::Literal<vk::integral_constant<...>> instead of being passed as an id.
template <typename T, uint N>
using LongVector =
    vk::SpirvOpaqueType</* OpTypeVector */ 23, T,
                        vk::Literal<vk::integral_constant<uint, N> > >;

// Builds an 8-component vector out of two ordinary 4-component vectors. Lowers
// to OpCompositeConstruct (80):
//   %result = OpCompositeConstruct %long8 %low %high
// The two constituents are concatenated in order, so the value of component i
// is low[i] for i < 4 and high[i - 4] otherwise.
template <typename T>
[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] LongVector<T, 8>
Concat(vector<T, 4> low, vector<T, 4> high);

// Builds a 16-component vector out of four ordinary 4-component vectors, in
// order. One OpCompositeConstruct with four constituents, concatenated in the
// order they are passed.
template <typename T>
[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] LongVector<T, 16>
Concat(vector<T, 4> c0, vector<T, 4> c1, vector<T, 4> c2, vector<T, 4> c3);

// Builds a 16-component vector out of two 8-component vectors. The constituents
// of OpCompositeConstruct may themselves be vectors of any length, so long
// vectors compose.
template <typename T>
[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] LongVector<T, 16>
Concat(LongVector<T, 8> low, LongVector<T, 8> high);

// Reads component `index` of a long vector. Lowers to OpCompositeExtract (81):
//   %result = OpCompositeExtract %T %value <index>
// `index` is an [[vk::ext_literal]] parameter, so it must be a constant that
// fits the instruction's LiteralInteger operand; prefer Get<index>() below,
// which enforces that at the call site. `index` must be less than N.
template <typename T, uint N>
[[vk::ext_instruction(/* OpCompositeExtract */ 81)]] T
Extract(LongVector<T, N> value, [[vk::ext_literal]] uint index);

// Writes component `index` of a long vector, returning the updated value.
// Lowers to OpCompositeInsert (82), whose operands are the new component
// ("Object") followed by the value it is inserted into ("Composite"):
//   %result = OpCompositeInsert %longN <object> <composite> <index>
// The operand order is the instruction's, not the mnemonic's; prefer
// Set<index>() below, which takes the vector first. As with Extract, the index
// has to be a literal.
template <typename T, uint N>
[[vk::ext_instruction(/* OpCompositeInsert */ 82)]] LongVector<T, N>
Insert(T object, LongVector<T, N> composite, [[vk::ext_literal]] uint index);

// Reads component `index` of a long vector. The index is a template argument, so
// it is always a compile-time constant.
template <uint index, typename T, uint N>
T Get(LongVector<T, N> value) {
  return Extract(value, index);
}

// Writes component `index` of a long vector and returns the updated value. The
// component is cast to the vector's component type first, so a literal such as
// 42.0 does not participate in template argument deduction.
template <uint index, typename T, uint N, typename U>
LongVector<T, N> Set(LongVector<T, N> value, U component) {
  return Insert((T)component, value, index);
}

} // namespace ext
} // namespace vk

#endif // _HLSL_VK_EXT_LONG_VECTOR_H_
