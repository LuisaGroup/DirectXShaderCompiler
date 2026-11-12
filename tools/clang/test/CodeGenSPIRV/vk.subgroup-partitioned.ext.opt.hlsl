// RUN: %dxc -E main -T ps_6_5 -spirv -fspv-target-env=vulkan1.1 -fspv-extension=SPV_EXT_shader_subgroup_partitioned %s | FileCheck %s

// SPV_EXT_shader_subgroup_partitioned after legalization and optimization
// (G13/L6).
//
// No -fcgl: this is the module that ships, after DXC's spirv-opt pass list and
// the capability-trimming pass have run. Two things can only break here -
// spirv-opt dropping the partitioned operations or the mask they consume, and
// capability trimming removing GroupNonUniformPartitionedEXT (and with it the
// extension) because it does not see a user of it. The compile itself is the
// validity gate: dxc validates every module it emits, and this RUN line keeps
// validation enabled.
//
// This file also pins the interaction between the selection and the trimming
// pass: trimming drops SPV_EXT_shader_subgroup_partitioned only when the
// capability is unused (that is vk.subgroup-partitioned.off.hlsl), and here the
// EXT string has to come out on the other side untouched - a trimming change
// that started substituting the NV spelling, or that removed the extension
// altogether, is caught by the CHECK-NOT and the OpExtension CHECK below.

StructuredBuffer<uint4> g_mask;

uint4 main(int4 input0 : ATTR0, uint4 input1 : ATTR1) : SV_Target {
    uint4 mask = WaveMatch(input1);
    int4 product = WaveMultiPrefixProduct(input0, mask);
    uint4 bits = WaveMultiPrefixBitOr(mask, mask);
    return bits + uint4(product);
}

// The capability and the extension survive capability trimming, and the
// selection is still the EXT one.
// CHECK:      OpCapability GroupNonUniformPartitionedEXT
// CHECK:      OpExtension "SPV_EXT_shader_subgroup_partitioned"
// CHECK-NOT:  OpExtension "SPV_NV_shader_subgroup_partitioned"
// CHECK:      OpMemoryModel Logical GLSL450

// The partition of the wave and the two partitioned scans survive, with the
// same operands the -fcgl module has.
// CHECK:      OpGroupNonUniformPartitionEXT %v4uint
// CHECK:      OpGroupNonUniformIMul %v4int %uint_3 PartitionedExclusiveScanEXT
// CHECK:      OpGroupNonUniformBitwiseOr %v4uint %uint_3 PartitionedExclusiveScanEXT
// CHECK:      OpStore
