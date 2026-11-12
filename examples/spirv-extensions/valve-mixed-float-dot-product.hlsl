// RUN: %dxc -T cs_6_4 -E main -enable-16bit-types -spirv -fcgl -fspv-extension=SPV_VALVE_mixed_float_dot_product %s

// Mixed-float dot product with SPV_VALVE_mixed_float_dot_product
// (OpFDot2MixAcc32VALVE).
//
// dot2add(a, b, acc) computes a.x*b.x + a.y*b.y + acc where a and b are vectors
// of 16-bit floats and acc is a 32-bit float. It is the inner step of a packed
// FP16 dot product, e.g. half2 light or normal math accumulated in float.
//
// Without the extension SPIR-V has no instruction of that shape, so DXC rebuilds
// it out of scalar instructions:
//
//   %m  = OpFMul %v2half a b             ; each product rounded to FP16
//   %c  = OpFConvert %v2float %m         ; widened to FP32
//   %0  = OpCompositeExtract %float %c 0
//   %1  = OpCompositeExtract %float %c 1
//   %d  = OpFAdd %float %0 %1
//   %r  = OpFAdd %float %d acc
//
// The result therefore goes through several roundings and is not the correctly
// rounded value of the dot product.
//
// With -fspv-extension=SPV_VALVE_mixed_float_dot_product the whole thing is one
// instruction that rounds once:
//
//   %r = OpFDot2MixAcc32VALVE %float %a %b %acc
//   OpCapability DotProductFloat16AccFloat32VALVE
//   OpExtension "SPV_VALVE_mixed_float_dot_product"
//
// What the fusion buys: one rounding instead of several (a numerically better
// result, not merely a shorter instruction stream) and no materialization of the
// FP32 copies of the operand vectors. The capability is per (input encoding,
// accumulator) pair; DotProductFloat16AccFloat32VALVE is the FP16-in/FP32-out
// one, and it depends on the Float16 capability that the operand type already
// requires.
//
// Required from the host:
// * the device extension VK_VALVE_shader_mixed_float_dot_product enabled with
//   vkCreateDevice, and the feature bits described by that extension's feature
//   structure, queried with vkGetPhysicalDeviceFeatures2 and chained into
//   VkDeviceCreateInfo::pNext. The compiler cannot check any of it.
// * VALVE extensions are vendor-specific: a driver that does not expose this one
//   rejects a module that declares the capability. That is why DXC only emits the
//   instruction when the extension is requested explicitly and keeps the unfused
//   lowering otherwise (see docs/SPIR-V.rst).
// * SPIR-V 1.0 and any target environment DXC supports are enough; no
//   -fspv-target-env bump is needed.
//
// Only the (FP16 input, FP32 accumulator) form is reachable from HLSL: the single
// dot2add overload always accumulates in float, so OpFDot2MixAcc16VALVE has no
// call site, and the bfloat16 / FP8 variants need type systems that HLSL does not
// expose here (see docs/SPIR-V.rst).

RWStructuredBuffer<float> Result : register(u0);

[numthreads(1, 1, 1)]
void main() {
  half2 lightDir = half2(0.5, -0.25);
  half2 normal = half2(0.25, 0.75);
  float accumulated = 0.0;

  // One OpFDot2MixAcc32VALVE instead of six instructions:
  //   0.5 * 0.25 + (-0.25) * 0.75 + 0.0
  // The accumulator is the third operand, and the result type is its type.
  accumulated = dot2add(lightDir, normal, accumulated);

  // A second accumulation; the FP32 accumulator of the first call feeds the
  // third operand of the second.
  accumulated = dot2add(lightDir, -normal, accumulated);

  Result[0] = accumulated;
}
