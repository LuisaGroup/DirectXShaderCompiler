// RUN: %dxc -T cs_6_0 -E main -fcgl -DU8 -fspv-constant-data -fspv-extension=SPV_KHR_constant_data %s -spirv | FileCheck %s --check-prefix=U8
// RUN: %dxc -T cs_6_2 -E main -enable-16bit-types -fcgl -DU16 -fspv-constant-data -fspv-extension=SPV_KHR_constant_data %s -spirv | FileCheck %s --check-prefix=U16
// RUN: %dxc -T cs_6_2 -E main -enable-16bit-types -fcgl -DI8 -fspv-constant-data -fspv-extension=SPV_KHR_constant_data %s -spirv | FileCheck %s --check-prefix=I8
// RUN: %dxc -T cs_6_0 -E main -fcgl -DU64 -fspv-constant-data=4 -fspv-extension=SPV_KHR_constant_data %s -spirv | FileCheck %s --check-prefix=U64

// L2 for the element widths that need bit packing. SPV_KHR_constant_data, on
// OpConstantDataKHR: "Data is packed with no padding between elements of the
// specified type. If the size of scalar elements of Result Type are less than
// 32 bits, they are packed into elements of Data from least significant bits to
// most significant bits. If the size of Result Type is not a multiple of 32
// bits, the final element of Data is padded to 32-bits."
//
// Every element below has a different bit pattern per byte / half word, so a
// wrong packing direction, a dropped element, or an encoder that rounds each
// element to its own word is visible in the asserted words. The decimal values
// in the CHECK lines are the words as the disassembler prints them:
//
// 8-bit unsigned, 8 elements (8 bytes -> exactly 2 words, no padding):
//   01 23 45 67 89 ab cd ef
//   word 0 = 0x67452301 = 1732584193   (element 0 in the least significant byte)
//   word 1 = 0xefcdab89 = 4023233417
//
// 8-bit signed, the same array with -1 -2 3 4 -5 -6 7 8. The packed bit pattern
// is two's complement at the element width, so a sign-extending encoder that
// writes 32 bits per element fails:
//   ff fe 03 04 fb fa 07 08
//   word 0 = 0x0403feff = 67370751
//   word 1 = 0x0807fafb = 134740731
//
// 16-bit unsigned, 8 elements (16 bytes -> 4 words):
//   0123 4567 89ab cdef 1111 2222 3333 4444
//   word 0 = 0x45670123 = 1164378403
//   word 1 = 0xcdef89ab = 3455027627
//   word 2 = 0x22221111 = 572657937
//   word 3 = 0x44443333 = 1145320243
//
// 64-bit unsigned, 4 elements (32 bytes -> 8 words), each element in two words,
// the low word first:
//   0123456789abcdef 1111222233334444 5555666677778888 9999aaaabbbbcccc
//   word 0 = 0x89abcdef = 2309737967   word 1 = 0x01234567 = 19088743
//   word 2 = 0x33334444 = 858997828    word 3 = 0x11112222 = 286335522
//   word 4 = 0x77778888 = 2004322440   word 5 = 0x55556666 = 1431660134
//   word 6 = 0xbbbbcccc = 3149647052   word 7 = 0x9999aaaa = 2576984746
//
// The threshold is 8 by default; the uint64_t case passes
// -fspv-constant-data=4 because its table has 4 elements.

#ifdef U8
static const uint8_t table[8] = {
  0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef
};
// U8: OpCapability Int8
// U8: %uchar = OpTypeInt 8 0
// U8: [[TYPE:%_arr_uchar_uint_8]] = OpTypeArray %uchar %uint_8
// U8: OpConstantDataKHR [[TYPE]] 1732584193 4023233417
// U8-NOT: OpConstantDataKHR [[TYPE]]
#define N 8
#elif defined(U16)
static const uint16_t table[8] = {
  0x0123, 0x4567, 0x89ab, 0xcdef, 0x1111, 0x2222, 0x3333, 0x4444
};
// U16: OpCapability Int16
// U16: %ushort = OpTypeInt 16 0
// U16: [[TYPE:%_arr_ushort_uint_8]] = OpTypeArray %ushort %uint_8
// U16: OpConstantDataKHR [[TYPE]] 1164378403 3455027627 572657937 1145320243
// U16-NOT: OpConstantDataKHR [[TYPE]]
#define N 8
#elif defined(I8)
static const int8_t table[8] = {
  -1, -2, 3, 4, -5, -6, 7, 8
};
// I8: OpCapability Int8
// I8: %char = OpTypeInt 8 1
// I8: [[TYPE:%_arr_char_uint_8]] = OpTypeArray %char %uint_8
// I8: OpConstantDataKHR [[TYPE]] 67370751 134740731
// I8-NOT: OpConstantDataKHR [[TYPE]]
#define N 8
#else
static const uint64_t table[4] = {
  0x0123456789abcdef, 0x1111222233334444, 0x5555666677778888, 0x9999aaaabbbbcccc
};
// U64: OpCapability Int64
// U64: %ulong = OpTypeInt 64 0
// U64: [[TYPE:%_arr_ulong_uint_4]] = OpTypeArray %ulong %uint_4
// U64: OpConstantDataKHR [[TYPE]] 2309737967 19088743 858997828 286335522 2004322440 1431660134 3149647052 2576984746
// U64-NOT: OpConstantDataKHR [[TYPE]]
#define N 4
#endif

RWStructuredBuffer<uint> outBuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  outBuf[0] = (uint)table[tid.x % N];
}
