// RUN: %dxc -E main -T ps_6_5 -spirv -O0 -fspv-target-env=vulkan1.1 -fcgl %s | FileCheck %s
// RUN: %dxc -E main -T ps_6_5 -spirv -O0 -fspv-target-env=vulkan1.1 -fspv-extension=SPV_NV_shader_subgroup_partitioned -fcgl %s | FileCheck %s

// SPV_NV_shader_subgroup_partitioned stays selectable (G13/L1.nv, G13/L5).
//
// The two RUN lines must agree on everything the partitioned feature
// contributes: the same capability, the same instructions, and the NV
// OpExtension string with no EXT string. The first line is the default -
// SPV_NV_shader_subgroup_partitioned is enabled unless an explicit
// -fspv-extension list is given, and the module it produces is byte-identical
// to what DXC emitted before SPV_EXT_shader_subgroup_partitioned was
// registered - and the second names the NV spelling explicitly. (The default
// module additionally carries the other extensions that are enabled by
// default, e.g. SPV_KHR_ray_query; the explicit list is a whitelist and turns
// them off. That is unrelated to this feature, which is why the CHECK lines
// below only pin the partitioned lines.)
//
// This file is the L5 anchor for the default: the pre-existing
// sm6_5.wave-match.hlsl and intrinsics.sm6_5.multiprefix.hlsl assert the same
// NV string and stay unmodified.

StructuredBuffer<uint4> g_mask;

uint4 main(int4 input0 : ATTR0, uint4 input1 : ATTR1) : SV_Target {
    // CHECK:      OpCapability GroupNonUniformPartitionedEXT
    // CHECK:      OpExtension "SPV_NV_shader_subgroup_partitioned"
    // CHECK-NOT:  OpExtension "SPV_EXT_shader_subgroup_partitioned"
    // CHECK:      OpMemoryModel Logical GLSL450

    // The instruction stream is identical to vk.subgroup-partitioned.ext.hlsl:
    // the capability id is shared, so only the OpExtension line can differ.
    // CHECK:      [[input1:%[0-9]+]] = OpLoad %v4uint %input1
    // CHECK:      [[mask:%[0-9]+]] = OpGroupNonUniformPartitionEXT %v4uint [[input1]]
    uint4 mask = WaveMatch(input1);

    // CHECK:      [[input0:%[0-9]+]] = OpLoad %v4int %input0
    // CHECK:      [[mask2:%[0-9]+]] = OpLoad %v4uint %mask
    // CHECK:      {{%[0-9]+}} = OpGroupNonUniformIMul %v4int %uint_3 PartitionedExclusiveScanEXT [[input0]] [[mask2]]
    int4 product = WaveMultiPrefixProduct(input0, mask);

    return mask + uint4(product);
}
