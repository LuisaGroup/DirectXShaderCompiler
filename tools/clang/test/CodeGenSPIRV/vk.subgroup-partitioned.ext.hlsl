// RUN: %dxc -E main -T ps_6_5 -spirv -O0 -fspv-target-env=vulkan1.1 -fspv-extension=SPV_EXT_shader_subgroup_partitioned -fcgl %s | FileCheck %s
// RUN: %dxc -E main -T ps_6_5 -spirv -O0 -fspv-target-env=vulkan1.1 -fspv-extension=SPV_EXT_shader_subgroup_partitioned -fspv-extension=SPV_NV_shader_subgroup_partitioned -fcgl %s | FileCheck %s

// SPV_EXT_shader_subgroup_partitioned selected explicitly (G13/L0, L1, L2).
//
// WaveMatch() and the WaveMultiPrefix* family are the HLSL surfaces of the
// partitioned group operations. The extension that provides them exists twice:
// SPV_NV_shader_subgroup_partitioned and the standardised
// SPV_EXT_shader_subgroup_partitioned. Both name the same capability
// (GroupNonUniformPartitionedEXT == GroupNonUniformPartitionedNV == 5297), so
// only the OpExtension string distinguishes them, and exactly one of the two
// may be declared. With -fspv-extension=SPV_EXT_shader_subgroup_partitioned the
// module declares the EXT spelling and nothing else - the NV spelling is not
// an alias that can be emitted next to it. The second RUN line lists both
// spellings, which resolves to the same module: the standardised EXT spelling
// wins.
//
// The capability id is identical for both spellings, so the disassembler prints
// the canonical EXT name (OpCapability GroupNonUniformPartitionedEXT,
// OpGroupNonUniformPartitionEXT) in both cases: this file and
// vk.subgroup-partitioned.nv.hlsl assert the same encoding for the operations
// they have in common, and differ only in the OpExtension line and the
// -fspv-extension flag.

StructuredBuffer<uint4> g_mask;

uint4 main(int4 input0 : ATTR0, uint4 input1 : ATTR1) : SV_Target {
    // CHECK:      OpCapability GroupNonUniformPartitionedEXT
    // CHECK:      OpExtension "SPV_EXT_shader_subgroup_partitioned"
    // CHECK-NOT:  OpExtension "SPV_NV_shader_subgroup_partitioned"
    // CHECK:      OpMemoryModel Logical GLSL450

    // WaveMatch lowers to OpGroupNonUniformPartitionEXT, result type %v4uint.
    // CHECK:      [[input1:%[0-9]+]] = OpLoad %v4uint %input1
    // CHECK:      [[mask:%[0-9]+]] = OpGroupNonUniformPartitionEXT %v4uint [[input1]]
    uint4 mask = WaveMatch(input1);

    // WaveMultiPrefixProduct is a partitioned exclusive scan: the group
    // operation is PartitionedExclusiveScanEXT and the mask is the second
    // operand.
    // CHECK:      [[input0:%[0-9]+]] = OpLoad %v4int %input0
    // CHECK:      [[mask2:%[0-9]+]] = OpLoad %v4uint %mask
    // CHECK:      {{%[0-9]+}} = OpGroupNonUniformIMul %v4int %uint_3 PartitionedExclusiveScanEXT [[input0]] [[mask2]]
    int4 product = WaveMultiPrefixProduct(input0, mask);

    // CHECK:      {{%[0-9]+}} = OpGroupNonUniformBitwiseOr %v4uint %uint_3 PartitionedExclusiveScanEXT {{%[0-9]+}} {{%[0-9]+}}
    uint4 bits = WaveMultiPrefixBitOr(mask, mask);

    return bits + uint4(product);
}
