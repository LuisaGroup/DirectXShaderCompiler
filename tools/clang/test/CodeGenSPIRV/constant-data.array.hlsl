// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-constant-data -fspv-extension=SPV_KHR_constant_data %s -spirv | FileCheck %s

// L1 + L2 for SPV_KHR_constant_data: a uint lookup table whose elements are all
// known at compile time is declared by one OpConstantDataKHR instead of an
// OpCompositeConstruct over one OpConstant per element.
//
// L1: exactly the capability and the extension the instruction needs, and no
//     ArrayStride on the result type (SPV_KHR_constant_data: "Result Type must
//     not be decorated with ArrayStride").
// L2: the operands are the literal words, not ids. The table below holds
//     0x01234567 and 0x89abcdef, so the word sequence starts with
//     0x01234567 = 19088743 and 0x89abcdef = 2309737967. A per-element encoding,
//     a reversed word order or an id operand all fail this CHECK, which is why
//     the two leading values are asymmetric.
//
// Float tables keep the composite form: the result type of the instruction must
// be an array of *integer scalar* elements, and a float element has no defined
// bit pattern to pack.

// CHECK:      OpCapability Shader
// CHECK-NEXT: OpCapability ConstantDataKHR
// CHECK-NEXT: OpExtension "SPV_KHR_constant_data"

// CHECK: OpDecorate %outBuf Binding 0
// CHECK-NOT: OpDecorate %_arr_uint_uint_8 ArrayStride
// CHECK: OpDecorate %_runtimearr_uint ArrayStride 4

// CHECK: %uint_8 = OpConstant %uint 8
// CHECK: [[TABLE_TYPE:%_arr_uint_uint_8]] = OpTypeArray %uint %uint_8
// CHECK: [[TABLE:%[0-9]+]] = OpConstantDataKHR [[TABLE_TYPE]] 19088743 2309737967 1 2 3 4 5 6

// The near-miss encodings must not appear for this type.
// CHECK-NOT: OpConstantComposite [[TABLE_TYPE]]
// CHECK-NOT: OpCompositeConstruct [[TABLE_TYPE]]

// A float table of the same size keeps the composite form: OpConstantDataKHR
// only packs integer scalar elements.
// CHECK: [[FTABLE_TYPE:%_arr_float_uint_8]] = OpTypeArray %float %uint_8
// CHECK-NOT: OpConstantDataKHR [[FTABLE_TYPE]]
// CHECK: %table = OpVariable %_ptr_Private__arr_uint_uint_8 Private
// CHECK: OpStore %table [[TABLE]]
// CHECK: OpCompositeConstruct [[FTABLE_TYPE]] %float_1_5 %float_2_5 %float_3_5 %float_4_5 %float_5_5 %float_6_5 %float_7_5 %float_8_5

static const uint table[8] = {
  0x01234567, 0x89abcdef, 1, 2, 3, 4, 5, 6
};
static const float ftable[8] = {
  1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5
};

RWStructuredBuffer<uint> outBuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint i = tid.x % 8;
  outBuf[0] = table[i] + (uint)ftable[i];
}
