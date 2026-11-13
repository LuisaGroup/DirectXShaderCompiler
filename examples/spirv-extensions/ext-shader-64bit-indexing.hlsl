// RUN: %dxc -T cs_6_0 -E main -spirv -fcgl -fspv-enable-64bit-indexing %s
// RUN: %dxc -T cs_6_0 -E main -spirv -fspv-enable-64bit-indexing %s

// VK_EXT_shader_64bit_indexing / SPV_EXT_shader_64bit_indexing: addressing a
// storage buffer whose range is larger than 4 GiB
// ==========================================================================
//
// The problem
// -----------
// Without this extension a Vulkan storage buffer binding has a range of at most
// maxStorageBufferRange == UINT32_MAX bytes, and DXC has always emitted the
// element index of a storage buffer's runtime-sized array as a 32-bit integer.
// That is not just a source-level convention: `index * ArrayStride` has to fit in
// 32 bits for the driver to be allowed to compute it with 32-bit arithmetic.
// Anything larger - a big weight tensor, a GPU-side hash table, a resident scene
// buffer - cannot be addressed through a single binding at all.
//
// What the extension changes
// --------------------------
// VK_EXT_shader_64bit_indexing removes the maxStorageBufferRange limit for devices
// that enable its feature bit, VkPhysicalDeviceShader64BitIndexingFeaturesEXT::
// shader64BitIndexing. SPV_EXT_shader_64bit_indexing is the SPIR-V half: an entry
// point that declares
//
//   OpExecutionMode %main Shader64BitIndexingEXT
//
// (with the Shader64BitIndexingEXT capability and the
// OpExtension "SPV_EXT_shader_64bit_indexing" string) promises the driver that
// the shader is prepared for the wider range. The Vulkan environment spec spells
// out what becomes 64-bit wide: "the calculation of index multiplied by
// ArrayStride for a runtime-sized array when evaluating an access chain in
// StorageBuffer or PhysicalStorageBuffer will have 64 bits of range".
//
// Two things do *not* become 64-bit, and the example is written to make that
// visible:
//   * the size of a struct or of a sized array. Offset and ArrayStride are 32-bit
//     literals, so only runtime-sized arrays can reach past 4 GiB;
//   * the HLSL index expression itself. `RWStructuredBuffer<T>::operator[]` and
//     `StructuredBuffer<T>::Load` take a `uint`, so Sema converts any wider index
//     expression down to 32 bits. What the extension widens is the address
//     arithmetic: with 48-byte elements a 32-bit element index addresses up to
//     192 GiB, which is the 4 GiB limit this example is about.
//
// What the compiler emits
// -----------------------
// With -fspv-enable-64bit-indexing (default off, so a shader compiled without it
// is byte-for-byte what it was before) DXC widens the one address calculation the
// extension is about - the index into the runtime-sized array of a storage
// buffer - and nothing else:
//
//   %idx = OpUConvert %ulong %u                  ; HLSL's 32-bit index, widened
//   %elt = OpAccessChain %ptr %buf %int_0 %idx   ; 64-bit element index
//
// * a literal index becomes a 64-bit OpConstant (%ulong_3) instead of a convert;
// * a signed index keeps its signedness (OpSConvert to %long), which is what
//   StructuredBuffer::Load(int) produces;
// * the struct member index that selects the runtime array (the permanent
//   leading %int_0) and every index into a sized array stay 32 bits;
// * cbuffer / tbuffer blocks, groupshared arrays, function-local arrays and
//   descriptor-array indices are unchanged;
// * the arithmetic that produces the index is unchanged, too: only the operand of
//   the access chain is widened, so `buf[i + 1]` still computes `i + 1` in 32
//   bits.
// Index paths that the flag cannot widen are diagnosed rather than silently left
// behind: (RW)ByteAddressBuffer.Load/Store take a 32-bit byte offset and
// Append/ConsumeStructuredBuffer use a 32-bit counter, so both emit a warning when
// the flag is on.
//
// Reading it back: `dxc -T cs_6_0 -E main -spirv -fcgl
// -fspv-enable-64bit-indexing ext-shader-64bit-indexing.hlsl` prints
// OpCapability Shader64BitIndexingEXT, OpCapability Int64,
// OpExtension "SPV_EXT_shader_64bit_indexing",
// OpExecutionMode %main Shader64BitIndexingEXT, %ulong = OpTypeInt 64 0 and the
// OpUConvert/OpAccessChain pair above.
//
// Required from the host
// ----------------------
// * VK_EXT_shader_64bit_indexing enabled at vkCreateDevice, with
//   VkPhysicalDeviceShader64BitIndexingFeaturesEXT::shader64BitIndexing set to
//   VK_TRUE;
// * 64-bit indexing requested for the pipeline or shader object:
//   VK_PIPELINE_CREATE_2_64_BIT_INDEXING_BIT_EXT /
//   VK_SHADER_CREATE_64_BIT_INDEXING_BIT_EXT, or this module's execution mode, so
//   the driver and the module agree about the width of the address computation.
//   Indexing a descriptor with more than 4 GiB of range without that request is
//   undefined behaviour;
// * a descriptor binding (or buffer device address) whose range really is larger
//   than 4 GiB, i.e. VkDescriptorBufferInfo::range not clamped to
//   maxStorageBufferRange.
// The compiler can check none of this - it does not see the device, the feature
// bits or the bound buffer - so the flag is the application's promise, and the
// module is only valid on a host that enables the matching feature. Enabling
// 64-bit indexing can also cost performance on some implementations, so keep a
// non-wide variant of hot shaders that never exceed 4 GiB.
//
// Example
// -------
// One >4 GiB buffer of 48-byte elements (>89 million elements before the range
// passes 4 GiB), plus a small parameter block and a small output buffer whose
// accesses stay 32-bit.

struct Element {
  float4 position;
  float4 normal;
  uint material;
};

// The >4 GiB payload: every access into it goes through a widened index.
RWStructuredBuffer<Element> g_elements : register(u0);

// Small control block: a mask, and an element-count bound the host keeps in sync
// with the size of the binding.
struct Params {
  uint mask;
  uint count;
};
ConstantBuffer<Params> g_params : register(b0);

// Small output buffer: ordinary 32-bit indexing, unchanged by the flag.
RWStructuredBuffer<float4> g_out : register(u1);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // A 32-bit element index, as HLSL's operator[] requires. Below the access
  // chain the compiler inserts %idx = OpUConvert %ulong %index, so the product
  // index * ArrayStride is evaluated in 64 bits and this read reaches past the
  // 4 GiB a non-wide module is limited to.
  uint i = tid.x;

  // The weight/mask arithmetic stays 32-bit: only the array index is widened.
  uint material = g_elements[i].material;
  uint lane = (material & g_params.mask) & 0x3fu;

  // A second access into the same binding, this time a write of one member: the
  // runtime-array index is %ulong, the struct member index is still %int.
  g_elements[i].normal = float4(float(lane), 0.0f, 0.0f, 1.0f);

  // Keep the loaded value alive through the small output buffer, whose index is
  // an ordinary 32-bit one.
  if (tid.x < 64 && tid.x < g_params.count) {
    g_out[tid.x] = g_elements[i].position;
  }
}
