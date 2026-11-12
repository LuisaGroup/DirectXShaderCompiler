// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fspv-target-env=vulkan1.3 %s

// VK_KHR_shader_bfloat16 (SPV_KHR_bfloat16).
//
// bfloat16 is IEEE 754 binary32 with the significand truncated to 7 stored
// bits: float's 8-bit exponent range with roughly three significant decimal
// digits.
// That is the shape a machine-learning weight/activation type wants - the range
// of float without the bandwidth of float.
//
// HLSL surface: bfloat16_t, a real builtin type (bfloat16_t2 .. bfloat16_t4,
// bfloat16_t2x2, structs and arrays of it). It is SPIR-V only, it needs HLSL
// 2018 or later, and it does not need -enable-16bit-types: the type is always
// 16 bits wide.
//
// The extension defines no arithmetic, comparison or bitwise operation for the
// type. It is a storage and conversion type plus three capabilities:
//
//   BFloat16TypeKHR              (5116) - the type itself: OpTypeFloat 16 with
//                                         the BFloat16KHR encoding operand, and
//                                         OpFConvert to and from other floats
//   BFloat16DotProductKHR        (5117) - OpDot with a bfloat16 component type
//   BFloat16CooperativeMatrixKHR (5118) - OpTypeCooperativeMatrixKHR with a
//                                         bfloat16 component type
//
// The conversion model is widening only: bfloat16_t converts implicitly to
// float/float64 (scalars, vectors and matrices), and every other conversion -
// narrowing to bfloat16_t, to or from integer types, to or from float16_t, to
// or from bool - needs an explicit constructor. bfloat16_t and float16_t never
// mix.
// VK_KHR_shader_bfloat16 also forbids the BFloat16KHR encoding in the Input and
// Output storage classes, so bfloat16_t cannot be a stage input or output; pass
// values between stages as float.
//
// Required from the host:
// * Vulkan device extension VK_KHR_shader_bfloat16 (add
//   VK_KHR_SHADER_BFLOAT16_EXTENSION_NAME at vkCreateDevice),
// * feature bits VkPhysicalDeviceShaderBfloat16FeaturesKHR::shaderBFloat16Type,
//   shaderBFloat16DotProduct and shaderBFloat16CooperativeMatrix (query via
//   vkGetPhysicalDeviceFeatures2, chain the struct with the required bits set to
//   VK_TRUE into VkDeviceCreateInfo::pNext). shaderBFloat16Type must be
//   supported and at least one of the other two must be supported;
//   shaderBFloat16CooperativeMatrix additionally requires the
//   VK_KHR_cooperative_matrix device extension and its cooperativeMatrix
//   feature, and the shapes and component types it permits must be queried with
//   vkGetPhysicalDeviceCooperativeMatrixPropertiesKHR.
// * the module declares OpCapability BFloat16TypeKHR (plus
//   BFloat16DotProductKHR / BFloat16CooperativeMatrixKHR where used) and
//   OpExtension "SPV_KHR_bfloat16". Cooperative matrices need SPIR-V 1.6, hence
//   -fspv-target-env=vulkan1.3 above.
//
// A driver without the feature bits rejects a module that declares the
// capabilities, which is why the compiler cannot paper over the host half.
// See docs/SPIR-V.rst for the full description.

#include <vk/khr/cooperative_matrix.h>

// bfloat16_t as a storage type: one bfloat16 block of weights and one float
// result array. Structured buffer members keep 2-byte size and 2-byte alignment
// regardless of -enable-16bit-types.
RWStructuredBuffer<bfloat16_t> Weights;
RWStructuredBuffer<float> Result;

// A bfloat16 vector dot product: OpDot %bfloat16 with BFloat16DotProductKHR,
// not a widened float dot product.
bfloat16_t bfloat16Dot(RWStructuredBuffer<bfloat16_t> weights, uint base) {
  bfloat16_t4 a = bfloat16_t4(weights[base], weights[base + 1],
                              weights[base + 2], weights[base + 3]);
  bfloat16_t4 b = bfloat16_t4(weights[base + 4], weights[base + 5],
                              weights[base + 6], weights[base + 7]);
  // One OpDot %bfloat16 %a %b; no OpFConvert on the operands.
  return dot(a, b);
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
  uint base = id.x * 8;

  // Widening conversion: bfloat16_t -> float is implicit and lowers to
  // OpFConvert %float. The other direction needs an explicit constructor.
  bfloat16_t w = Weights[id.x];
  float widened = w;
  Result[id.x] = widened;

  // The dot product accumulates in bfloat16, so bfloat16_t is its natural
  // destination. A float destination widens the result instead of the operands
  // (OpDot %bfloat16 followed by OpFConvert %float); that rounding is inherent
  // to the capability.
  bfloat16_t d = bfloat16Dot(Weights, base);
  float df = d;
  Result[id.x + 1] = df;

  // Arithmetic is not defined for bfloat16_t, so it has to be converted first.
  // (w * 2.0 would be a compile error.)
  Result[id.x + 2] = float(w) * 2.0;

  // BFloat16CooperativeMatrixKHR: a cooperative matrix whose component type is
  // bfloat16. The module additionally declares
  // OpCapability BFloat16CooperativeMatrixKHR next to CooperativeMatrixKHR, and
  // OpCooperativeMatrixMulAddKHR carries no Matrix*SignedComponentsKHR bits
  // because a bfloat16 component is not an integer type.
  using CoopMatA =
      vk::khr::CooperativeMatrixA<bfloat16_t, vk::ScopeSubgroup, 16, 8>;
  using CoopMatB =
      vk::khr::CooperativeMatrixB<bfloat16_t, vk::ScopeSubgroup, 8, 8>;
  using CoopMatAcc =
      vk::khr::CooperativeMatrixAccumulator<bfloat16_t, vk::ScopeSubgroup, 16,
                                            8>;

  CoopMatA a = CoopMatA::Load<vk::CooperativeMatrixLayoutColumnMajorKHR>(
      Weights, base, 64);
  CoopMatB b = CoopMatB::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(
      Weights, base, 64);
  CoopMatAcc c = CoopMatAcc::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(
      Weights, base, 64);
  CoopMatAcc r = vk::khr::cooperativeMatrixMultiplyAdd(a, b, c);
  r.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(Weights, base, 64);
}
