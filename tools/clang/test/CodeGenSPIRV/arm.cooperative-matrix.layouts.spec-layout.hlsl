// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -HV 2021 %s -spirv | FileCheck %s

// A MemoryLayout that is a specialization constant rather than a compile-time
// constant.
//
// SPV_ARM_cooperative_matrix_layouts requires the MemoryLayout operand to come
// from a constant instruction, and OpSpecConstant is one, so this is legal SPIR-V:
// the host still chooses between 4202, 4203 and the classic layouts at pipeline
// creation time. The compiler therefore cannot know which layout a module will use,
// and the capability is declared conservatively - a module may declare a capability
// it never exercises, but using an Arm enumerant without the capability is invalid,
// and SPIRV-Tools validates against the specialization constant's default value.
// The alternative - a diagnostic - would reject legal SPIR-V.
//
// This has to reach OpCooperativeMatrixStoreKHR directly: LoadBlockedInterleaved /
// StoreBlockedInterleaved take the layout as a template argument, which is always a
// compile-time constant. `_matrix` is the opaque cooperative matrix value the class
// wraps, which is the Object operand the store takes.

#include <vk/khr/cooperative_matrix.h>

// CHECK: OpCapability CooperativeMatrixLayoutsARM
// CHECK: OpExtension "SPV_ARM_cooperative_matrix_layouts"
[[vk::constant_id(0)]] const vk::CooperativeMatrixLayout g_layout =
    vk::CooperativeMatrixLayoutRowBlockedInterleavedARM;

// Defaults to 4202 (RowBlockedInterleavedARM); the host can set it to 0, 1 or 4203.
// The capability and the extension above are declared even though no Arm enumerant
// is a compile-time constant here.
// CHECK: %g_layout = OpSpecConstant %int 4202

RWStructuredBuffer<float> data;

[numthreads(64, 1, 1)]
void main() {
  using FloatMatA =
      vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, 16, 16>;

  // CHECK: OpCooperativeMatrixStoreKHR %{{[0-9]+}} %{{[0-9]+}} %g_layout %uint_1 None
  __builtin_spv_CooperativeMatrixStoreKHR(data[0], FloatMatA::Splat(1.0)._matrix,
                                          g_layout, 1u, vk::MemoryAccessMaskNone);
}
