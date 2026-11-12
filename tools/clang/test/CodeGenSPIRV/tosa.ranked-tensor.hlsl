// RUN: %dxc -T cs_6_0 -E main -fcgl %s -spirv | FileCheck %s

// L2 gate for the Rank operand of OpTypeTensorARM (4163), the type that the
// TOSA.001000.1 operations are defined over.
//
// This is the one thing the header *cannot* give a caller, so it is pinned here
// as a recipe rather than left in a comment. OpTypeTensorARM has two optional
// operands after the Element Type:
//
//   %t = OpTypeTensorARM %ElementType                      <- <vk/arm/tosa.h>
//   %t = OpTypeTensorARM %ElementType %Rank                <- this file
//   %t = OpTypeTensorARM %ElementType %Rank %Shape         <- not expressible
//
// Rank is the id of an integer constant, which vk::integral_constant<uint, N>
// supplies, so it is expressible. Shape is the id of an OpConstantComposite of an
// integer array whose length equals Rank, and the vk:: template-argument machinery
// carries types and integer constants but not a composite constant, so it is not:
// there is no spelling of "the tensor is 4x4" in this header, and no spelling in
// the compiler at all.
//
// A type with a Rank and no Shape is accepted by SPIRV-Tools -
// ValidateTypeTensorARM returns success as soon as it runs out of operands - and
// it is the half-specified form: the rank is known and the extent along each
// dimension is not. That is worth having, because a consumer that dispatches on
// rank (matrix operations are rank-2, reductions are rank-n) can read it, and it
// is what a hand-written declaration gets. This file is that declaration.
//
// The header's own operations take the unranked Tensor alias so that one
// declaration serves every tensor; see the note at the top of <vk/arm/tosa.h>.

// A ranked TOSA tensor: OpTypeTensorARM %float %uint_2.
template <typename ElementType>
using RankedTensor2 = vk::SpirvOpaqueType</* OpTypeTensorARM */ 4163, ElementType,
                                         vk::integral_constant<uint, 2> >;

// The same attributes <vk/arm/tosa.h> puts on its declarations. Both are needed
// because OpTypeTensorARM is in SPV_ARM_tensors: the capability and the extension
// belong to the type, and FeatureManager has no SPIR-V-side entry for
// SPV_ARM_tensors to infer them from.
[[vk::ext_extension("SPV_ARM_tensors")]]
[[vk::ext_capability(/* TensorsARM */ 4174)]]
[[vk::ext_instruction(/* ADD */ 14, "TOSA.001000.1")]]
RankedTensor2<float> AddRanked2(RankedTensor2<float> input1,
                                RankedTensor2<float> input2);

// A rank-2 operation on a rank-2 tensor: TOSA MATMUL is (A, B, A_zp, B_zp), so it
// is the operation that makes the rank interesting.
[[vk::ext_extension("SPV_ARM_tensors")]]
[[vk::ext_capability(/* TensorsARM */ 4174)]]
[[vk::ext_instruction(/* MATMUL */ 6, "TOSA.001000.1")]]
RankedTensor2<float> MatMulRanked2(RankedTensor2<float> A,
                                   RankedTensor2<float> B, int A_zp, int B_zp);

RWStructuredBuffer<float> g_out : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // L1: the same capability, extension and import string the header's operations
  // produce - the type, not the header, is what requires them.
  // CHECK: OpCapability TensorsARM
  // CHECK: OpExtension "SPV_ARM_tensors"
  // CHECK: %[[TOSA:[0-9]+]] = OpExtInstImport "TOSA.001000.1"

  // L2, the type: the Rank operand is the id of an OpConstant uint, so it appears
  // as %uint_2 and not as the literal 2. A module that wrote the literal would be
  // rejected by the validator ("OpTypeTensorARM Rank <id> ... is not a constant
  // instruction"), which is the near miss this line pins.
  // CHECK: %[[R2:[A-Za-z0-9_]+]] = OpTypeTensorARM %float %uint_2
  // CHECK-NOT: OpTypeTensorARM %float 2
  // Shape is the operand that would follow the rank and is not expressible, so the
  // type ends here.
  // CHECK-NOT: OpTypeTensorARM %float %uint_2 %{{[0-9]+}}

  RankedTensor2<float> a;
  RankedTensor2<float> b;

  // CHECK: %[[ADD:[0-9]+]] = OpExtInst %[[R2]] %[[TOSA]] ADD %{{[0-9]+}} %{{[0-9]+}}
  RankedTensor2<float> sum = AddRanked2(a, b);
  // The result travels through a Function-storage variable, because a tensor is
  // opaque and legalization cannot forward it; the OpLoad is the chained operand.
  // CHECK: OpStore %[[SUM:[A-Za-z0-9_]+]] %[[ADD]]
  // CHECK: %[[SUML:[0-9]+]] = OpLoad %[[R2]] %[[SUM]]
  // CHECK: %[[MUL:[0-9]+]] = OpExtInst %[[R2]] %[[TOSA]] MATMUL %[[SUML]] %{{[0-9]+}} %int_0 %int_0
  RankedTensor2<float> prod = MatMulRanked2(sum, b, 0, 0);

  g_out[0] = float(tid.x);
}
