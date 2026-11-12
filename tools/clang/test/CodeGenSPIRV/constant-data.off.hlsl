// RUN: %dxc -T cs_6_0 -E main -fcgl %s -spirv | FileCheck %s

// L5: without -fspv-constant-data the output is what it was before the feature:
// no capability, no extension, and the table is still an OpCompositeConstruct
// over one OpConstant per element. The CHECK-NOT regions are anchored between
// two CHECKs so that they cover the only place the excluded text could appear.

// The capability block, from the Shader capability down to the memory model, is
// exactly where a ConstantDataKHR capability and extension would be emitted.
// CHECK:     OpCapability Shader
// CHECK-NOT: OpCapability ConstantDataKHR
// CHECK-NOT: OpExtension "SPV_KHR_constant_data"
// CHECK:     OpMemoryModel Logical GLSL450

// CHECK: %uint_11 = OpConstant %uint 11
// CHECK-NOT: OpConstantDataKHR
// CHECK: [[ARRTY:%_arr_uint_uint_8]] = OpTypeArray %uint %uint_8
// CHECK: OpCompositeConstruct [[ARRTY]] %uint_11 %uint_22 %uint_33 %uint_44 %uint_55 %uint_66 %uint_77 %uint_88
// CHECK-NOT: OpConstantDataKHR %_arr_uint_uint_8

static const uint table[8] = {
  11, 22, 33, 44, 55, 66, 77, 88
};

RWStructuredBuffer<uint> outBuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  outBuf[0] = table[tid.x % 8];
}
