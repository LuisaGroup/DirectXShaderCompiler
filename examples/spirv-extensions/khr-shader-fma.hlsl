// RUN: %dxc -T cs_6_0 -E main -spirv -fcgl -fspv-extension=SPV_KHR_fma %s

// Fused multiply-add with SPV_KHR_fma (OpFmaKHR).
//
// A fused multiply-add computes a * b + c with a single rounding: the product is
// not rounded before the addition. That matters whenever the intermediate
// precision is what a numeric result depends on - compensated summation,
// polynomial evaluation, matrix and geometry math - and an *unfused* a * b + c
// loses those bits permanently.
//
// The GLSL.std.450 "Fma" extended instruction only asks for a fused
// multiply-add; the SPIR-V core instruction OpFmaKHR requires it and can only be
// produced when the device advertises support for it.
//
// Required from the host:
//   * Vulkan device extension  VK_KHR_shader_fma  (enable the extension name
//     VK_KHR_SHADER_FMA_EXTENSION_NAME at vkCreateDevice),
//   * feature bit             VkPhysicalDeviceShaderFmaFeaturesKHR::shaderFmaFloat32
//     (query it via vkGetPhysicalDeviceFeatures2 and enable it by chaining a
//     VkPhysicalDeviceShaderFmaFeaturesKHR structure with shaderFmaFloat32 set
//     to VK_TRUE into VkDeviceCreateInfo::pNext),
//   * SPIR-V 1.0 is enough; no target environment bump is needed.
// Without them the driver rejects a module that declares the FMAKHR capability,
// which is why DXC only emits OpFmaKHR when the extension is enabled with
// -fspv-extension=SPV_KHR_fma (see docs/SPIR-V.rst).
//
// HLSL note: mad() is the intrinsic that accepts 'float' and is what lowers to
// OpFmaKHR. fma() is a 'double'-only intrinsic (it maps to dx.op.fma) and keeps
// the GLSL.std.450 form, as do 16-bit float operands.
//
// Scalar example: 5 * 3 + 2 == 17, computed as one fused operation.
// Vector example: component-wise fused multiply-add of a 4-component position.

RWStructuredBuffer<float4> Result : register(u0);

[numthreads(1, 1, 1)]
void main() {
  float a = 5.0;
  float b = 3.0;
  float c = 2.0;

  // One OpFmaKHR %float: no rounding of a * b before the addition.
  float scalar = mad(a, b, c);

  // One OpFmaKHR %v4float: fused component-wise, not four unfused
  // multiplies followed by four adds.
  float4 position = float4(0.5, 1.5, -2.0, 3.25);
  float4 scale = float4(2.0, 2.0, 2.0, 2.0);
  float4 offset = float4(1.0, -1.0, 0.25, 0.75);
  float4 transformed = mad(position, scale, offset);

  Result[0] = float4(scalar, transformed.x + transformed.y,
                     transformed.z, transformed.w);
}
