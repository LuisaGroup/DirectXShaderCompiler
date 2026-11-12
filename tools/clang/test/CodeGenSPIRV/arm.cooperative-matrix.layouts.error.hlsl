// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -HV 2021 -DBAD_STRIDE %s -spirv 2>&1 | FileCheck %s --check-prefix=STRIDE
// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -HV 2021 -DRUNTIME_STRIDE %s -spirv 2>&1 | FileCheck %s --check-prefix=RUNTIME

// L4 diagnostics for SPV_ARM_cooperative_matrix_layouts.
//
// Both are compile-time errors raised from the headers; without them the compiler
// would emit SPIR-V that spirv-val rejects:
//
//  STRIDE  - a Stride that is not 1, 2 or 4, or a (Rows, Columns, Stride) shape
//            the layout cannot describe. SPIRV-Tools' wording for the same
//            module is "MemoryLayout 4202 requires Stride be 1, 2, or 4" or
//            "... requires that the number of columns be a multiple of ...".
//  RUNTIME - one of the Arm layouts handed to the ordinary Load/Store entry
//            points, whose Stride is a run-time argument. SPV_ARM_cooperative_matrix_layouts
//            requires the Stride operand to come from a constant instruction,
//            and a run-time argument is lowered to an OpLoad, so those layouts
//            have to go through LoadBlockedInterleaved/StoreBlockedInterleaved.
//
// HLSL has no static_assert before -HV 202x, so the headers report both cases by
// instantiating a class template that only has a definition for `true`. The note
// that follows the error names the HLSL call site.

#include <vk/arm/cooperative_matrix_layouts.h>

RWStructuredBuffer<float> data;

using FloatMatA = vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, 16, 16>;

#ifdef BAD_STRIDE
// Stride 3 is not one of 1, 2, 4.
// STRIDE: error: implicit instantiation of undefined template 'vk::arm::BlockedInterleavedLayoutIsSupported<false>'
// STRIDE: note: in instantiation of function template specialization 'vk::khr::CooperativeMatrix<float, vk::Scope::ScopeSubgroup, 16, 16, vk::CooperativeMatrixUse::CooperativeMatrixUseMatrixAKHR>::LoadBlockedInterleaved<vk::CooperativeMatrixLayout::CooperativeMatrixLayoutRowBlockedInterleavedARM, 3, float>' requested here
// STRIDE: FloatMatA::LoadBlockedInterleaved<
[numthreads(64, 1, 1)]
void main() {
  FloatMatA m = FloatMatA::LoadBlockedInterleaved<
      vk::CooperativeMatrixLayoutRowBlockedInterleavedARM, 3>(data, 0);
}
#endif

#ifdef RUNTIME_STRIDE
// The stride is passed as an argument, which the Arm layouts cannot accept.
// RUNTIME: error: implicit instantiation of undefined template 'vk::arm::RuntimeStrideIsValidForLayout<false>'
// RUNTIME: note: in instantiation of function template specialization 'vk::khr::CooperativeMatrix<float, vk::Scope::ScopeSubgroup, 16, 16, vk::CooperativeMatrixUse::CooperativeMatrixUseMatrixAKHR>::Load<vk::CooperativeMatrixLayout::CooperativeMatrixLayoutRowBlockedInterleavedARM, float>' requested here
// RUNTIME: FloatMatA::Load<
[numthreads(64, 1, 1)]
void main() {
  FloatMatA m = FloatMatA::Load<
      vk::CooperativeMatrixLayoutRowBlockedInterleavedARM>(data, 0, 1);
}
#endif
