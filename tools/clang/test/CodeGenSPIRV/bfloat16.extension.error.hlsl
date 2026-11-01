// RUN: not %dxc -T cs_6_0 -E main -spirv -HV 2018 -fcgl -Vd -fspv-extension=SPV_KHR_16bit_storage %s 2>&1 | FileCheck %s

// An explicit extension allowlist must include SPV_KHR_bfloat16 when BF16 is
// used; the type must not silently fall back to Float16.

// CHECK: error: SPIR-V extension 'SPV_KHR_bfloat16' required for bfloat16_t type but not permitted to use

[numthreads(1, 1, 1)]
void main() {
  bfloat16_t value = bfloat16_t(1.0);
}
