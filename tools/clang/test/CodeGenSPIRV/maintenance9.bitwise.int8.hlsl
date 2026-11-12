// RUN: %dxc -T cs_6_2 -E main -enable-16bit-types -fcgl -fspv-enable-maintenance9 %s -spirv | FileCheck %s

// The maintenance9 relaxation covers 8-bit widths as well: the Vulkan rule
// VUID-RuntimeSpirv-None-10824 that required a 32-bit Base operand applied to
// OpBitReverse, OpBitCount, OpBitFieldInsert, OpBitFieldSExtract and
// OpBitFieldUExtract, and the extension removes it for all integer widths.
// 8-bit is not reachable through the HLSL reversebits/countbits builtins - the
// front end has no int8_t/uint8_t overload for them (the Sema overload set
// "any_int" is 16/32/64-bit, so an 8-bit operand is promoted to int first, see
// maintenance9.reversebits.hlsl) - but it is reachable through inline SPIR-V,
// which is what this test uses.
// Without -fspv-enable-maintenance9 the same module is rejected by the
// validator; maintenance9.bitwise.int8.error.hlsl asserts that diagnostic.

// CHECK: OpCapability Int8

RWStructuredBuffer<uint> buf;

[[vk::ext_instruction(/* OpBitReverse */ 204)]]
uint8_t bitReverse8(uint8_t v);
[[vk::ext_instruction(/* OpBitCount */ 205)]]
uint bitCount8(uint8_t v);
[[vk::ext_instruction(/* OpBitFieldUExtract */ 203)]]
uint8_t bitFieldUExtract8(uint8_t base, uint offset, uint count);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint8_t v = (uint8_t)tid.x;

// CHECK: [[v:%[0-9]+]] = OpLoad %uchar %v
// CHECK-NEXT: {{%[0-9]+}} = OpBitReverse %uchar [[v]]
  uint r8 = (uint)bitReverse8(v);

// OpBitCount keeps a 32-bit result while the Base operand stays 8-bit.
// CHECK: [[vc:%[0-9]+]] = OpLoad %uchar %v
// CHECK-NEXT: {{%[0-9]+}} = OpBitCount %uint [[vc]]
  uint c8 = bitCount8(v);

// CHECK: [[ve:%[0-9]+]] = OpLoad %uchar %v
// CHECK-NEXT: {{%[0-9]+}} = OpBitFieldUExtract %uchar [[ve]] %uint_2 %uint_4
  uint e8 = (uint)bitFieldUExtract8(v, 2, 4);

  buf[0] = r8 + c8 + e8;
}
