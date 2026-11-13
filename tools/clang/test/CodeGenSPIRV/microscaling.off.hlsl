// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl %s | FileCheck %s
//
// L5: a shader that only uses float8 and bfloat16_t gains nothing from
// SPV_EXT_ocp_microscaling_types. No capability of the extension, no
// OpBitcastExtractEXT, and no micro-scaled OpTypeFloat may appear, and the
// float8 output must be byte-for-byte what it was before the extension landed.
//
// The CHECK-NOT region is anchored between two CHECKs so that it is not
// vacuous: it covers the capability block, the extension block and the whole
// type/constant section.
//
// CHECK: OpCapability Float8EXT
// CHECK: OpCapability BFloat16TypeKHR
// CHECK-NOT: OpCapability Float4EXT
// CHECK-NOT: OpCapability Float6EXT
// CHECK-NOT: OpCapability Float8UnsignedE8M0EXT
// CHECK-NOT: OpCapability BitcastExtractEXT
// CHECK-NOT: OpCapability MXInt8EXT
// CHECK: OpExtension "SPV_EXT_float8"
// CHECK-NOT: OpExtension "SPV_EXT_ocp_microscaling_types"
// CHECK: OpMemoryModel
// CHECK-NOT: OpTypeFloat 4
// CHECK-NOT: OpTypeFloat 6
// CHECK-NOT: OpBitcastExtractEXT
// CHECK: %fp8e4m3 = OpTypeFloat 8 Float8E4M3EXT
// CHECK: %bfloat16 = OpTypeFloat 16 BFloat16KHR
// CHECK-NOT: OpTypeFloat 8 Float8UnsignedE8M0EXT
// CHECK: OpFunction
// CHECK-NOT: OpBitcastExtractEXT

[numthreads(1, 1, 1)]
void main() {
  // The float8 and bfloat16 paths are untouched: one OpFConvert each way.
  // A non-literal source is what produces the conversion instead of a folded
  // OpConstant.
  float f = 1.5;
  // CHECK: OpFConvert %fp8e4m3
  float8_e4m3_t e4m3 = float8_e4m3_t(f);
  // CHECK: OpFConvert %bfloat16
  bfloat16_t bf = bfloat16_t(f);
  // CHECK: OpFConvert %float
  float sum = float(e4m3) + float(bf);
}
