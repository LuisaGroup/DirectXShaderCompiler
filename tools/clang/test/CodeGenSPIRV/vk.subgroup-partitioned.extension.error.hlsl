// RUN: not %dxc -E main -T ps_6_5 -spirv -O0 -fspv-target-env=vulkan1.1 -fspv-extension=SPV_KHR_shader_clock %s 2>&1 | FileCheck %s

// The partitioned wave operations need one of the two extension spellings
// (G13/L4).
//
// -fspv-extension is a whitelist: naming any extension disables every extension
// that is only enabled by default, and that includes
// SPV_NV_shader_subgroup_partitioned. Here an unrelated extension is named, so
// neither spelling is enabled and both WaveMatch() and WaveMultiPrefix*() are
// compile errors.
//
// The diagnostic replaces a fatal "generated SPIR-V is invalid" failure: without
// it the module would contain OpGroupNonUniformPartitionEXT while no declared
// extension provides GroupNonUniformPartitionedEXT, which is exactly what the
// validator rejects. The extensions are interchangeable (same capability), so
// the message names both and recommends the standardised one.

StructuredBuffer<uint4> g_mask;

uint4 main(int4 input0 : ATTR0, uint4 input1 : ATTR1) : SV_Target {
    uint4 mask = g_mask[0];

    // CHECK: error: 'WaveMatch' requires the SPV_EXT_shader_subgroup_partitioned extension; pass -fspv-extension=SPV_EXT_shader_subgroup_partitioned (or -fspv-extension=SPV_NV_shader_subgroup_partitioned) to enable it
    mask = WaveMatch(input1);

    // CHECK: error: 'WaveMultiPrefix*' requires the SPV_EXT_shader_subgroup_partitioned extension; pass -fspv-extension=SPV_EXT_shader_subgroup_partitioned (or -fspv-extension=SPV_NV_shader_subgroup_partitioned) to enable it
    int4 product = WaveMultiPrefixProduct(input0, mask);

    return mask + uint4(product);
}
