// RUN: %dxc -T cs_6_6 -E main -fcgl -spirv -fspv-use-descriptor-heap -fspv-enable-64bit-indexing -fspv-target-env=vulkan1.3 %s | FileCheck %s

// VK_EXT_shader_64bit_indexing composes with VK_EXT_descriptor_heap: a buffer
// that is reached through ResourceDescriptorHeap still has its runtime-array
// index widened, and the module validates for vulkan1.3 (the environment the
// heap requires).
//
// CHECK-DAG: OpCapability Shader64BitIndexingEXT
// CHECK-DAG: OpCapability DescriptorHeapEXT
// CHECK-DAG: OpExtension "SPV_EXT_shader_64bit_indexing"
// CHECK: OpEntryPoint GLCompute %main "main"
// CHECK: OpExecutionMode %main Shader64BitIndexingEXT
//
// The descriptor index into the heap is not an address calculation, so it stays
// a 32-bit immediate (%uint_3 for ResourceDescriptorHeap[3]).
// CHECK: OpUntypedAccessChainKHR {{.*}} %resource_heap %uint_3

struct S {
  float4 a;
  float b;
};

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint i = tid.x;
  RWStructuredBuffer<S> b = ResourceDescriptorHeap[3];

  // The buffer handle is fetched through the heap with a 32-bit descriptor
  // index (OpUntypedAccessChainKHR + OpBufferPointerEXT above); the element
  // access chain into the fetched buffer then uses the widened index.
  // CHECK: [[idx:%[0-9]+]] = OpUConvert %ulong
  // CHECK: OpAccessChain %_ptr_StorageBuffer_v4float {{.*}} %int_0 [[idx]] %int_0
  b[i].a = float4(i, 0, 0, 1);

  // CHECK: [[idx2:%[0-9]+]] = OpUConvert %ulong
  // CHECK: OpAccessChain %_ptr_StorageBuffer_float {{.*}} %int_0 [[idx2]] %int_1
  b[i].b = 1.0f;
}
