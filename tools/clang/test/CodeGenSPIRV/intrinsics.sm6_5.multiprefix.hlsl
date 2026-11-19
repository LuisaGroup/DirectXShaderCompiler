// RUN: %dxc -E main -T ps_6_5 -spirv -O0 -fspv-target-env=vulkan1.1 %s | FileCheck %s
// RUN: not %dxc -E main -T ps_6_5 -spirv -O0 %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERROR

// CHECK-ERROR: error: Vulkan 1.1 is required for Wave Operation but not permitted to use

// CHECK: OpCapability GroupNonUniformPartitionedEXT
// CHECK: OpExtension "SPV_NV_shader_subgroup_partitioned"

StructuredBuffer<uint4> g_mask;

uint4 main(int4 input0 : ATTR0, uint4 input1 : ATTR1) : SV_Target {
    uint4 mask = g_mask[0];

// CHECK: [[input0:%[0-9]+]] = OpLoad %v4int %input0
// CHECK:   [[mask:%[0-9]+]] = OpLoad %v4uint %mask
// CHECK:        {{%[0-9]+}} = OpGroupNonUniformIMul %v4int %uint_3 PartitionedExclusiveScanEXT [[input0]] [[mask]]
    int4 res = WaveMultiPrefixProduct(input0, mask);

// CHECK: [[input1:%[0-9]+]] = OpLoad %v4uint %input1
// CHECK:   [[mask:%[0-9]+]] = OpLoad %v4uint %mask
// CHECK:        {{%[0-9]+}} = OpGroupNonUniformIMul %v4uint %uint_3 PartitionedExclusiveScanEXT [[input1]] [[mask]]
    res += WaveMultiPrefixProduct(input1, mask);

// CHECK: [[input0:%[0-9]+]] = OpLoad %v4int %input0
// CHECK:   [[mask:%[0-9]+]] = OpLoad %v4uint %mask
// CHECK:        {{%[0-9]+}} = OpGroupNonUniformIAdd %v4int %uint_3 PartitionedExclusiveScanEXT [[input0]] [[mask]]
    res += WaveMultiPrefixSum(input0, mask);

// CHECK: [[input1:%[0-9]+]] = OpLoad %v4uint %input1
// CHECK:   [[mask:%[0-9]+]] = OpLoad %v4uint %mask
// CHECK:        {{%[0-9]+}} = OpGroupNonUniformIAdd %v4uint %uint_3 PartitionedExclusiveScanEXT [[input1]] [[mask]]
    res += WaveMultiPrefixSum(input1, mask);

// CHECK: [[input1:%[0-9]+]] = OpLoad %v4uint %input1
// CHECK:   [[mask:%[0-9]+]] = OpLoad %v4uint %mask
// CHECK:        {{%[0-9]+}} = OpGroupNonUniformBitwiseAnd %v4uint %uint_3 PartitionedExclusiveScanEXT [[input1]] [[mask]]
    res += WaveMultiPrefixBitAnd(input1, mask);

// CHECK: [[input1:%[0-9]+]] = OpLoad %v4uint %input1
// CHECK:   [[mask:%[0-9]+]] = OpLoad %v4uint %mask
// CHECK:        {{%[0-9]+}} = OpGroupNonUniformBitwiseOr %v4uint %uint_3 PartitionedExclusiveScanEXT [[input1]] [[mask]]
    res += WaveMultiPrefixBitOr(input1, mask);

// CHECK: [[input1:%[0-9]+]] = OpLoad %v4uint %input1
// CHECK:   [[mask:%[0-9]+]] = OpLoad %v4uint %mask
  // CHECK: {{%[0-9]+}} = OpGroupNonUniformBitwiseXor %v4uint %uint_3 PartitionedExclusiveScanEXT [[input1]] [[mask]]
      res += WaveMultiPrefixBitXor(input1, mask);
  // CHECK: [[pred:%[0-9]+]] = OpIEqual %bool {{%[0-9]+}} %int_1
  // CHECK: [[counted:%[0-9]+]] = OpSelect %uint [[pred]] %uint_1 %uint_0
  // CHECK: [[mask2:%[0-9]+]] = OpLoad %v4uint %mask
  // CHECK: {{%[0-9]+}} = OpGroupNonUniformIAdd %uint %uint_3 PartitionedExclusiveScanEXT [[counted]] [[mask2]]
      res += WaveMultiPrefixCountBits(input0.x == 1, mask);
      return res;
}
