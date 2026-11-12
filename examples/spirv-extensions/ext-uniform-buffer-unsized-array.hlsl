// RUN: %dxc -T cs_6_0 -E main -spirv -fcgl -fspv-enable-uniform-buffer-unsized-array %s

// VK_EXT_shader_uniform_buffer_unsized_array: an unsized array as the last
// member of a uniform buffer block.
//
// A uniform buffer block normally has to describe its whole contents, so the
// size of every array in it is baked into the module and a new shader variant is
// needed for every data set size. VK_EXT_shader_uniform_buffer_unsized_array
// allows the *last* member of a uniform buffer block to be an unsized array
// instead; its effective length is then inferred at runtime from the size of the
// buffer object bound to the block.
//
// What the compiler emits
// -----------------------
// The extension is a relaxation of the Vulkan SPIR-V *environment*, not new
// module surface: the last member is simply an OpTypeRuntimeArray inside a
// Block-decorated OpTypeStruct in the Uniform storage class, which is exactly the
// type OpTypeRuntimeArray already denotes. Consequences:
//
//   * there is no SPV_EXT_shader_uniform_buffer_unsized_array, so there is
//     nothing to pass to -fspv-extension (the Khronos SPIR-V registry has no such
//     extension), and no OpExtension string is emitted;
//   * no capability is added either - the capability block of this module is the
//     one any other compute module gets;
//   * SPV_KHR_untyped_pointers, which the Vulkan extension lists as a dependency
//     for *implementations*, is not needed by the shader interface and is
//     therefore not emitted.
//
// Because none of that can be expressed by a target environment or an extension
// string, DXC gates the relaxation behind an opt-in flag,
// -fspv-enable-uniform-buffer-unsized-array (default off, so a module compiled
// without it is byte-for-byte what it was before). The flag only says that the
// shader may *declare* such a block; it is the application's promise that the
// device feature below is enabled.
//
// Rules the compiler enforces
// ---------------------------
//   * the unsized array must be the last member of the struct;
//   * the struct may only be used as the element type of a ConstantBuffer, i.e.
//     as a uniform buffer block. Push constant blocks and shader record buffers
//     are not covered by the Vulkan extension (and the shipped validator keeps
//     rejecting a runtime array in the PushConstant storage class), a
//     TextureBuffer/StructuredBuffer element type would nest the runtime array,
//     and a local variable or a function parameter of such a struct cannot have
//     a runtime size. All of those are compile errors;
//   * .Length on the unsized member is a compile error: the Vulkan extension
//     prohibits OpArrayLength, because the length is not a property of the
//     shader.
//   * the block cannot be copied: a local ConstantBuffer<T> variable, a
//     ConstantBuffer<T> parameter and a function returning one are rejected,
//     because CodeGen would have to place the runtime array in Function storage.
//     This is the extension's "cannot be passed as arguments to functions" rule.
//     An array of such blocks is rejected as well.
//
// How the shader learns the length
// --------------------------------
// It does not - it is passed in. The application computes
//
//   count = max((bufferObjectSize - offsetOfArray) / arrayStride, 0)
//
// from the size of the bound VkBuffer (offsetOfArray and arrayStride are the
// block's OpMemberDecorate Offset and the array's ArrayStride decoration, which
// DXC's disassembly prints, or the values SPIRV-Reflect reports) and stores it in
// the small block below. That is the intended usage pattern of the extension.
//
// Required from the host
// ----------------------
//   * VK_EXT_shader_uniform_buffer_unsized_array enabled at vkCreateDevice
//     (VK_EXT_SHADER_UNIFORM_BUFFER_UNSIZED_ARRAY_EXTENSION_NAME), and
//     VkPhysicalDeviceShaderUniformBufferUnsizedArrayFeaturesEXT::
//     shaderUniformBufferUnsizedArray set to VK_TRUE in the pNext chain of
//     VkDeviceCreateInfo;
//   * a VkDescriptorBufferInfo::range for the block that covers the members
//     before the array plus as many whole array elements as the shader should
//     see. The range is what makes the unsized array's effective length, so a
//     range of VK_WHOLE_SIZE exposes the rest of the buffer;
//   * indexes that stay inside that range. Out-of-range accesses follow the
//     ordinary Vulkan buffer access rules (undefined, and bounds-checked only
//     when the robustness features are enabled).
//
// The compiler cannot check any of this: it does not know the device or the
// buffer the application will bind.

struct DataBlock {
  float scale;   // sized member
  float values[];  // unsized member, must be last: OpTypeRuntimeArray in the block
};

struct CountBlock {
  uint count;    // max((bufferSize - offsetOfArray) / arrayStride, 0), from the host
};

ConstantBuffer<DataBlock> g_data;
ConstantBuffer<CountBlock> g_count;

RWStructuredBuffer<float> g_result : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // Indexing with a runtime index: OpAccessChain selects the unsized member
  // (index 1) and a second OpAccessChain applies the dynamic index. The value is
  // only defined for indexes the bound descriptor range covers.
  uint i = tid.x % g_count.count;
  g_result[tid.x] = g_data.values[i] * g_data.scale;
}
