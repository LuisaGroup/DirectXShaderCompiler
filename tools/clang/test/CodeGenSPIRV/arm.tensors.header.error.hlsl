// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 -DELEMENT_TYPE %s -spirv 2>&1 | FileCheck %s --check-prefix=ELEMENT_TYPE
// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 -DRANK %s -spirv 2>&1 | FileCheck %s --check-prefix=RANK
// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 -DDIMENSION %s -spirv 2>&1 | FileCheck %s --check-prefix=DIMENSION

// L4 gates for the checks <vk/arm/tensors.h> performs in the front end, i.e. the
// mistakes a shader author makes by writing the header's names rather than a
// hand-written vk::SpirvOpaqueType (arm.tensors.rank.error.hlsl covers those).
//
// Each check is a type-alias template parameter that has a definition for the
// valid case only, so the diagnostic names the rule that was broken rather than
// a later, unrelated failure:
//
//  ELEMENT_TYPE - Tensor<float2, 2>: SPV_ARM_tensors has no encoding for a
//                 tensor of vectors, so the element type must be scalar.
//  RANK         - Tensor<float, 5>: Vulkan only guarantees a
//                 maxTensorDimensionCount of 4, so ranks 1..4 are the supported
//                 range; a higher one is refused here instead of becoming a
//                 pipeline-creation failure on a device that reports 4.
//  DIMENSION    - TensorSize<2>() on a rank-2 tensor: the dimension of
//                 OpTensorQuerySizeARM must be smaller than the rank, which the
//                 compiler knows because both are template arguments. The
//                 lowered instruction would be rejected by SPIRV-Tools
//                 ("Dimension (2) must be less than the Rank of Tensor (2)").
//
// The three diagnostics are front-end errors, so no SPIR-V is generated and no
// capability can leak; -Vd is not involved.

#include <vk/arm/tensors.h>

RWByteAddressBuffer outBuf : register(u0);

#ifdef ELEMENT_TYPE
// ELEMENT_TYPE: error: implicit instantiation of undefined template 'vk::arm::tensors_detail::ElementTypeIsScalar<false>'
// ELEMENT_TYPE: note: in instantiation of default argument for 'Tensor<vector<float, 2>, 2>'
vk::arm::Tensor<float2, 2> badElement;
#endif

#ifdef RANK
// RANK: error: implicit instantiation of undefined template 'vk::arm::tensors_detail::RankIsSupported<false>'
// RANK: note: in instantiation of default argument for 'Tensor<float, 5, int>'
vk::arm::Tensor<float, 5> badRank;
#endif

[numthreads(1, 1, 1)] void main() {
#ifdef DIMENSION
  vk::arm::Tensor<float, 2> tensor;
  // DIMENSION: error: no matching function for call to 'TensorSize'
  // DIMENSION: note: candidate template ignored: substitution failure
  // DIMENSION-SAME: implicit instantiation of undefined template 'vk::arm::tensors_detail::DimensionIsInRank<false>'
  outBuf.Store(0, vk::arm::TensorSize<2>(tensor));
#endif
}
