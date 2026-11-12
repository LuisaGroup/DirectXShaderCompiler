// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-constant-data=8 -fspv-extension=SPV_KHR_constant_data %s -spirv | FileCheck %s

// L4.threshold: -fspv-constant-data=<threshold> is a minimum *element count*.
// Both sides of the boundary are exercised in one module: an 8-element table
// (>= 8) uses OpConstantDataKHR, a 7-element table keeps the
// OpCompositeConstruct form it has without the option.

// CHECK: OpCapability ConstantDataKHR

// Eight elements: packed.
// CHECK: [[BIG:%_arr_uint_uint_8]] = OpTypeArray %uint %uint_8
// CHECK: OpConstantDataKHR [[BIG]] 100 101 102 103 104 105 106 107

// Seven elements: below the threshold, still a composite over OpConstant ids.
// CHECK: [[SMALL:%_arr_uint_uint_7]] = OpTypeArray %uint %uint_7
// CHECK: OpCompositeConstruct [[SMALL]] %uint_100 %uint_101 %uint_102 %uint_103 %uint_104 %uint_105 %uint_106
// CHECK-NOT: OpConstantDataKHR [[SMALL]]

static const uint big[8] = {
  100, 101, 102, 103, 104, 105, 106, 107
};
static const uint small[7] = {
  100, 101, 102, 103, 104, 105, 106
};

RWStructuredBuffer<uint> outBuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint i = tid.x;
  outBuf[0] = big[i % 8] + small[i % 7];
}
