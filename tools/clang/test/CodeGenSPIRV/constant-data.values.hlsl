// RUN: %dxc -T cs_6_0 -E main -fcgl %s -spirv | FileCheck %s --check-prefix=COMPOSITE
// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-constant-data -fspv-extension=SPV_KHR_constant_data %s -spirv | FileCheck %s --check-prefix=DATA

// L2.values: the array holds the same values after it is packed, so it still
// behaves like the composite it replaced.
//
// DXC materializes a `static const` array as a Private variable and indexes it
// at run time: a constant index does not become an OpConstant in the front end
// (HLSL also rejects `case table[5]:` as "case value is not a constant
// expression"), so the two encodings are compared against each other instead.
// The two RUN lines compile the same shader, once with the composite and once
// with the packed constant, and both must produce the *same* index and load
// stream, down to the element types:
//
//   * with the feature off: OpCompositeConstruct over %uint_11 .. %uint_88
//   * with the feature on:  OpConstantDataKHR with the words 11 22 .. 88
//
// The words 11 22 33 44 55 66 77 88 are the source values in source order, so
// `%table` initialized with either instruction holds the same 8 uints and
// OpAccessChain/OpLoad of `%table` with %int_3 reads 44 in both modules. A
// packing error (wrong order, wrong width, wrong word count) makes the DATA run
// disagree with the COMPOSITE run on the words, and a validator error on the
// word count fails the DATA compile outright.

// COMPOSITE: OpCapability Shader
// COMPOSITE-NOT: OpCapability ConstantDataKHR
// DATA:      OpCapability Shader
// DATA-NEXT: OpCapability ConstantDataKHR
// DATA-NEXT: OpExtension "SPV_KHR_constant_data"

// COMPOSITE: [[ARRTY:%_arr_uint_uint_8]] = OpTypeArray %uint %uint_8
// COMPOSITE: [[CONST:%[0-9]+]] = OpCompositeConstruct [[ARRTY]] %uint_11 %uint_22 %uint_33 %uint_44 %uint_55 %uint_66 %uint_77 %uint_88
// DATA:      [[ARRTY:%_arr_uint_uint_8]] = OpTypeArray %uint %uint_8
// DATA:      [[CONST:%[0-9]+]] = OpConstantDataKHR [[ARRTY]] 11 22 33 44 55 66 77 88

// COMPOSITE: OpStore %table [[CONST]]
// DATA:      OpStore %table [[CONST]]

// Runtime index: table[i].
// COMPOSITE: [[MOD:%[0-9]+]] = OpUMod %uint {{%[0-9]+}} %uint_8
// COMPOSITE: OpStore %i [[MOD]]
// COMPOSITE: [[IV:%[0-9]+]] = OpLoad %uint %i
// COMPOSITE: [[P0:%[0-9]+]] = OpAccessChain %_ptr_Private_uint %table [[IV]]
// COMPOSITE: [[V0:%[0-9]+]] = OpLoad %uint [[P0]]
// COMPOSITE: [[O0:%[0-9]+]] = OpAccessChain %_ptr_Uniform_uint %outBuf %int_0 %uint_0
// COMPOSITE: OpStore [[O0]] [[V0]]
// DATA:      [[MOD:%[0-9]+]] = OpUMod %uint {{%[0-9]+}} %uint_8
// DATA:      OpStore %i [[MOD]]
// DATA:      [[IV:%[0-9]+]] = OpLoad %uint %i
// DATA:      [[P0:%[0-9]+]] = OpAccessChain %_ptr_Private_uint %table [[IV]]
// DATA:      [[V0:%[0-9]+]] = OpLoad %uint [[P0]]
// DATA:      [[O0:%[0-9]+]] = OpAccessChain %_ptr_Uniform_uint %outBuf %int_0 %uint_0
// DATA:      OpStore [[O0]] [[V0]]

// Constant index: table[3], same element type and same pointer in both modules.
// COMPOSITE: [[P1:%[0-9]+]] = OpAccessChain %_ptr_Private_uint %table %int_3
// COMPOSITE: [[V1:%[0-9]+]] = OpLoad %uint [[P1]]
// COMPOSITE: [[O1:%[0-9]+]] = OpAccessChain %_ptr_Uniform_uint %outBuf %int_0 %uint_1
// COMPOSITE: OpStore [[O1]] [[V1]]
// DATA:      [[P1:%[0-9]+]] = OpAccessChain %_ptr_Private_uint %table %int_3
// DATA:      [[V1:%[0-9]+]] = OpLoad %uint [[P1]]
// DATA:      [[O1:%[0-9]+]] = OpAccessChain %_ptr_Uniform_uint %outBuf %int_0 %uint_1
// DATA:      OpStore [[O1]] [[V1]]

static const uint table[8] = {
  11, 22, 33, 44, 55, 66, 77, 88
};

RWStructuredBuffer<uint> outBuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint i = tid.x % 8;
  outBuf[0] = table[i];
  outBuf[1] = table[3];
}
