// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fspv-target-env=vulkan1.3 %s

// VK_EXT_shader_ocp_microscaling_types (SPV_EXT_ocp_microscaling_types).
//
//   Requires SPV_EXT_float8 and a device that reports the extension with the
//   feature bits this shader uses.
//
// Four sub-byte-or-byte floating point formats plus one instruction to get a
// value out of packed storage:
//
//   float4_e2m1_t - 1 sign bit, 2 exponent bits (bias 1), 1 mantissa bit.
//                   Values {0, 0.5, 1, 1.5, 2, 3, 4, 6} and their negatives,
//                   so the range is -6 .. 6. No infinity and no NaN: every bit
//                   pattern is finite and anything larger saturates to 6.
//                   Two values per byte; four lanes of a 32-bit word.
//   float6_e3m2_t - 1/3/2 with a bias of 3: normal range 2^-2 .. 28, subnormals
//                   down to 2^-4. All 32 patterns finite. Five lanes plus two
//                   unused bits per 32-bit word.
//   float6_e2m3_t - 1/2/3 with a bias of 1: normal range 1 .. 7.5, subnormals
//                   down to 2^-3. All 32 patterns finite, one more mantissa bit
//                   and two fewer exponent decades than E3M2.
//   float8_e8m0_t - unsigned, 8 exponent bits with a bias of 127 and no
//                   significand: the value is exactly 2^(e-127), so the range is
//                   2^-127 .. 2^127. 0xff is the only NaN, and there is no zero
//                   and no negative value. This is the MX block scale, and it is
//                   one byte wide, so it is an ordinary buffer element.
//
// OpBitcastExtractEXT (4195, capability BitcastExtractEXT) takes an integer word
// (or a vector of words), a *scalar* bit offset, and a micro-scaled result type:
//
//   %v = OpBitcastExtractEXT %fp4e2m1 %word %uint_12
//
// The offset is the ABI's: lane i of a packed E2M1 stream starts at bit 4*i, and
// lane i of an E3M2/E2M3 stream at bit 6*i. That is why the format and the
// packing rule are the caller's business and not the compiler's - the offset
// reaches the instruction unchanged.
//
// A 4- or 6-bit type has no addressable storage. SPIR-V only allows a variable
// containing one in Function or Private storage, never in a buffer, so
//   RWStructuredBuffer<float4_e2m1_t>   // rejected: no addressable storage
// does not exist and is a compile error. Load the packed word as an integer and
// call vk::mx::bitcast_extract. The 8-bit scale is not affected.
//
// Conversion model:
//   float f = float(q);              // implicit widening to float32/float64
//   float d = double(q);             // explicit, OpFConvert
//   float8_e4m3_t w = float8_e4m3_t(q); // OpFConvert to E4M3, allowed
//   float4_e2m1_t bad = float4_e2m1_t(f); // rejected: see below
// SPIR-V forbids OpFConvert, OpConvertSToF and OpConvertUToF from *producing* an
// OCP micro-scaling type, so there is no conversion into one except from a
// literal, which folds to an OpConstant. There is no arithmetic, comparison,
// bitwise or unary operation on any of the four types and no conversion to or
// from bool: widen to float first.
//
// Block scaling is NOT part of the extension. An MX block is a float8_e8m0_t
// scale times a vector of elements, and applying that scale is the shader's job -
// the compiler emits no multiply for it. What would be needed for whole-block
// arithmetic is a tensor/MMA type (OpTypeTensorARM or a cooperative matrix) plus
// the scale application, which this extension does not define.
//
// What the host must do (the compiler cannot check any of it): enable the
// extension and VkPhysicalDeviceShaderOcpMicroscalingTypesFeaturesEXT's
// shaderFloat4, shaderFloat6, shaderFloat8UnsignedE8M0 and shaderBitcastExtract
// feature bits, and only then create a pipeline that contains the
// corresponding OpCapability. A shader that uses two formats declares two
// capabilities - there is no per-format float4 or float6 name - so the host has
// to check both.

#include <vk/ext/ocp_microscaling.h>

// A 32-bit word of eight packed float4_e2m1_t lanes, and a run of E3M2 lanes.
RWStructuredBuffer<uint> PackedFp4;
RWStructuredBuffer<uint> PackedFp6E3M2;
RWStructuredBuffer<uint> PackedFp6E2M3;

// float8_e8m0_t is one byte, so the per-block scale is an ordinary buffer.
// ArrayStride 1, like the float8 formats.
RWStructuredBuffer<float8_e8m0_t> BlockScale;

RWStructuredBuffer<float> Out;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint lane = tid.x;

  // Four E2M1 lanes per word: word `lane / 4`, field `lane % 4` at bit 4*(lane%4).
  uint word4 = PackedFp4[lane >> 2];
  uint offset4 = (lane & 3u) << 2;
  float4_e2m1_t element4 = vk::mx::bitcast_extract_e2m1(word4, offset4);

  // Five 6-bit lanes per word: word `lane / 5`, field `lane % 5` at bit 6*(lane%5).
  uint word6 = PackedFp6E3M2[lane / 5u];
  uint offset6 = (lane % 5u) * 6u;
  float6_e3m2_t element6 = vk::mx::bitcast_extract_e3m2(word6, offset6);

  // The other 6-bit split reads the same packing with a different encoding.
  float6_e2m3_t element6b = vk::mx::bitcast_extract_e2m3(word6, offset6);

  // Four lanes at once: the vector size of the base has to match the result's.
  float4_e2m1_t4 quad =
      vk::mx::bitcast_extract_e2m1(uint4(word4, word4, word4, word4), offset4);

  // The scale is loaded, not extracted. Applying it is the shader's job: this is
  // the MX dequantisation `x = scale * element`, and it is written out
  // explicitly because the compiler does not do it.
  float8_e8m0_t scale = BlockScale[lane >> 2];

  // Every micro-scaled value is consumed through a conversion; the arithmetic is
  // then ordinary float arithmetic.
  float decoded = (float(element4) + float(element6) + float(element6b) +
                   float(quad.z)) *
                  float(scale);

  Out[lane] = decoded;
}
