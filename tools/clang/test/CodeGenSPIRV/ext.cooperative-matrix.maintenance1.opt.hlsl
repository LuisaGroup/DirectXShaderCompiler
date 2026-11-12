// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_EXT_cooperative_matrix_maintenance1 %s | FileCheck %s
// SPV_EXT_cooperative_matrix_maintenance1 after legalization and spirv-opt
// (G16/L6). No -fcgl here, so this is the module the driver would actually get:
// the header helpers are inlined into main, the optimizer's DCE, function
// inlining and capability trimming all run, and the result is validated. Both
// things that can only go wrong here are covered: an instruction that the
// optimizer removes or rewrites, and a capability that capability trimming
// throws away together with a "SPIR-V capability trimming" warning.
//
// The synthesized combine / per-element functions have to survive as well: they
// are only referenced by the reduce and per-element instructions, so nothing but
// that reference keeps them alive.
// CHECK: OpCapability CooperativeMatrixKHR
// CHECK-DAG: OpCapability CooperativeMatrixConversionsEXT
// CHECK-DAG: OpCapability CooperativeMatrixReductionsEXT
// CHECK-DAG: OpCapability CooperativeMatrixPerElementOperationsEXT
// CHECK-DAG: OpCapability CooperativeMatrixGetCoordinateEXT
// CHECK-DAG: OpExtension "SPV_EXT_cooperative_matrix_maintenance1"
// CHECK: OpMemoryModel
#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<int> outbuf;
int stride;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  using Acc = vk::khr::CooperativeMatrixAccumulator<int, vk::ScopeSubgroup, 16, 16>;
  using AccRow = vk::khr::CooperativeMatrixAccumulator<int, vk::ScopeSubgroup, 16, 1>;
  using MatA = vk::khr::CooperativeMatrixA<int, vk::ScopeSubgroup, 16, 16>;

  Acc acc = Acc::Splat(1);
  MatA asA = acc.ConvertUse<vk::CooperativeMatrixUseMatrixAKHR>();
  AccRow reduced = acc.Reduce<16, 1, vk::CooperativeMatrixReduceRow>();
  Acc perElement = acc.PerElementOp();
  uint2 coordinate = acc.GetCoordinate(tid.x);

  asA.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(outbuf, 0, stride);
  reduced.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(outbuf, 16, stride);
  perElement.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(outbuf, 32, stride);
  outbuf[64] = coordinate.x + coordinate.y;
}

// The four instructions are still there, with the same operands, and the two
// synthesized functions are still functions.
// CHECK-DAG: %__coopmat_combine = OpFunction {{%[A-Za-z0-9_]+}} None
// CHECK-DAG: %__coopmat_perelem = OpFunction {{%[A-Za-z0-9_]+}} None
// CHECK-DAG: OpCooperativeMatrixConvertUseEXT {{%[A-Za-z0-9_]+}} {{%[0-9]+}}
// CHECK-DAG: OpCooperativeMatrixReduceEXT {{%[A-Za-z0-9_]+}} {{%[0-9]+}} Row %__coopmat_combine
// CHECK-DAG: OpCooperativeMatrixPerElementOpEXT {{%[A-Za-z0-9_]+}} {{%[0-9]+}} %__coopmat_perelem
// CHECK-DAG: OpCooperativeMatrixGetCoordinateEXT %v2uint {{%[0-9]+}} {{%[0-9]+}}
