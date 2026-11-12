// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_vector %s

// A matrix-vector product with VK_NV_cooperative_vector / SPV_NV_cooperative_vector.
//
// The extension adds an opaque vector type plus the instructions that consume it:
// a matrix-vector product, an accumulating one, two training accumulators, and a
// load/store pair that moves values between memory and the type. It is aimed at
// machine-learning inference, where the matrix is a weight block in device or
// workgroup memory and the vector is one activation row: the implementation can
// keep the vector in registers of the width it likes and stream the matrix,
// instead of the shader deciding on a register layout for every component.
//
// The compiler emits, for the shader below:
//
//   OpCapability CooperativeVectorNV
//   OpExtension "SPV_NV_cooperative_vector"
//   %cv4 = OpTypeVectorIdEXT %float %uint_4    ; the input vector: 4 components
//   %cv8 = OpTypeVectorIdEXT %float %uint_8    ; the result: 8 components
//   %v   = OpCooperativeVectorLoadNV %cv4 %g_input %uint_0
//   %r   = OpCooperativeVectorMatrixMulNV %cv8 %v %int_1 %g_matrix %uint_0
//                        %int_1 %uint_8 %uint_4 %int_0 %false %uint_16
//   OpCooperativeVectorStoreNV %g_output %uint_0 %r
//
// %int_1 is CooperativeVectorComponentTypeFloat32NV, %int_0 is
// CooperativeVectorMatrixLayoutRowMajorNV, %uint_8 and %uint_4 are M and K, and
// %false is Transpose. Every one of those operands has to name a *constant
// instruction*, which is why the shader below passes enumerators, integer
// literals and a bool literal - the compiler rejects a value it cannot fold
// ("... must be compile-time constants").
//
// The type comes from <vk/nv/cooperative_vector.h>, because HLSL has no type of
// its own for a cooperative vector: vk::nv::CooperativeVector<float, 8> is an
// inline SPIR-V type (OpTypeVectorIdEXT, whose component count is an id of a
// constant). The value is opaque - there is no instruction that reads or writes a
// single component - so a shader stages the inputs in memory, runs the
// instructions, and writes the result back to memory. That is also why the
// pointer operands address workgroup arrays: SPIRV-Tools requires the pointer of
// these instructions to point at an array in the Workgroup, StorageBuffer or
// PhysicalStorageBuffer storage class, and a groupshared array is what HLSL can
// hand over directly.
//
// Sizes: M = 8 rows, K = 4 columns, so the matrix is 8x4 and the result vector has
// 8 components. MatrixStride is the distance between two consecutive rows of the
// addressed array, in the units SPV_NV_cooperative_vector defines for it - 16
// bytes for four 32-bit floats. The RowMajorNV layout carries a stride; the
// InferencingOptimalNV and TrainingOptimalNV layouts leave it to the device and
// take the overload of vk::nv::MatrixMul that has no stride parameter.
//
// Required from the host - the compiler cannot check any of this:
//
// * enable VK_NV_COOPERATIVE_VECTOR_EXTENSION_NAME at vkCreateDevice.
// * query VkPhysicalDeviceCooperativeVectorPropertiesNV with
//   vkGetPhysicalDeviceCooperativeVectorPropertiesNV and check
//   cooperativeVectorSupportedStages contains VK_SHADER_STAGE_COMPUTE_BIT.
//   The *compiler* does not restrict the stage, and a shader compiled for a
//   stage the device does not list fails pipeline creation.
// * the same structure reports cooperativeVectorTrainingFloat16Accumulation,
//   cooperativeVectorTrainingFloat32Accumulation, maxCooperativeVectorComponents
//   and maxCooperativeVectorMatrixComponents. This shader needs
//   maxCooperativeVectorComponents >= 8; a device whose limit is lower still
//   compiles it and then fails pipeline creation.
// * the component type / layout pairs a stage supports are also listed there.
//   The compiler emits the pair the shader names; a pair the device does not
//   report for compute is a pipeline-creation failure, not a compile error.
// * the training half of the extension (vk::nv::OuterProductAccumulate,
//   vk::nv::ReduceSumAccumulate) has its own feature bits. This example only uses
//   the inferencing half, so its module declares CooperativeVectorNV and not
//   CooperativeVectorTrainingNV - which matters, because a module that declares
//   the training capability is rejected by a device that does not implement it.
//
// Compiler side restrictions, each diagnosed rather than miscompiled:
//
// * -fspv-extension=SPV_NV_cooperative_vector. The extension is opt-in: every
//   other shader in the tree is unchanged, and a driver without
//   VK_NV_cooperative_vector never sees a module that declares its capability.
// * there is no -fspv-target-env gate. SPV_NV_cooperative_vector has no SPIR-V
//   version requirement (the grammar spells "version": "None" for
//   OpTypeVectorIdEXT and for all six OpCooperativeVector*NV instructions), so
//   this shader also compiles and validates at the default environment,
//   vulkan1.0. -fspv-target-env=vulkan1.3 above matches the Vulkan version a host
//   would run this on, not a compiler requirement.
// * the component type has to be a 32-bit integer or a 16/32-bit float, the
//   component count at least one, and the layout/stride pairing has to match the
//   overload (see the note above).
#include <vk/nv/cooperative_vector.h>

// The matrix is 8 rows x 4 columns of 32-bit floats, the input vector has 4
// components, the result has 8.
static const uint kRows = 8;
static const uint kColumns = 4;
static const uint kRowStrideInBytes = kColumns * 4;

StructuredBuffer<float> g_matrixIn : register(t0);
StructuredBuffer<float> g_vectorIn : register(t1);
RWStructuredBuffer<float> g_result : register(u0);

// The operands the instructions read and write live in workgroup memory.
groupshared float g_matrix[kRows * kColumns];
groupshared float g_input[kColumns];
groupshared float g_output[kRows];

[numthreads(1, 1, 1)] void main(uint3 dispatchThreadId : SV_DispatchThreadID) {
  // Stage the weight block and the activation row. A real shader would tile this
  // over the workgroup and reuse the staged matrix for many vectors; one
  // invocation keeps the example about the instruction.
  for (uint element = 0; element < kRows * kColumns; ++element)
    g_matrix[element] = g_matrixIn[element];
  for (uint column = 0; column < kColumns; ++column)
    g_input[column] = g_vectorIn[column];
  GroupMemoryBarrierWithGroupSync();

  // Load the activation row as a cooperative vector of 4 components
  // (OpCooperativeVectorLoadNV).
  vk::nv::CooperativeVector<float, kColumns> input =
      vk::nv::Load<float, kColumns>(g_input, 0);

  // result[i] = sum over j of matrix[i][j] * input[j]
  // (OpCooperativeVectorMatrixMulNV). The interpretations describe how the
  // matrix in memory and the input vector are encoded; M and K are the shape of
  // the matrix, and both are also reflected in the template arguments, so the
  // result type is a cooperative vector of M components and the input is one of
  // at most K.
  vk::nv::CooperativeVector<float, kRows> result =
      vk::nv::MatrixMul<float, kRows, kColumns>(
          input, vk::CooperativeVectorComponentTypeFloat32NV,
          // The matrix, the byte offset into it and its interpretation.
          g_matrix, 0, vk::CooperativeVectorComponentTypeFloat32NV,
          // M, K, the memory layout, whether the matrix is transposed, and the
          // stride between two rows.
          kRows, kColumns, vk::CooperativeVectorMatrixLayoutRowMajorNV,
          /*transpose*/ false, kRowStrideInBytes);

  // Write the result back to workgroup memory (OpCooperativeVectorStoreNV) and
  // from there to the output buffer. The vector itself is opaque: this pair is
  // the only way in and out of the type.
  vk::nv::Store<float, kRows>(g_output, 0, result);
  GroupMemoryBarrierWithGroupSync();

  for (uint row = 0; row < kRows; ++row)
    g_result[dispatchThreadId.x * kRows + row] = g_output[row];
}
