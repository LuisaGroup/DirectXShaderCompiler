// RUN: %dxc -T cs_6_0 -E main -spirv -fcgl -fspv-target-env=vulkan1.3 -fspv-extension=SPV_EXT_shader_subgroup_partitioned %s

// Partitioned wave operations with
// SPV_EXT_shader_subgroup_partitioned / VK_EXT_shader_subgroup_partitioned.
//
// A wave is usually operated on as a whole: WaveActiveSum() reduces every lane,
// WavePrefixSum() scans every lane. The partitioned operations instead split the
// wave into groups of lanes that share a key and evaluate the reduction inside
// each group:
//
//     uint4 mask = WaveMatch(key);              // OpGroupNonUniformPartitionEXT
//     uint  sum  = WaveMultiPrefixSum(x, mask); // OpGroupNonUniformIAdd with
//                                               // PartitionedExclusiveScanEXT
//
// WaveMatch() returns, for every lane, the bitmask of the lanes of the wave that
// hold the same key - that bitmask is the partition. WaveMultiPrefixSum(),
// WaveMultiPrefixProduct() and WaveMultiPrefixBitAnd/Or/Xor() consume the mask
// and evaluate an exclusive scan over the lanes it selects, ignoring all others.
// Both halves are needed: a mask is not a partition operator on its own, and a
// WaveMultiPrefix*() call without a mask from WaveMatch() has no meaning.
//
// The example below is the shape that motivates the extension: a compute shader
// that needs two independent reductions over the same partition - a sum and a
// product - where a shared-memory reduction would need two passes, two
// barriers, and an explicit loop, and would serialize the whole group even
// though each partition is independent.
//
// Partition groups are arbitrary: they do not have to be uniform in size, do
// not have to be contiguous in lane order, and a wave may contain any number of
// them, so this replaces a shared-memory scheme whose cost is a barrier. Here
// the key is lane / 8, which gives contiguous groups of eight lanes (the last
// group of the wave is smaller if the wave size is not a multiple of eight).
//
// The extension exists under two names, and they are two names for the same
// SPIR-V capability:
//   * SPV_NV_shader_subgroup_partitioned - the original NVIDIA spelling. It
//     stays the default, so a shader compiled without -fspv-extension keeps
//     emitting OpExtension "SPV_NV_shader_subgroup_partitioned".
//   * SPV_EXT_shader_subgroup_partitioned - the standardised spelling, used
//     here. It has to be requested explicitly with
//     -fspv-extension=SPV_EXT_shader_subgroup_partitioned, and the module then
//     declares OpExtension "SPV_EXT_shader_subgroup_partitioned" and not the NV
//     string.
// GroupNonUniformPartitionedEXT and GroupNonUniformPartitionedNV are both
// capability 5297 and OpGroupNonUniformPartitionEXT/...NV are the same opcode,
// so the instruction stream is identical for the two; only the OpExtension
// string differs, which is why a disassembler always prints the canonical EXT
// name.
//
// The partitioned operations need SPIR-V 1.3 (i.e. Vulkan 1.1 or later), so
// -fspv-target-env=vulkan1.1 or a later environment is mandatory on top of the
// extension flag. Note that -fspv-extension is a whitelist: this RUN line names
// only the partition extension, so other default extensions must be listed too
// if the shader uses them.
//
// Required from the host:
//   * Vulkan device extension VK_EXT_shader_subgroup_partitioned (enable
//     VK_EXT_SHADER_SUBGROUP_PARTITIONED_EXTENSION_NAME at vkCreateDevice), or
//     VK_NV_shader_subgroup_partitioned for the NV spelling;
//   * the shaderSubgroupPartitioned feature bit of
//     VkPhysicalDeviceShaderSubgroupPartitionedFeaturesEXT (query it with
//     vkGetPhysicalDeviceFeatures2 and chain the structure with
//     shaderSubgroupPartitioned set to VK_TRUE into VkDeviceCreateInfo::pNext).
// A driver without them rejects a module that declares the
// GroupNonUniformPartitionedEXT capability, which is why DXC only emits the
// extension that was asked for (see docs/SPIR-V.rst).

RWStructuredBuffer<uint2> g_out : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  const uint lane = WaveGetLaneIndex();

  // The key decides the partition: every lane with the same key is in the same
  // group. Lanes 0-7 get key 0, lanes 8-15 key 1, and so on.
  const uint group = lane / 8;

  // Partition the wave. The result is per-lane: each lane receives the bitmask
  // of the lanes it is partitioned with, which is why it has to be fed back
  // into the WaveMultiPrefix*() calls below.
  const uint4 mask = WaveMatch(group);

  // Two independent reductions over the same partition, without shared memory
  // and without a barrier: an exclusive scan of the lane index (sum) and an
  // exclusive scan of a non-trivial value (product). Each lane gets the
  // combination of the lanes of its own group that precede it.
  const uint sum = WaveMultiPrefixSum(lane, mask);
  const uint product = WaveMultiPrefixProduct(lane + 1, mask);

  // Partitions are independent of each other, so the two results can be
  // combined and stored without any inter-group synchronization.
  g_out[tid.x] = uint2(sum, product);
}
