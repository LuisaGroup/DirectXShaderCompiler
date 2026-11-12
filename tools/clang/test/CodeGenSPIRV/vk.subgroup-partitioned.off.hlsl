// RUN: %dxc -E main -T cs_6_5 -spirv -O0 -fspv-target-env=vulkan1.1 %s | FileCheck %s
// RUN: %dxc -E main -T cs_6_5 -spirv -O0 -fspv-target-env=vulkan1.1 -fspv-extension=SPV_EXT_shader_subgroup_partitioned %s | FileCheck %s

// Off path: wave operations that are not partitioned (G13/L5).
//
// The partitioned capability is declared unconditionally by CapabilityVisitor
// and removed again by the capability-trimming pass when no partitioned
// operation uses it. This file runs *without* -fcgl for that reason: the
// pre-trim module always carries the extension of the enabled spelling, so only
// the shipped module can show that an unused partition extension is gone.
//
// Both RUN lines must produce the same module:
//   * the first is the default (NV spelling enabled, EXT not),
//   * the second selects the new EXT spelling with -fspv-extension, which is
//     the case where the feature is enabled but the shader does not use it.
// WaveActiveSum/WavePrefixSum keep their plain OpGroupNonUniformIAdd encoding
// (Reduce / ExclusiveScan), so nothing is lowered differently either. Both
// outputs were diffed against the pre-change compiler: the default-flag module
// is byte-identical to it, and the EXT-selected module is byte-identical to the
// default-flag one, so the new extension changes nothing here.

RWStructuredBuffer<uint> g_out;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint sum = WaveActiveSum(tid.x);
    uint prefix = WavePrefixSum(tid.x);
    g_out[tid.x] = sum + prefix;
}

// The whole header - capability block and extension block, in whatever order
// they end up - must not mention either spelling of the partitioned extension.
// The three CHECK-NOTs are anchored between the start of the module and
// OpMemoryModel, which is the first directive after all OpCapability and
// OpExtension lines.
// CHECK-NOT:  GroupNonUniformPartition
// CHECK-NOT:  SPV_EXT_shader_subgroup_partitioned
// CHECK-NOT:  SPV_NV_shader_subgroup_partitioned
// CHECK:      OpMemoryModel Logical GLSL450

// The non-partitioned wave operations are unchanged, and no partitioned
// operation is introduced anywhere in the function.
// CHECK:      OpGroupNonUniformIAdd %uint %uint_3 Reduce
// CHECK:      OpGroupNonUniformIAdd %uint %uint_3 ExclusiveScan
// CHECK-NOT:  OpGroupNonUniformPartitionEXT
// CHECK-NOT:  PartitionedReduceEXT
// CHECK-NOT:  PartitionedExclusiveScanEXT
// CHECK:      OpReturn
