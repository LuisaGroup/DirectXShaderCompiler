// RUN: %dxc -T cs_6_6 -E main -spirv -fspv-use-descriptor-heap -fspv-target-env=vulkan1.3 %s

// Resource and sampler descriptor heaps.
//
// SPIR-V: SPV_EXT_descriptor_heap (capability ResourceHeapEXT / SamplerHeapEXT,
// OpUntypedVariableKHR + OpUntypedAccessChainKHR into a typed runtime array)
// plus SPV_KHR_untyped_pointers (OpTypeUntypedPointerKHR, OpUntypedAccessChainKHR)
// and, for buffers, OpTypeBufferEXT + OpBufferPointerEXT.
// Vulkan: VK_EXT_descriptor_heap, enabled at vkCreateDevice, together with the
// descriptor-heap feature bits; the host builds the heaps with
// vkWriteResourceDescriptorsEXT / vkWriteSamplerDescriptorsEXT and the shader
// indexes them with the ResourceHeapEXT / SamplerHeapEXT built-ins.
//
// Instead of a fixed descriptor set binding, ResourceDescriptorHeap[i] and
// SamplerDescriptorHeap[i] address a heap slot directly. This is what lets one
// shader reach "bindless" resources without descriptor-indexing gymnastics; the
// host decides which descriptor sits in which slot.
//
// Compile with -fspv-use-descriptor-heap to get the native heap encoding above.
// Without the flag DXC emulates the heaps with ordinary descriptor sets
// (SPV_EXT_descriptor_indexing), which every driver supports.

RWStructuredBuffer<float4> output : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
  // Slot 0 of the resource heap is a sampled texture; slot 1 of the sampler heap
  // is the sampler that goes with it. Neither is a shader-declared resource.
  Texture2D<float4> texture = ResourceDescriptorHeap[0];
  SamplerState sampler = SamplerDescriptorHeap[1];

  output[id.x] = texture.SampleLevel(sampler, float2(0.5, 0.5), 0.0);

  // A UAV from the same heap: the typed runtime array is re-typed per access, so
  // one shader can address many different resource types by index.
  RWStructuredBuffer<uint> counters = ResourceDescriptorHeap[2];
  counters[id.x] = id.x;
}
