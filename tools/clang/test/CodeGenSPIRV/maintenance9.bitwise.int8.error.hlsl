// RUN: not %dxc -T cs_6_2 -E main -enable-16bit-types -fcgl %s -spirv 2>&1 | FileCheck %s

// Negative control for maintenance9.bitwise.int8.hlsl: the same module without
// -fspv-enable-maintenance9, i.e. a device that does not report the maintenance9
// feature, must be rejected by the SPIR-V validator exactly as before. This is
// the diagnostic the extension removes, produced by SPIRV-Tools'
// validate_bitwise.cpp and not by DXC.

// CHECK: fatal error: generated SPIR-V is invalid: [VUID-RuntimeSpirv-None-10824] Expected 32-bit int type for Base operand: BitReverse
// CHECK-NEXT: This is allowed if you enable the maintenance9 feature (or use the --allow-vulkan-32-bit-bitwise command line flag)
// CHECK: OpBitReverse %uchar

RWStructuredBuffer<uint> buf;

[[vk::ext_instruction(/* OpBitReverse */ 204)]]
uint8_t bitReverse8(uint8_t v);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint8_t v = (uint8_t)tid.x;
  uint r8 = (uint)bitReverse8(v);
  buf[0] = r8;
}
