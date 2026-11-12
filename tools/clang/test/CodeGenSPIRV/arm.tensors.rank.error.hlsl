// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 -DRANK_ZERO %s -spirv 2>&1 | FileCheck %s --check-prefix=RANK_ZERO
// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 -DRANK_FIVE %s -spirv 2>&1 | FileCheck %s --check-prefix=RANK_FIVE
// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 -DVECTOR_ELEMENT %s -spirv 2>&1 | FileCheck %s --check-prefix=VECTOR_ELEMENT

// L4 gates: the two properties of OpTypeTensorARM that SPV_ARM_tensors and
// Vulkan constrain, checked for hand-written types - the spellings that bypass
// <vk/arm/tensors.h> and its template checks (those are
// arm.tensors.header.error.hlsl). Both are the "would otherwise be invalid
// SPIR-V" cases:
//
//  RANK_ZERO       - SPIRV-Tools: "OpTypeTensorARM Rank <id> ... must define a
//                    value greater than 0." A rank of 0 has no meaning: the
//                    tensor has no dimensions to name.
//  RANK_FIVE       - Vulkan requires every implementation that supports
//                    VK_ARM_tensors to report a maxTensorDimensionCount of at
//                    least 4, so a rank of 5 is outside the range every device
//                    supports. SPIRV-Tools does not reject it, and the module
//                    would then fail at pipeline creation on a device that
//                    reports exactly the guaranteed minimum, so the compiler
//                    refuses it and names the limit.
//  VECTOR_ELEMENT  - SPIRV-Tools: "OpTypeTensorARM Element Type <id> is not a
//                    scalar type." A tensor of float2 has no encoding in the
//                    extension.

#ifdef RANK_ZERO
using BadTensor = vk::SpirvOpaqueType</* OpTypeTensorARM */ 4163, float,
                                      vk::integral_constant<uint, 0> >;
// RANK_ZERO: error: the rank of a tensor (vk::arm::Tensor) must be between 1 and 4
// RANK_ZERO-SAME: maxTensorDimensionCount of 4
// RANK_ZERO-NOT: OpCapability TensorsARM
#endif

#ifdef RANK_FIVE
using BadTensor = vk::SpirvOpaqueType</* OpTypeTensorARM */ 4163, float,
                                      vk::integral_constant<uint, 5> >;
// RANK_FIVE: error: the rank of a tensor (vk::arm::Tensor) must be between 1 and 4
// RANK_FIVE-SAME: maxTensorDimensionCount of 4
// RANK_FIVE-NOT: OpCapability TensorsARM
#endif

#ifdef VECTOR_ELEMENT
using BadTensor = vk::SpirvOpaqueType</* OpTypeTensorARM */ 4163, float2,
                                      vk::integral_constant<uint, 2> >;
// VECTOR_ELEMENT: error: the element type of a tensor (vk::arm::Tensor) must be a scalar type
// VECTOR_ELEMENT-SAME: is not a scalar
// VECTOR_ELEMENT-NOT: OpCapability TensorsARM
#endif

using BadCoordinates = vk::SpirvOpaqueType</* OpTypeArray */ 28, uint,
                                           vk::integral_constant<uint, 2> >;

[[vk::ext_instruction(/* OpTensorReadARM */ 4164)]] float
BadRead(BadTensor tensor, BadCoordinates coordinates);

RWByteAddressBuffer outBuf : register(u0);

[numthreads(1, 1, 1)] void main() {
  BadTensor tensor;
  BadCoordinates coordinates;
  // The tensor is used, so the diagnostic is not about an unused typedef: the
  // capability is only withheld because the type - and therefore the module - is
  // rejected first.
  outBuf.Store(0, asuint(BadRead(tensor, coordinates)));
}
