// RUN: not %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl -fspv-extension=SPV_KHR_float_controls %s 2>&1 | FileCheck %s
//
// An explicit extension allow-list must include SPV_EXT_ocp_microscaling_types
// when one of its types is used: the type must not silently lower to something
// else (a wider float, or an 8-bit integer for the byte-sized format), and the
// extension must not be emitted behind the user's back. -fspv-extension
// establishes an allow-list, so naming a different extension is enough.
//
// CHECK: error: SPIR-V extension 'SPV_EXT_ocp_microscaling_types' required for float4_e2m1_t/float6_e3m2_t/float6_e2m3_t/float8_e8m0_t type but not permitted to use
#include <vk/ext/ocp_microscaling.h>

[numthreads(1, 1, 1)]
void main() {
  uint w = 0;
  float4_e2m1_t a = vk::mx::bitcast_extract_e2m1(w, 0);
  float8_e8m0_t s = float8_e8m0_t(1.0);
  float o = float(a) + float(s);
}
