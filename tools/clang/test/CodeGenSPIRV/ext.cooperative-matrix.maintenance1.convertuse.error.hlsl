// RUN: not %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 %s 2>&1 | FileCheck %s
// SPV_EXT_cooperative_matrix_maintenance1: the use pairing ConvertUse forbids
// (G16/L4).
//
// OpCooperativeMatrixConvertUseEXT converts between the accumulator use and the
// A/B uses. It is *not* a general reinterpretation: with the
// CooperativeMatrixConversionsEXT capability, external/SPIRV-Tools
// (ValidateCooperativeMatrix in source/val/validate_conversion.cpp) requires one
// side to be MatrixAccumulatorKHR and the other MatrixAKHR or MatrixBKHR, and
// rejects exactly the module this shader asks for with
//   "Matrix and Result Type must convert between MatrixAccumulatorKHR and
//    MatrixAKHR or MatrixBKHR"
// so the header rejects it at compile time instead, by instantiating a class
// template that only has a definition for `true`
// (vk::khr::ConvertUseIsSupported<false>, the mechanism
// <vk/arm/cooperative_matrix_layouts.h> uses).
//
// The note that follows the error points at the call site below.
// CHECK: error: implicit instantiation of undefined template 'vk::khr::ConvertUseIsSupported<false>'
// CHECK: note: in instantiation of function template specialization
// CHECK-SAME: ConvertUse<
#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<int> outbuf;
int stride;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  using Acc = vk::khr::CooperativeMatrixAccumulator<int, vk::ScopeSubgroup, 16, 16>;
  using MatA = vk::khr::CooperativeMatrixA<int, vk::ScopeSubgroup, 16, 16>;
  using MatB = vk::khr::CooperativeMatrixB<int, vk::ScopeSubgroup, 16, 16>;

  Acc acc = Acc::Splat(1);
  // Accumulator -> A is one of the conversions the extension allows ...
  MatA asA = acc.ConvertUse<vk::CooperativeMatrixUseMatrixAKHR>();
  // ... A -> B is not: both sides are already in the "input" position, so the
  // conversion would reinterpret the values rather than move them between the
  // input and the accumulator roles.
  MatB asB = asA.ConvertUse<vk::CooperativeMatrixUseMatrixBKHR>();
  asB.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(outbuf, 0, stride);
}
