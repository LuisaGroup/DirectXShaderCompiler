// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl %s | FileCheck %s

// Constants of the SPV_EXT_float8 types.
//
// A float8 constant is an OpConstant whose type is the encoded OpTypeFloat 8, so
// the 8-bit encoding has to be produced by the constant evaluator (the APFloat
// semantics attached to float8_e4m3_t / float8_e5m2_t). The printed hex float is
// the decoded value of the encoded byte, which pins both the rounding and the bit
// positions of the format.
//
// The constants below are declared in the order in which they are checked,
// because each encoding's type declaration is emitted next to its first constant.

// CHECK: OpCapability Float8EXT
// CHECK-NOT: OpCapability Int8
// CHECK-NOT: OpCapability Float16
// CHECK: OpExtension "SPV_EXT_float8"
// CHECK-NOT: OpExtension "SPV_EXT_float8"

// Zero, in both formats.
// CHECK: %fp8e4m3 = OpTypeFloat 8 Float8E4M3EXT
// CHECK: OpConstant %fp8e4m3 0x0p+0
static const float8_e4m3_t c_zero_e4m3 = float8_e4m3_t(0.0);

// CHECK: %fp8e5m2 = OpTypeFloat 8 Float8E5M2EXT
// CHECK: OpConstant %fp8e5m2 0x0p+0
static const float8_e5m2_t c_zero_e5m2 = float8_e5m2_t(0.0);

// 1.5 is exactly representable in both formats (0x38 for E4M3, 0x3E for E5M2).
// CHECK: OpConstant %fp8e4m3 0x1.8p+0
static const float8_e4m3_t c_1_5_e4m3 = float8_e4m3_t(1.5);

// CHECK: OpConstant %fp8e5m2 0x1.8p+0
static const float8_e5m2_t c_1_5_e5m2 = float8_e5m2_t(1.5);

// 1.125 is exactly representable in E4M3 (0x32: one of its three mantissa bits)
// but is a halfway case in E5M2, which only has two mantissa bits, so it rounds
// to 1.0 (0x3C) under round-to-nearest-even. E4M3 and E5M2 therefore must not
// share an implementation.
// CHECK: OpConstant %fp8e4m3 0x1.2p+0
static const float8_e4m3_t c_precise_e4m3 = float8_e4m3_t(1.125);

// CHECK: OpConstant %fp8e5m2 0x1p+0
static const float8_e5m2_t c_rounded_e5m2 = float8_e5m2_t(1.125);

// The largest finite E4M3 value is 448 (exponent bias 7 and no infinity): a
// value above it saturates instead of becoming infinite, without a diagnostic.
// CHECK: OpConstant %fp8e4m3 0x1.cp+8
static const float8_e4m3_t c_saturate = float8_e4m3_t(1000.0);

// The largest finite E5M2 value is 57344 (0x7B).
// CHECK: OpConstant %fp8e5m2 0x1.cp+15
static const float8_e5m2_t c_max_e5m2 = float8_e5m2_t(57344.0);

// E5M2 does have an infinity (0x7C), which the shader below exercises. The
// vendored disassembler prints that 8-bit pattern as 0x1p+16 rather than as an
// infinity, so it is only asserted as "not the largest finite value": the value
// is pinned by the E5M2 maximum above and by the encoding itself.
// CHECK-NOT: OpConstant %fp8e5m2 0x1.cp+15
static const float8_e5m2_t c_inf_e5m2 = float8_e5m2_t(1e30);

// The smallest normal values are 2^-6 (E4M3) and 2^-14 (E5M2), the smallest
// subnormals 2^-9 and 2^-16.
// CHECK: OpConstant %fp8e4m3 0x1p-6
static const float8_e4m3_t c_min_normal = float8_e4m3_t(0.015625);

// CHECK: OpConstant %fp8e5m2 0x1p-14
static const float8_e5m2_t c_min_normal_e5m2 = float8_e5m2_t(0.00006103515625);

// CHECK: OpConstant %fp8e4m3 0x1p-9
static const float8_e4m3_t c_min_subnormal = float8_e4m3_t(0.001953125);

// CHECK: OpConstant %fp8e5m2 0x1p-16
static const float8_e5m2_t c_min_subnormal_e5m2 =
    float8_e5m2_t(0.0000152587890625);

// A negative zero keeps its sign bit.
// CHECK: OpConstant %fp8e4m3 -0x0p+0
static const float8_e4m3_t c_negzero = float8_e4m3_t(-0.0);

[numthreads(1, 1, 1)]
void main() {
  // The constants are used through a conversion, so that they are emitted even
  // without the optimizer.
  float x = float(c_zero_e4m3) + float(c_zero_e5m2) + float(c_1_5_e4m3) +
            float(c_1_5_e5m2) + float(c_precise_e4m3) + float(c_rounded_e5m2) +
            float(c_saturate) + float(c_max_e5m2) + float(c_inf_e5m2) +
            float(c_min_normal) + float(c_min_normal_e5m2) +
            float(c_min_subnormal) + float(c_min_subnormal_e5m2) +
            float(c_negzero);
  float4 o = float4(x, 0, 0, 0);
}
