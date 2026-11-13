// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 %s | FileCheck %s
//
// L6: the same formats and instruction as microscaling.basic.hlsl, but through
// the shipped post-processing (legalization, spirv-opt and the capability trim
// pass) instead of -fcgl. Three things can only break here: the optimizer
// rewriting OpFConvert on a 4- or 6-bit float, spirv-opt dropping an
// OpTypeFloat it does not understand, and the capability trim pass removing
// Float4EXT/Float6EXT/Float8UnsignedE8M0EXT/BitcastExtractEXT because it only
// sees opcodes it knows.
//
// This module is also the storage case: float8_e8m0_t is one byte, so it is a
// legal buffer element (ArrayStride 1) in the way the sub-byte formats are not.
//
// CHECK: OpCapability Float8UnsignedE8M0EXT
// CHECK: OpCapability Float4EXT
// CHECK: OpCapability Float6EXT
// CHECK: OpCapability BitcastExtractEXT
// CHECK: OpExtension "SPV_EXT_ocp_microscaling_types"
// CHECK-NOT: OpCapability Float16
// CHECK-NOT: OpCapability MXInt8EXT
// The byte-sized scale packs at one byte per element, like the float8 formats.
// CHECK: OpDecorate %_runtimearr_fp8e8m0 ArrayStride 1
// CHECK: %fp8e8m0 = OpTypeFloat 8 Float8UnsignedE8M0EXT
// CHECK: %fp4e2m1 = OpTypeFloat 4 Float4E2M1EXT
// CHECK: %fp6e3m2 = OpTypeFloat 6 Float6E3M2EXT
// CHECK: %fp6e2m3 = OpTypeFloat 6 Float6E2M3EXT
#include <vk/ext/ocp_microscaling.h>

RWStructuredBuffer<uint> Packed;
RWStructuredBuffer<float8_e8m0_t> Scales;
RWStructuredBuffer<float> Out;

[numthreads(1, 1, 1)]
void main() {
  uint w = Packed[0];
  // The extractions have to survive optimization with their encoded result
  // types.
  // CHECK: OpBitcastExtractEXT %fp4e2m1
  float4_e2m1_t q = vk::mx::bitcast_extract_e2m1(w, 0);
  // CHECK: OpBitcastExtractEXT %fp6e3m2
  float6_e3m2_t e = vk::mx::bitcast_extract_e3m2(w, 4);
  // CHECK: OpBitcastExtractEXT %fp6e2m3
  float6_e2m3_t m = vk::mx::bitcast_extract_e2m3(w, 10);
  // CHECK: OpLoad %fp8e8m0
  float8_e8m0_t s = Scales[0];
  // The conversions survive as well.
  // CHECK: OpFConvert %float
  float decoded = (float(q) + float(e) + float(m)) * float(s);
  Out[0] = decoded;
}
