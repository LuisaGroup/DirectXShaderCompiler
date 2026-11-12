// Copyright (c) 2026 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Cooperative vectors: VK_NV_cooperative_vector / SPV_NV_cooperative_vector.
//
// A cooperative vector is an opaque vector whose length and component type are
// part of its SPIR-V type, and whose arithmetic is a small, fixed instruction
// set rather than HLSL's operators: a matrix-vector product, an accumulating
// matrix-vector product, an outer-product accumulate and a reduce-sum
// accumulate, plus a load and a store that move values between memory and the
// opaque type. The matrix, the bias and the accumulators live in memory, so
// every operand that refers to one is a pointer and an offset.
//
//   #include <vk/nv/cooperative_vector.h>
//
//   vk::nv::CooperativeVector<float, 4> v = vk::nv::Load<float, 4>(g_vector, 0);
//   vk::nv::CooperativeVector<float, 8> r = vk::nv::MatrixMul<float, 8, 4>(
//       v, vk::CooperativeVectorComponentTypeFloat32NV,
//       g_matrix, /*matrixOffset*/ 0,
//       vk::CooperativeVectorComponentTypeFloat32NV,
//       /*M*/ 8, /*K*/ 4,
//       vk::CooperativeVectorMatrixLayoutRowMajorNV,
//       /*transpose*/ false, /*matrixStride*/ 32);
//   vk::nv::Store<float, 8>(g_result, 0, r);
//
// HLSL has no cooperative vector type of its own, so the type is an inline
// SPIR-V type: vk::SpirvOpaqueType with the opcode of OpTypeVectorIdEXT (5288),
// whose *Component Type* is an <id> of a scalar type and whose *Component Count*
// is an <id> of a 32-bit integer constant instruction. The count is wrapped in
// vk::integral_constant<uint, N> so that it is written as the id of an
// OpConstant and not as a literal. OpTypeVectorIdEXT is the instruction
// SPV_EXT_long_vector uses for a vector with a specialization-constant component
// count; <vk/ext/long_vector.h> deliberately does not implement it, so this
// header owns opcode 5288 (docs/SPIR-V.rst, "Long vectors").
//
// The six operations are [[vk::ext_instruction]] declarations, so they have no
// definition anywhere and SPIR-V CodeGen emits the instruction in place of the
// call. Operand order below is the instruction's, exactly as the grammar spells
// it, which is not always the order the mnemonic suggests:
//
//   Load    (ResultType, Result, Pointer, Offset, [MemoryAccess])
//   Store   (Pointer, Offset, Object, [MemoryAccess])
//   MatrixMul
//           (ResultType, Result, Input, InputInterpretation, Matrix,
//            MatrixOffset, MatrixInterpretation, M, K, MemoryLayout,
//            Transpose, [MatrixStride], [CooperativeMatrixOperands])
//   MatrixMulAdd
//           (ResultType, Result, Input, InputInterpretation, Matrix,
//            MatrixOffset, MatrixInterpretation, Bias, BiasOffset,
//            BiasInterpretation, M, K, MemoryLayout, Transpose,
//            [MatrixStride], [CooperativeMatrixOperands])
//   OuterProductAccumulate
//           (Pointer, Offset, A, B, MemoryLayout, MatrixInterpretation,
//            [MatrixStride])
//   ReduceSumAccumulate
//           (Pointer, Offset, V)
//
// The bias of MatrixMulAdd is a *pointer* (plus an offset and an
// interpretation), the same shape as the matrix, not a cooperative vector value.
//
// Because a declaration-only entry point has exactly one parameter per SPIR-V
// operand, the interpretation, M, K, MemoryLayout and Transpose operands are
// ordinary parameters here. SPV_NV_cooperative_vector requires every one of them
// to name a *constant instruction* - SPIRV-Tools rejects a module otherwise
// ("<op> <operand> <id> is not a constant instruction") - so they have to be
// passed as compile-time constants: enumerators from <vk/spirv.h>, integer
// literals, and a bool literal for Transpose. Passing a run-time value is
// diagnosed by SPIR-V CodeGen ("the ... operands ... must be compile-time
// constants") instead of producing a module that does not validate. There is no
// instruction that converts between memory layouts at run time, which is why the
// layout cannot be a run-time value in the first place.
//
// The pointer operands are [[vk::ext_reference]] parameters whose type is
// deduced from the argument, and the argument has to be an *array*: SPIRV-Tools
// requires the pointer of OpCooperativeVectorLoadNV / ...StoreNV /
// ...MatrixMulNV / ...MatrixMulAddNV / ...OuterProductAccumulateNV /
// ...ReduceSumAccumulateNV to point to an OpTypeArray or OpTypeRuntimeArray
// whose element type is a scalar or vector, in the Workgroup, StorageBuffer or
// PhysicalStorageBuffer storage class. In HLSL the shape that produces exactly
// that is a groupshared array, passed whole:
//
//   groupshared float g_matrix[16];
//   ... vk::nv::MatrixMul<...>(v, ..., g_matrix, 0, ...);
//   ; %g_matrix is OpVariable %_ptr_Workgroup_%arr_float_16 Workgroup
//
// Passing an element (g_matrix[0]) is rejected here, by the
// PointerMustPointToArray<> diagnostic below, because it would lower to a pointer
// to a scalar that SPIRV-Tools rejects. A private or function-local array
// produces the right shape with the wrong storage class; the storage class of an
// [[vk::ext_reference]] argument is not visible to the front end, so SPIRV-Tools
// rejects that module ("storage class for pointer type ... is not Workgroup or
// StorageBuffer"). Data that comes from a buffer has to be staged through
// groupshared memory first; see docs/SPIR-V.rst.
//
// Module surface:
// * Using the type adds OpCapability CooperativeVectorNV (5394) and
//   OpExtension "SPV_NV_cooperative_vector"; the two training instructions add
//   OpCapability CooperativeVectorTrainingNV (5435) as well (they take
//   cooperative vectors as operands, so their modules declare both). Both
//   capabilities and the extension are added by SPIR-V CodeGen from the
//   instruction and from the type (CapabilityVisitor), not by
//   [[vk::ext_capability]] / [[vk::ext_extension]] on the declarations below:
//   those attributes write the capability and the extension string
//   unconditionally, so -fspv-extension could neither select nor refuse them.
//   The extension is opt-in; see FeatureManager::enabledByDefault.
// * This header includes <vk/spirv.h> for the interpretation and layout
//   enumerators. That header materializes every one of its enumerators as a
//   module-scope variable, so a module that includes it - directly or through
//   <vk/khr/cooperative_matrix.h> - carries those variables; the optimizer
//   removes them when they are unused. It is a pre-existing property of
//   <vk/spirv.h>, not of this feature, and it is what makes the enumerators
//   usable as identifiers instead of bare integers.
// * The extension and its instructions carry no SPIR-V version requirement in
//   the grammar snapshot this tree vendors (spirv.core.grammar.json spells
//   "version": "None" for OpTypeVectorIdEXT and for all six instructions), so
//   there is no -fspv-target-env gate: a module produced from this header
//   validates at the default target environment (vulkan1.0, SPIR-V 1.0) as well
//   as at vulkan1.3. That is unlike <vk/ext/long_vector.h>, which is specified
//   against SPIR-V 1.3.
//
// Component types and lengths, each diagnosed rather than miscompiled:
// * 32-bit float, 16-bit float, 32-bit signed and 32-bit unsigned integers are
//   the component types SPIRV-Tools accepts for a cooperative vector ("<op>
//   result component type <id> is not a 32 bit int or 16/32 bit float"). double,
//   bool, 8- and 16-bit integers are rejected by the ComponentTypeIsSupported<>
//   diagnostic below and by CapabilityVisitor, whichever comes first.
// * The component count has to be at least one; a count taken from a
//   specialization constant is not expressible (the HLSL template argument is an
//   integral_constant, which lowers to an OpConstant).
// * A cooperative vector can only be allocated in Function or Private storage or
//   used as a function parameter (external/SPIRV-Tools, ValidateMemory:
//   "Cooperative vector types (or types containing them) can only be allocated
//   in Function or Private storage classes or as function parameters"), so a
//   groupshared variable of this type is an error; CapabilityVisitor reports it.
// * MatrixStride has to be present for the RowMajorNV and ColumnMajorNV layouts
//   and has to be absent for the InferencingOptimalNV and TrainingOptimalNV
//   layouts, whose stride the device chooses, which is why each of the three
//   memory-taking entry points has two overloads. Omitting the operand is
//   structural (there is no way to pass an empty one), so the mistake this
//   cannot catch is passing a stride to an optimal layout or omitting it for
//   RowMajorNV / ColumnMajorNV; the overloads make that a deliberate choice in
//   the source, and the compiler emits whatever the author asked for.
// * The trailing CooperativeMatrixOperands operand of OpCooperativeVectorMatrixMulNV
//   and ...MatrixMulAddNV is not modelled, so the Matrix*SignedComponentsKHR
//   hints cannot be requested and inferencing on signed 8-bit data takes the
//   device's default interpretation. It is a literal mask with further optional
//   operands, like MemoryAccess, and adding it is a separate piece of surface.
//
// Required from the host - the compiler cannot check any of this:
// * the VK_NV_cooperative_vector device extension,
// * VkPhysicalDeviceCooperativeVectorPropertiesNV, which reports
//   cooperativeVectorSupportedStages, cooperativeVectorTrainingFloat16Accumulation,
//   cooperativeVectorTrainingFloat32Accumulation, maxCooperativeVectorComponents
//   and maxCooperativeVectorMatrixComponents - a shader that exceeds the
//   component limit still compiles and fails pipeline creation,
// * the training half (OuterProductAccumulate, ReduceSumAccumulate) needs the
//   training feature bits of the same device extension; a device that implements
//   only the inferencing half rejects a module that declares
//   CooperativeVectorTrainingNV,
// * the component type and layout combinations that
//   vkGetPhysicalDeviceCooperativeVectorPropertiesNV reports per stage: the
//   compiler cannot know which of them a device supports, so a combination the
//   device does not list produces a module that fails at pipeline creation,
// * for the InferencingOptimalNV and TrainingOptimalNV layouts, the memory layout
//   the device prefers - the host decides it, and the shader cannot inspect it.
//
// See docs/SPIR-V.rst ("Cooperative vectors") and
// examples/spirv-extensions/nv-cooperative-vector.hlsl.
#ifndef _HLSL_VK_NV_COOPERATIVE_VECTOR_H_
#define _HLSL_VK_NV_COOPERATIVE_VECTOR_H_

#include <vk/spirv.h>

namespace vk {
namespace nv {

// A cooperative vector with N components of type ComponentType, i.e.
//   %cv = OpTypeVectorIdEXT %ComponentType %uint_N
// (OpTypeVectorIdEXT, 5288; its grammar alias is OpTypeCooperativeVectorNV).
// The component count is an <id> of a 32-bit integer constant instruction rather
// than a literal, which is why it is spelled vk::integral_constant<uint, N> and
// not vk::Literal<...>: the latter would be written as a literal word and
// SPIRV-Tools would reject the type. OpTypeVectorIdEXT requires the
// CooperativeVectorNV capability unless LongVectorEXT is declared, so using this
// type for any purpose adds both the capability and the extension;
// CapabilityVisitor::addCapabilityForType adds them from the type itself.
template <typename ComponentType, uint N>
using CooperativeVector = vk::SpirvOpaqueType</* OpTypeVectorIdEXT */ 5288,
                                             ComponentType,
                                             vk::integral_constant<uint, N> >;

// Compile-time checks for the entry points below. HLSL has no `static_assert`
// before -HV 202x and these headers are documented for -HV 2021, so an
// unsupported combination is reported by instantiating a class template that
// only has a definition for `true`. The instantiation happens in a default
// template argument of the entry point, so it names the declaration the author
// called:
//   error: no matching function for call to 'Load'
//   note: candidate template ignored: substitution failure [with ...]:
//         implicit instantiation of undefined template
//         'vk::nv::detail::PointerMustPointToArray<false>'
namespace detail {

// True when T is an array type. The pointer operands of the instructions in this
// header have to address an array, and passing a single element instead is the
// mistake this catches.
template <typename T> struct IsArray {
  static const bool value = false;
};
template <typename T, uint N> struct IsArray<T[N]> {
  static const bool value = true;
};

// The component types SPIRV-Tools accepts for a cooperative vector: a 32-bit
// integer, or a 16- or 32-bit float ("<op> result component type <id> is not a
// 32 bit int or 16/32 bit float"). min16float lowers to the same 16-bit float
// type as half.
template <typename T> struct IsSupportedComponent {
  static const bool value = false;
};
template <> struct IsSupportedComponent<float> {
  static const bool value = true;
};
template <> struct IsSupportedComponent<half> {
  static const bool value = true;
};
template <> struct IsSupportedComponent<min16float> {
  static const bool value = true;
};
template <> struct IsSupportedComponent<int> {
  static const bool value = true;
};
template <> struct IsSupportedComponent<uint> {
  static const bool value = true;
};

// The diagnostic types. Each has a definition for `true` only; instantiating it
// with `false` is the error.
template <bool supported> struct PointerMustPointToArray;
template <> struct PointerMustPointToArray<true> {
  using ok = int;
};

template <bool supported> struct ComponentTypeIsSupported;
template <> struct ComponentTypeIsSupported<true> {
  using ok = int;
};

template <bool supported> struct ComponentCountIsPositive;
template <> struct ComponentCountIsPositive<true> {
  using ok = int;
};

} // namespace detail

// Loads a cooperative vector from memory:
//   %result = OpCooperativeVectorLoadNV %type %ptr %offset
// Pointer has to address an array of the component type (see the note at the top
// of this file); Offset is the offset into that array that
// SPV_NV_cooperative_vector defines for the instruction, and may be a run-time
// value. This form omits the optional MemoryAccess operand.
template <typename T, uint N, typename Data,
          typename PointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Data>::value>::ok,
          typename ComponentCheck = typename detail::ComponentTypeIsSupported<
              detail::IsSupportedComponent<T>::value>::ok,
          typename CountCheck =
              typename detail::ComponentCountIsPositive<(N > 0)>::ok>
[[vk::ext_instruction(/* OpCooperativeVectorLoadNV */ 5302)]]
CooperativeVector<T, N> Load([[vk::ext_reference]] Data data, uint offset);

// Loads a cooperative vector from memory with a MemoryAccess operand:
//   %result = OpCooperativeVectorLoadNV %type %ptr %offset <MemoryAccess>
// The mask is a literal of the instruction, so it has to be a compile-time
// constant; use the vk::MemoryAccess*Mask enumerators from <vk/spirv.h>. Only
// Volatile and Nontemporal are expressible: Aligned and
// MakePointerAvailable/MakePointerVisible take further literal operands (an
// alignment, a scope) that this header does not model, and SPIRV-Tools rejects
// them without those operands.
template <typename T, uint N, typename Data,
          typename PointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Data>::value>::ok,
          typename ComponentCheck = typename detail::ComponentTypeIsSupported<
              detail::IsSupportedComponent<T>::value>::ok,
          typename CountCheck =
              typename detail::ComponentCountIsPositive<(N > 0)>::ok>
[[vk::ext_instruction(/* OpCooperativeVectorLoadNV */ 5302)]]
CooperativeVector<T, N> Load([[vk::ext_reference]] Data data, uint offset,
                             [[vk::ext_literal]] uint memoryAccess);

// Stores a cooperative vector to memory:
//   OpCooperativeVectorStoreNV %ptr %offset %object
// The value stays opaque: there is no instruction that reads or writes a single
// component of a cooperative vector, so a value is moved between memory and the
// type with this pair of instructions and combined with the instructions below.
// This form omits the optional MemoryAccess operand.
template <typename T, uint N, typename Data,
          typename PointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Data>::value>::ok,
          typename ComponentCheck = typename detail::ComponentTypeIsSupported<
              detail::IsSupportedComponent<T>::value>::ok,
          typename CountCheck =
              typename detail::ComponentCountIsPositive<(N > 0)>::ok>
[[vk::ext_instruction(/* OpCooperativeVectorStoreNV */ 5303)]] void
Store([[vk::ext_reference]] Data data, uint offset,
      CooperativeVector<T, N> value);

// Stores a cooperative vector to memory with a MemoryAccess operand. The same
// restrictions on the mask apply as for Load.
template <typename T, uint N, typename Data,
          typename PointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Data>::value>::ok,
          typename ComponentCheck = typename detail::ComponentTypeIsSupported<
              detail::IsSupportedComponent<T>::value>::ok,
          typename CountCheck =
              typename detail::ComponentCountIsPositive<(N > 0)>::ok>
[[vk::ext_instruction(/* OpCooperativeVectorStoreNV */ 5303)]] void
Store([[vk::ext_reference]] Data data, uint offset,
      CooperativeVector<T, N> value, [[vk::ext_literal]] uint memoryAccess);

// Matrix-vector product of a matrix in memory and a cooperative vector:
//   %result = OpCooperativeVectorMatrixMulNV %type %input %inputInterpretation
//       %matrix %matrixOffset %matrixInterpretation %M %K %memoryLayout
//       %transpose %matrixStride
// The result has M components and the input has as many as the instruction
// expects for its interpretation (K, or one per four columns for the packed
// 8-bit interpretations). `matrix` has to address an array of the matrix
// component type; the matrix is M x K in the orientation Transpose selects, and
// matrixStride is the distance in that array between two consecutive rows (or
// columns) for the RowMajorNV / ColumnMajorNV layouts.
// This overload is for the two layouts that carry a stride.
template <typename T, uint M, uint K,
          typename Matrix,
          typename PointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Matrix>::value>::ok,
          typename ComponentCheck = typename detail::ComponentTypeIsSupported<
              detail::IsSupportedComponent<T>::value>::ok,
          typename CountCheck =
              typename detail::ComponentCountIsPositive<(M > 0)>::ok>
[[vk::ext_instruction(/* OpCooperativeVectorMatrixMulNV */ 5289)]]
CooperativeVector<T, M> MatrixMul(
    CooperativeVector<T, K> input,
   vk::CooperativeVectorComponentType inputInterpretation,
    [[vk::ext_reference]] Matrix matrix, uint matrixOffset,
   vk::CooperativeVectorComponentType matrixInterpretation, uint m, uint k,
   vk::CooperativeVectorMatrixLayout memoryLayout, bool transpose,
    uint matrixStride);

// As above, without the MatrixStride operand:
//   %result = OpCooperativeVectorMatrixMulNV ... %memoryLayout %transpose
// This overload is for the InferencingOptimalNV and TrainingOptimalNV layouts,
// whose stride the device chooses.
template <typename T, uint M, uint K,
          typename Matrix,
          typename PointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Matrix>::value>::ok,
          typename ComponentCheck = typename detail::ComponentTypeIsSupported<
              detail::IsSupportedComponent<T>::value>::ok,
          typename CountCheck =
              typename detail::ComponentCountIsPositive<(M > 0)>::ok>
[[vk::ext_instruction(/* OpCooperativeVectorMatrixMulNV */ 5289)]]
CooperativeVector<T, M> MatrixMul(
    CooperativeVector<T, K> input,
   vk::CooperativeVectorComponentType inputInterpretation,
    [[vk::ext_reference]] Matrix matrix, uint matrixOffset,
   vk::CooperativeVectorComponentType matrixInterpretation, uint m, uint k,
   vk::CooperativeVectorMatrixLayout memoryLayout, bool transpose);

// Accumulating matrix-vector product: as MatrixMul, plus a bias matrix in memory
// that is added to the result.
//   %result = OpCooperativeVectorMatrixMulAddNV %type %input
//       %inputInterpretation %matrix %matrixOffset %matrixInterpretation
//       %bias %biasOffset %biasInterpretation %M %K %memoryLayout %transpose
//       %matrixStride
// The bias is a pointer and an offset, not a cooperative vector value, and it
// holds M values in the same memory layout as the matrix.
template <typename T, uint M, uint K,
          typename Matrix, typename Bias,
          typename MatrixPointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Matrix>::value>::ok,
          typename BiasPointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Bias>::value>::ok,
          typename ComponentCheck = typename detail::ComponentTypeIsSupported<
              detail::IsSupportedComponent<T>::value>::ok,
          typename CountCheck =
              typename detail::ComponentCountIsPositive<(M > 0)>::ok>
[[vk::ext_instruction(/* OpCooperativeVectorMatrixMulAddNV */ 5292)]]
CooperativeVector<T, M> MatrixMulAdd(
    CooperativeVector<T, K> input,
   vk::CooperativeVectorComponentType inputInterpretation,
    [[vk::ext_reference]] Matrix matrix, uint matrixOffset,
   vk::CooperativeVectorComponentType matrixInterpretation,
    [[vk::ext_reference]] Bias bias, uint biasOffset,
   vk::CooperativeVectorComponentType biasInterpretation, uint m, uint k,
   vk::CooperativeVectorMatrixLayout memoryLayout, bool transpose,
    uint matrixStride);

// As above, without the MatrixStride operand, for the InferencingOptimalNV and
// TrainingOptimalNV layouts.
template <typename T, uint M, uint K,
          typename Matrix, typename Bias,
          typename MatrixPointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Matrix>::value>::ok,
          typename BiasPointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Bias>::value>::ok,
          typename ComponentCheck = typename detail::ComponentTypeIsSupported<
              detail::IsSupportedComponent<T>::value>::ok,
          typename CountCheck =
              typename detail::ComponentCountIsPositive<(M > 0)>::ok>
[[vk::ext_instruction(/* OpCooperativeVectorMatrixMulAddNV */ 5292)]]
CooperativeVector<T, M> MatrixMulAdd(
    CooperativeVector<T, K> input,
   vk::CooperativeVectorComponentType inputInterpretation,
    [[vk::ext_reference]] Matrix matrix, uint matrixOffset,
   vk::CooperativeVectorComponentType matrixInterpretation,
    [[vk::ext_reference]] Bias bias, uint biasOffset,
   vk::CooperativeVectorComponentType biasInterpretation, uint m, uint k,
   vk::CooperativeVectorMatrixLayout memoryLayout, bool transpose);

// Training: accumulates the outer product of two cooperative vectors into a
// matrix in memory.
//   OpCooperativeVectorOuterProductAccumulateNV %ptr %offset %a %b
//       %memoryLayout %matrixInterpretation %matrixStride
// `a` has M components, `b` has K, and the M x K result is accumulated into the
// matrix the pointer addresses. There is no result: the matrix in memory is the
// destination. This instruction requires the CooperativeVectorTrainingNV
// capability (5435), which CapabilityVisitor adds from the instruction itself; a
// device that exposes only the inferencing half of VK_NV_cooperative_vector
// rejects the module.
// This overload is for the RowMajorNV and ColumnMajorNV layouts.
template <typename T, uint M, uint K,
          typename Accumulator,
          typename PointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Accumulator>::value>::ok,
          typename ComponentCheck = typename detail::ComponentTypeIsSupported<
              detail::IsSupportedComponent<T>::value>::ok>
[[vk::ext_instruction(/* OpCooperativeVectorOuterProductAccumulateNV */ 5290)]] void
OuterProductAccumulate([[vk::ext_reference]] Accumulator accumulator, uint offset,
                       CooperativeVector<T, M> a, CooperativeVector<T, K> b,
                      vk::CooperativeVectorMatrixLayout memoryLayout,
                      vk::CooperativeVectorComponentType matrixInterpretation,
                       uint matrixStride);

// As above, without the MatrixStride operand, for the InferencingOptimalNV and
// TrainingOptimalNV layouts.
template <typename T, uint M, uint K,
          typename Accumulator,
          typename PointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Accumulator>::value>::ok,
          typename ComponentCheck = typename detail::ComponentTypeIsSupported<
              detail::IsSupportedComponent<T>::value>::ok>
[[vk::ext_instruction(/* OpCooperativeVectorOuterProductAccumulateNV */ 5290)]] void
OuterProductAccumulate([[vk::ext_reference]] Accumulator accumulator, uint offset,
                       CooperativeVector<T, M> a, CooperativeVector<T, K> b,
                      vk::CooperativeVectorMatrixLayout memoryLayout,
                      vk::CooperativeVectorComponentType matrixInterpretation);

// Training: accumulates the sum of the components of a cooperative vector into
// an array in memory.
//   OpCooperativeVectorReduceSumAccumulateNV %ptr %offset %v
// Requires CooperativeVectorTrainingNV (5435), like OuterProductAccumulate.
template <typename T, uint N, typename Accumulator,
          typename PointerCheck = typename detail::PointerMustPointToArray<
              detail::IsArray<Accumulator>::value>::ok,
          typename ComponentCheck = typename detail::ComponentTypeIsSupported<
              detail::IsSupportedComponent<T>::value>::ok,
          typename CountCheck =
              typename detail::ComponentCountIsPositive<(N > 0)>::ok>
[[vk::ext_instruction(/* OpCooperativeVectorReduceSumAccumulateNV */ 5291)]] void
ReduceSumAccumulate([[vk::ext_reference]] Accumulator accumulator, uint offset,
                    CooperativeVector<T, N> v);

} // namespace nv
} // namespace vk

#endif // _HLSL_VK_NV_COOPERATIVE_VECTOR_H_
