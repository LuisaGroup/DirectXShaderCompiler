// RUN: %dxc -T cs_6_0 -E main -HV 2021 %s -spirv | FileCheck %s

// L6: the float8 constants of float8.constant.hlsl after the full
// post-processing chain. The encoded 8-bit bit patterns have to survive the
// optimizer and the capability trim pass untouched; a pass that reinterpreted
// OpConstant of an OpTypeFloat 8 as a 32-bit value would corrupt them.
//
// CHECK: OpCapability Float8EXT
// CHECK-NOT: OpCapability Float8EXT
// CHECK: OpExtension "SPV_EXT_float8"
// CHECK-NOT: OpExtension "SPV_EXT_float8"

static const float8_e4m3_t c_zero = float8_e4m3_t(0.0);
static const float8_e4m3_t c_one_and_half = float8_e4m3_t(1.5);
static const float8_e5m2_t c_one_and_half_e5m2 = float8_e5m2_t(1.5);
static const float8_e4m3_t c_eighth = float8_e4m3_t(1.125);
static const float8_e5m2_t c_rounds_down = float8_e5m2_t(1.125);
static const float8_e4m3_t c_saturate = float8_e4m3_t(1000.0);
static const float8_e5m2_t c_max_e5m2 = float8_e5m2_t(57344.0);
static const float8_e4m3_t c_min_normal = float8_e4m3_t(0.015625);
static const float8_e4m3_t c_negzero = float8_e4m3_t(-0.0);

RWStructuredBuffer<float8_e4m3_t> OutE4M3;
RWStructuredBuffer<float8_e5m2_t> OutE5M2;
RWStructuredBuffer<float> Out;

[numthreads(1, 1, 1)]
void main() {
  // Storing the constants keeps them alive as OpConstant of the encoded 8-bit
  // type: the destination of each store is a float8 value, so the optimizer
  // cannot fold them into float constants.
  //
  // Each encoded type is declared next to the first constant that uses it, so
  // the type declaration is interleaved with the constants and is checked in
  // place.
  // CHECK: %fp8e4m3 = OpTypeFloat 8 Float8E4M3EXT
  // CHECK: OpConstant %fp8e4m3 0x0p+0
  // CHECK: OpConstant %fp8e4m3 0x1.8p+0
  // CHECK: %fp8e5m2 = OpTypeFloat 8 Float8E5M2EXT
  // CHECK: OpConstant %fp8e5m2 0x1.8p+0
  // CHECK: OpConstant %fp8e4m3 0x1.2p+0
  // CHECK: OpConstant %fp8e5m2 0x1p+0
  // A value above the E4M3 range stays saturated at the largest finite value.
  // CHECK: OpConstant %fp8e4m3 0x1.cp+8
  // CHECK: OpConstant %fp8e5m2 0x1.cp+15
  // CHECK: OpConstant %fp8e4m3 0x1p-6
  // CHECK: OpConstant %fp8e4m3 -0x0p+0
  // CHECK-NOT: OpTypeFloat 8{{$}}
  //
  // CHECK: OpStore {{%[0-9]+}} %fp8e4m3_0x0p_0
  OutE4M3[0] = c_zero;
  // CHECK: OpStore {{%[0-9]+}} %fp8e4m3_0x1_8p_0
  OutE4M3[1] = c_one_and_half;
  // CHECK: OpStore {{%[0-9]+}} %fp8e4m3_0x1_2p_0
  OutE4M3[2] = c_eighth;
  // CHECK: OpStore {{%[0-9]+}} %fp8e4m3_0x1_cp_8
  OutE4M3[3] = c_saturate;
  // CHECK: OpStore {{%[0-9]+}} %fp8e4m3_0x1pn6
  OutE4M3[4] = c_min_normal;
  // CHECK: OpStore {{%[0-9]+}} %fp8e4m3_n0x0p_0
  OutE4M3[5] = c_negzero;
  // CHECK: OpStore {{%[0-9]+}} %fp8e5m2_0x1_8p_0
  OutE5M2[0] = c_one_and_half_e5m2;
  // CHECK: OpStore {{%[0-9]+}} %fp8e5m2_0x1p_0
  OutE5M2[1] = c_rounds_down;
  // CHECK: OpStore {{%[0-9]+}} %fp8e5m2_0x1_cp_15
  OutE5M2[2] = c_max_e5m2;
  // 448 + 57344 folds to one float constant: the optimizer is free to fold the
  // conversion because the float8 constants themselves are still in the module.
  // CHECK: OpStore {{%[0-9]+}} %float_0x1p_128
  Out[0] = float(c_saturate) + float(c_max_e5m2);
}
