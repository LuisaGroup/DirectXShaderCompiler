// Copyright (c) 2026 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// OCP micro-scaling types: VK_EXT_shader_ocp_microscaling_types /
// SPV_EXT_ocp_microscaling_types.
//
// The extension adds four sub-byte-or-byte floating point formats to SPIR-V,
// all of them `OpTypeFloat` with an FP encoding:
//
//   HLSL type        OpTypeFloat   encoding                    capability
//   float4_e2m1_t    4            Float4E2M1EXT (4225)         Float4EXT (4229)
//   float6_e3m2_t    6            Float6E3M2EXT (4224)         Float6EXT (4228)
//   float6_e2m3_t    6            Float6E2M3EXT (4223)         Float6EXT (4228)
//   float8_e8m0_t    8            Float8UnsignedE8M0EXT (4226) Float8UnsignedE8M0EXT (4230)
//
// and one instruction, OpBitcastExtractEXT (4195), gated by
// BitcastExtractEXT (4232):
//
//   OpBitcastExtractEXT %result %base %offset
//     Result Type  the micro-scaled value to extract (Float4EXT or Float6EXT
//                  in the Vulkan environment)
//     Base         an integer scalar or vector holding the packed bit fields;
//                  its bit width must be greater than the result's and its
//                  vector size must match the result's
//     Offset       a scalar integer bit offset into Base
//
// Why a value and not a variable: a 4- or 6-bit type is not addressable. SPIR-V
// only lets a variable containing one live in Function or Private storage, so a
// buffer of float4_e2m1_t does not exist. A packed word is loaded from an
// integer buffer and the field is extracted, which is exactly what this
// instruction is for. float8_e8m0_t is one byte, so it can be a buffer element
// like the float8 formats, and it is read with an ordinary load.
//
// Ranges (the same numbers the compiler uses for its range diagnostics):
//
//   float4_e2m1_t   -6 to 6        0.5 step below 1, 1 elsewhere; no inf, no NaN
//   float6_e3m2_t   -28 to 28      2^-4 subnormal, 28 is the largest finite
//   float6_e2m3_t   -7.5 to 7.5    2^-3 subnormal, 7.5 is the largest finite
//   float8_e8m0_t   2^-127 to 2^127 unsigned exponent only; 0xff is the NaN
//
// Conversion model (see docs/SPIR-V.rst):
//   - a micro-scaled value widens implicitly to float32/float64;
//   - converting it to float, double, half, bfloat16_t, float8_e4m3_t or
//     float8_e5m2_t needs an explicit cast and lowers to OpFConvert;
//   - a literal converts into one of the types, and folds to OpConstant;
//   - there is no conversion *into* a micro-scaled type other than a literal,
//     because SPIR-V forbids OpFConvert/OpConvertSToF/OpConvertUToF from
//     producing an OCP micro-scaling type (VUID-StandaloneSpirv-Result-12466
//     and -12465);
//   - no arithmetic, comparison, bitwise or unary operation is defined, and no
//     conversion to or from bool exists.
//
// Block scaling is not part of the extension: a micro-scaled value is a single
// format, and an MX block is a float8_e8m0_t scale times a vector of elements.
// The shader has to load the scale and multiply explicitly; the compiler emits
// no scale multiply and no tensor/MMA operation for any call in this header.
//
// What the host has to do is invisible to the compiler: the device must enable
// VkPhysicalDeviceShaderOcpMicroscalingTypesFeaturesEXT (shaderFloat4,
// shaderFloat6, shaderFloat8UnsignedE8M0 and shaderBitcastExtract) before a
// pipeline containing these types or this instruction may be created. The
// compiler emits the capability and the extension; it cannot check that the
// feature bits were enabled, and no driver behaviour is covered by this
// compiler's tests.
//
// The declarations below are compiler builtins: they have no definition
// anywhere, and SPIR-V CodeGen replaces each call with OpBitcastExtractEXT
// (SpirvEmitter::processSpvIntrinsicCallExpr). One OpCapability per call is
// contributed by the attribute; the per-format capabilities come from the
// types themselves (CapabilityVisitor::addCapabilityForType), so a shader that
// extracts both a 4-bit and a 6-bit value emits both Float4EXT and Float6EXT -
// which is what a mixed-format shader needs, since there is no per-format
// float4 capability.
#ifndef _HLSL_VK_EXT_OCP_MICROSCALING_H_
#define _HLSL_VK_EXT_OCP_MICROSCALING_H_

namespace vk {
namespace mx {

// Extract one float4_e2m1_t from `base` starting at bit `offset`.
// The 4-bit field is taken from the low bits of the result bit width, so the
// lanes of a packed word are Offset 0, 4, 8, ... and a word holds eight of
// them. Adds OpCapability Float4EXT (via the type) and BitcastExtractEXT.
[[vk::ext_instruction(4195)]]
[[vk::ext_capability(4232)]]
[[vk::ext_extension("SPV_EXT_ocp_microscaling_types")]]
float4_e2m1_t bitcast_extract_e2m1(uint32_t base, uint32_t offset);

[[vk::ext_instruction(4195)]]
[[vk::ext_capability(4232)]]
[[vk::ext_extension("SPV_EXT_ocp_microscaling_types")]]
float4_e2m1_t2 bitcast_extract_e2m1(uint2 base, uint32_t offset);

[[vk::ext_instruction(4195)]]
[[vk::ext_capability(4232)]]
[[vk::ext_extension("SPV_EXT_ocp_microscaling_types")]]
float4_e2m1_t4 bitcast_extract_e2m1(uint4 base, uint32_t offset);

// Extract one float6_e3m2_t. A 32-bit word holds five 6-bit fields plus two
// unused bits.
[[vk::ext_instruction(4195)]]
[[vk::ext_capability(4232)]]
[[vk::ext_extension("SPV_EXT_ocp_microscaling_types")]]
float6_e3m2_t bitcast_extract_e3m2(uint32_t base, uint32_t offset);

[[vk::ext_instruction(4195)]]
[[vk::ext_capability(4232)]]
[[vk::ext_extension("SPV_EXT_ocp_microscaling_types")]]
float6_e3m2_t2 bitcast_extract_e3m2(uint2 base, uint32_t offset);

[[vk::ext_instruction(4195)]]
[[vk::ext_capability(4232)]]
[[vk::ext_extension("SPV_EXT_ocp_microscaling_types")]]
float6_e3m2_t4 bitcast_extract_e3m2(uint4 base, uint32_t offset);

// Extract one float6_e2m3_t: the other 6-bit mantissa/exponent split.
[[vk::ext_instruction(4195)]]
[[vk::ext_capability(4232)]]
[[vk::ext_extension("SPV_EXT_ocp_microscaling_types")]]
float6_e2m3_t bitcast_extract_e2m3(uint32_t base, uint32_t offset);

[[vk::ext_instruction(4195)]]
[[vk::ext_capability(4232)]]
[[vk::ext_extension("SPV_EXT_ocp_microscaling_types")]]
float6_e2m3_t2 bitcast_extract_e2m3(uint2 base, uint32_t offset);

[[vk::ext_instruction(4195)]]
[[vk::ext_capability(4232)]]
[[vk::ext_extension("SPV_EXT_ocp_microscaling_types")]]
float6_e2m3_t4 bitcast_extract_e2m3(uint4 base, uint32_t offset);

} // namespace mx
} // namespace vk

#endif // _HLSL_VK_EXT_OCP_MICROSCALING_H_
