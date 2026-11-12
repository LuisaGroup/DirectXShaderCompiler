// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_EXT_cooperative_matrix_maintenance1 %s | FileCheck %s
// SPV_EXT_cooperative_matrix_maintenance1: one instruction per capability
// (G16/L0, G16/L1, G16/L2).
//
// The four entries exercised below are the whole surface the extension adds on
// top of SPV_KHR_cooperative_matrix:
//   CooperativeMatrix::ConvertUse      -> OpCooperativeMatrixConvertUseEXT (5293)
//   CooperativeMatrix::Reduce          -> OpCooperativeMatrixReduceEXT (5366)
//   CooperativeMatrix::PerElementOp    -> OpCooperativeMatrixPerElementOpEXT (5369)
//   CooperativeMatrix::GetCoordinate   -> OpCooperativeMatrixGetCoordinateEXT (5363)
// Each of them declares its own capability (5429, 5430, 5432, 5438) and, once for
// the module, OpExtension "SPV_EXT_cooperative_matrix_maintenance1".
//
// The opcodes are shared with the SPV_NV_cooperative_matrix2 spellings -
// OpCooperativeMatrixReduceNV is an alias of OpCooperativeMatrixReduceEXT, and
// CooperativeMatrixReductionsEXT / CooperativeMatrixPerElementOperationsEXT are
// aliases of the NV capabilities - so the opcode alone cannot tell the two
// spellings apart. What distinguishes them is the extension string, which is why
// this file asserts both the extension and the capabilities and asserts the
// absence of SPV_NV_cooperative_matrix2 and of CooperativeMatrixConversionsNV
// (5431), the one capability whose value differs between the two extensions.
//
// Passing -fspv-extension=SPV_EXT_cooperative_matrix_maintenance1 is what makes
// the extension explicit: it is registered in FeatureManager and enabled by
// default, but an explicit -fspv-extension list is an allow-list, so this also
// pins that the name is accepted (a typo is "unknown SPIR-V extension") and that
// a module using the four entry points validates.
//
// The capability and the extension are emitted once each, next to the
// SPV_KHR_cooperative_matrix ones, and the four of them are what makes each
// instruction legal - validation is left on, so a missing capability fails the
// compile before FileCheck sees the module.
// CooperativeMatrixConversionsNV (5431) is the one capability whose *value*
// differs from its EXT twin (5429), so it is the near-miss this file excludes;
// the NV extension string is excluded by the fact that
// OpExtension "SPV_EXT_cooperative_matrix_maintenance1" has to be present and
// splitting one module across both spellings is not something CodeGen can do.
// CHECK: OpCapability CooperativeMatrixKHR
// CHECK-NOT: CooperativeMatrixConversionsNV
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

  // Converts the accumulator use to the A use of the same shape. The result type
  // is the A-shaped OpTypeCooperativeMatrixKHR and the Matrix operand is the
  // source matrix; OpCooperativeMatrixConvertUseEXT takes no other operand.
  // CHECK-DAG: [[conv:%[0-9]+]] = OpCooperativeMatrixConvertUseEXT {{%[A-Za-z0-9_]+}} [[convsrc:%[0-9]+]]
  MatA asA = acc.ConvertUse<vk::CooperativeMatrixUseMatrixAKHR>();

  // Reduces 16x16 to 16x1 across rows. `Row` is the CooperativeMatrixReduce
  // literal (0x1), not an <id>: a run-time mode cannot be encoded, which the
  // header rules out by taking the mode as a template argument (see
  // ext.cooperative-matrix.maintenance1.reduce-mode.error.hlsl).
  // The last operand is the *function reference* CodeGen synthesizes for the
  // combine function; the OpFunction check below proves it is a function and not
  // a value.
  // CHECK-DAG: [[red:%[0-9]+]] = OpCooperativeMatrixReduceEXT {{%[A-Za-z0-9_]+}} [[redsrc:%[0-9]+]] Row %__coopmat_combine
  AccRow reduced = acc.Reduce<16, 1, vk::CooperativeMatrixReduceRow>();

  // Applies the per-element operation. The result type has to be identical to the
  // matrix type (ValidateCooperativeMatrixPerElementOp), and the referenced
  // function takes (row, column, value) and returns the component type.
  // CHECK-DAG: [[per:%[0-9]+]] = OpCooperativeMatrixPerElementOpEXT {{%[A-Za-z0-9_]+}} [[persrc:%[0-9]+]] %__coopmat_perelem
  Acc perElement = acc.PerElementOp();

  // Maps an element index to its coordinate. The Result Type has to be a
  // two-component 32-bit integer vector, which is %v2uint.
  // CHECK-DAG: [[coord:%[0-9]+]] = OpCooperativeMatrixGetCoordinateEXT %v2uint [[coordsrc:%[0-9]+]] {{%[0-9]+}}
  uint2 coordinate = acc.GetCoordinate(tid.x);

  // The two synthesized helpers really are functions, so the reduce and
  // per-element operands above name a function and not a value.
  // CHECK-DAG: %__coopmat_combine = OpFunction {{%[A-Za-z0-9_]+}} None
  // CHECK-DAG: %__coopmat_perelem = OpFunction {{%[A-Za-z0-9_]+}} None

  asA.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(outbuf, 0, stride);
  reduced.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(outbuf, 16, stride);
  perElement.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(outbuf, 32, stride);
  outbuf[64] = coordinate.x + coordinate.y;
}
