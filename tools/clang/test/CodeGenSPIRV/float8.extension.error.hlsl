// RUN: not %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl -fspv-extension=SPV_KHR_float_controls %s 2>&1 | FileCheck %s

// An explicit extension allow-list must include SPV_EXT_float8 when a float8
// type is used: the type must not silently lower to something else (a plain
// 8-bit integer or a wider float), and the extension must not be emitted behind
// the user's back.
//
// CHECK: error: SPIR-V extension 'SPV_EXT_float8' required for float8_e4m3_t/float8_e5m2_t type but not permitted to use
[numthreads(1, 1, 1)]
void main() {
  float8_e4m3_t value = float8_e4m3_t(1.0);
  float4 o = float4(float(value), 0, 0, 0);
}
