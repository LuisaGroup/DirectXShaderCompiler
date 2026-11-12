// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_matrix_decode_vector -fspv-extension=SPV_NV_cooperative_matrix2 -fspv-extension=SPV_NV_tensor_addressing -fspv-extension=SPV_KHR_physical_storage_buffer %s
//
// A cooperative matrix block load through a decode function:
// VK_NV_cooperative_matrix_decode_vector / SPV_NV_cooperative_matrix_decode_vector.
//
// VK_NV_cooperative_matrix2 lets a cooperative matrix be loaded from *tensor*
// memory instead of a plain strided block: OpCooperativeMatrixLoadTensorNV takes
// a tensor layout (rank, clamp mode) and a trailing TensorAddressingOperands bit
// mask that can name a decode callback. SPV_NV_cooperative_matrix_decode_vector
// adds the DecodeVectorFunc bit to that mask: the callback it names decodes a
// *vector* of block-adjacent elements per invocation, instead of the single scalar
// element the DecodeFunc bit decodes, so one callback call can fill several
// block-adjacent matrix elements at once.
//
// The compiler emits, for the shader below:
//   OpCapability PhysicalStorageBufferAddresses
//   OpCapability TensorAddressingNV
//   OpCapability CooperativeMatrixTensorAddressingNV
//   OpCapability CooperativeMatrixBlockLoadsNV
//   OpCapability CooperativeMatrixDecodeVectorNV
//   OpExtension "SPV_NV_tensor_addressing"
//   OpExtension "SPV_NV_cooperative_matrix2"
//   OpExtension "SPV_NV_cooperative_matrix_decode_vector"
//   OpMemoryModel PhysicalStorageBuffer64 Vulkan
//   %layout = OpTypeTensorLayoutNV %uint_2 %uint_2           ; rank 2, clamp to edge
//   %tl     = OpCreateTensorLayoutNV %layout
//   %mat    = OpCooperativeMatrixLoadTensorNV %f16x16 %g_tensor %object %tl None
//             DecodeFunc|DecodeVectorFunc %__decode_func %__decode_vector_func
//   OpCooperativeMatrixStoreKHR %g_matrix %mat %int_0 %uint_16 ...
//
// Both decode functions are compiler-synthesized. SPIR-V has no operand form that
// can name an HLSL function, so CodeGen creates the pair with the signature
// SPIRV-Tools requires of them
// (external/SPIRV-Tools, ValidateCooperativeMatrixLoadStoreTensorNV):
//   %__decode_func        = OpFunction %float None %functy_float
//   %__decode_vector_func = OpFunction %v4float None %functy_v4float
// both taking (pointer to PhysicalStorageBuffer, array of 32-bit integers x2);
// the arrays' length is the Dim of the tensor layout, and the vectors' length is
// the first template argument of the entry point. Their bodies return OpUndef, so
// this compiles to a valid *encoding* of the decode-vector load: the shader says
// "decode the block through a function that returns four components at a time",
// and the decoded values are not part of the HLSL surface yet.
//
// The extension is opt-in: -fspv-extension=SPV_NV_cooperative_matrix_decode_vector
// has to be given, and so do the three prerequisites, because an explicit
// -fspv-extension list replaces the extensions that are on by default. The three
// prerequisites are not optional for the instruction -
// SPV_NV_cooperative_matrix2 defines OpCooperativeMatrixLoadTensorNV and
// SPV_NV_tensor_addressing defines the OpTypeTensorLayoutNV it reads through -
// so CodeGen always declares them; only the decode-vector extension goes through
// the FeatureManager allow-list, which is what makes it refusable.
//
// A cooperative matrix needs SPIR-V 1.6, hence -fspv-target-env=vulkan1.3, and the
// decode functions' first parameter is a PhysicalStorageBuffer pointer, which
// promotes the module's addressing model and rewrites the memory model to the
// Vulkan one (the VulkanKHR memory model is required alongside
// PhysicalStorageBufferAddresses). The pointer also adds
// OpCapability PhysicalStorageBufferAddresses, and the module *before* the
// capability trimmer runs (-fcgl shows it) also carries
// OpExtension "SPV_KHR_physical_storage_buffer"; the trimmer drops that string for
// a Vulkan 1.2+ target, where the extension is core, so it does not appear in the
// module this example produces.
//
// Required from the host - the compiler cannot check any of this:
// * enable VK_NV_COOPERATIVE_MATRIX_DECODE_VECTOR_EXTENSION_NAME at
//   vkCreateDevice, together with VK_NV_COOPERATIVE_MATRIX_2_EXTENSION_NAME and
//   VK_NV_TENSOR_ADDRESSING_EXTENSION_NAME (the base this is built on) and
//   VK_KHR_COOPERATIVE_MATRIX_EXTENSION_NAME,
// * query VkPhysicalDeviceCooperativeMatrixPropertiesKHR with
//   vkGetPhysicalDeviceCooperativeMatrixPropertiesKHR and check that a
//   combination covers this shader: M = N = 16, the A type is float32 with
//   component type float32, scope VK_SCOPE_WORKGROUP_KHR and the compute stage,
// * query VkPhysicalDeviceCooperativeMatrix2PropertiesNV with
//   vkGetPhysicalDeviceCooperativeMatrix2PropertiesNV: tensor addressing and the
//   block-loads feature have to be reported for the stage, and the decode-vector
//   feature of VK_NV_cooperative_matrix_decode_vector has to be reported as well.
//   A device that implements only the scalar DecodeFunc form rejects a module that
//   declares CooperativeMatrixDecodeVectorNV,
// * the tensor layout the device supports for the rank and clamp mode used here
//   (rank 2, VK_TENSOR_CLAMP_MODE_CLAMP_TO_EDGE_NV). The compiler emits the
//   OpTypeTensorLayoutNV the shader asks for and cannot know which ones the device
//   accepts,
// * physical storage buffer (buffer device address) support: the decode functions
//   take a PhysicalStorageBuffer pointer, so creating the pipeline needs the
//   bufferDeviceAddress feature as well.
//
// See docs/SPIR-V.rst ("NV cooperative matrix decode vector") and
// <vk/nv/cooperative_matrix_decode_vector.h>.
//
// The shader: a 16x16 float block in workgroup memory is loaded as a
// CooperativeMatrixA through a decode-vector function that decodes four components
// per call, and the matrix is then stored back into another workgroup block with
// the ordinary strided store, so the loaded value is observable.

#include <vk/nv/cooperative_matrix_decode_vector.h>

// The block is 16x16 floats, so the tensor has rank 2 and the layout's Dim is 2.
static const uint kRows = 16;
static const uint kColumns = 16;
static const uint kRowStrideInBytes = kColumns * 4;
// The decode-vector function decodes four block-adjacent components per call.
// SPV_NV_cooperative_matrix_decode_vector allows 2, 4 or 8; 8 would need
// OpCapability LongVectorEXT, which the header does not request.
static const uint kDecodeVectorLength = 4;

// The tensor the block is decoded from, and the block the matrix is stored into.
// Both live in workgroup memory, because the pointer operand of
// OpCooperativeMatrixLoadTensorNV has to be a Workgroup, StorageBuffer or
// PhysicalStorageBuffer pointer to the array, and a groupshared array is what HLSL
// hands over directly.
groupshared float g_tensor[kRows * kColumns];
groupshared float g_matrix[kRows * kColumns];

StructuredBuffer<float> g_tensorIn : register(t0);
RWStructuredBuffer<float> g_matrixOut : register(u0);

[numthreads(1, 1, 1)] void main(uint3 dispatchThreadId : SV_DispatchThreadID) {
  // Stage the tensor. A real shader would tile this over the workgroup and reuse
  // the staged block for several matrices; one invocation keeps the example about
  // the instruction.
  for (uint element = 0; element < kRows * kColumns; ++element)
    g_tensor[element] = g_tensorIn[element];
  GroupMemoryBarrierWithGroupSync();

  using Mat = vk::khr::CooperativeMatrixA<float, vk::ScopeWorkgroup, kRows,
                                          kColumns>;
  // The tensor layout: rank 2, clamping out-of-range coordinates to the edge.
  // Both operands are <id>s of 32-bit integer constants, not literals, which is
  // why they are template arguments of vk::nv::TensorLayout.
  using Layout =
      vk::nv::TensorLayout<2, vk::nv::TensorClampModeClampToEdge>;

  // The cooperative matrix the block is merged into. OpCooperativeMatrixLoadTensorNV
  // keeps the elements of Object that the decoded block does not cover, so the
  // source matrix decides the rest of the result.
  Mat source;

  // vk::nv::CreateTensorLayout -> OpCreateTensorLayoutNV (5372).
  Layout layout =
      vk::nv::CreateTensorLayout<2, vk::nv::TensorClampModeClampToEdge>();

  // OpCooperativeMatrixLoadTensorNV (5367) with
  // TensorAddressingOperands = DecodeFunc|DecodeVectorFunc. The first argument is
  // the decode vector length: 4 components per DecodeVectorFunc call.
  Mat matrix = vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV<
      kDecodeVectorLength>(g_tensor, source, layout);

  // OpCooperativeMatrixStoreKHR (4457): write the block back out, in row-major
  // order, to a workgroup array that the second loop copies to the buffer.
  matrix.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(
      vk::GetGroupSharedAddress(g_matrix[0]), kRowStrideInBytes);
  GroupMemoryBarrierWithGroupSync();

  for (uint element = 0; element < kRows * kColumns; ++element)
    g_matrixOut[element] = g_matrix[element];
}
