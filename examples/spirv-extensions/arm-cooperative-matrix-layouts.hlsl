// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fspv-target-env=vulkan1.3 %s

// Cooperative matrix memory layouts with SPV_ARM_cooperative_matrix_layouts /
// VK_ARM_cooperative_matrix_layouts.
//
// SPV_KHR_cooperative_matrix defines two memory layouts, RowMajorKHR (0) and
// ColumnMajorKHR (1), in which Stride is a byte stride: the distance between the
// starts of two consecutive rows (row-major) or columns (column-major).
// SPV_ARM_cooperative_matrix_layouts adds two more, aimed at Arm GPUs that keep
// matrices in a blocked, interleaved form in memory:
//
//   RowBlockedInterleavedARM     4202
//   ColumnBlockedInterleavedARM  4203
//
// Both arrange the matrix in 64-byte blocks: a block holds a sub-matrix of 4 rows
// and 16 / sizeof(ComponentType) columns, stored row-major inside the block.
// RowBlockedInterleavedARM orders the blocks row-major, ColumnBlockedInterleavedARM
// column-major, and in both the blocks are interleaved at a 4-byte granularity in
// groups whose size is the Stride operand.
//
// For these two layouts Stride therefore does not mean a byte stride at all - it
// is the interleaving group size, counted in blocks, and it may only be 1, 2 or 4.
// The extension also requires it to come from a *constant* instruction, which is
// why the entry points below take it as a template argument: every ordinary HLSL
// function argument is lowered to a pointer and read back with OpLoad, so a run-time
// stride could never satisfy the rule. Passing an Arm layout to the ordinary
// Load/Store entry points is a compile error.
//
// The shapes are constrained as well, and the compiler checks them:
//   RowBlockedInterleavedARM     Rows % 4 == 0, Columns % (16 / sizeof(T)) * Stride == 0
//   ColumnBlockedInterleavedARM  Rows % 4 * Stride == 0, Columns % (16 / sizeof(T)) == 0
// This example uses a 16x16 float matrix, so 16 rows is a multiple of 4 and of
// 4 * 2, and 16 columns is a multiple of (16 / 4) * 1 and of 16 / 4.
//
// A module that uses either layout declares OpCapability CooperativeMatrixLayoutsARM
// (4201) and OpExtension "SPV_ARM_cooperative_matrix_layouts"; CodeGen infers both
// from the MemoryLayout operand of the load or store. The capability implicitly
// declares CooperativeMatrixKHR, so SPV_KHR_cooperative_matrix is required as well
// (this file gets it from <vk/khr/cooperative_matrix.h>).
//
// Required from the host:
// * Vulkan device extension VK_ARM_cooperative_matrix_layouts (enable
//   VK_ARM_COOPERATIVE_MATRIX_LAYOUTS_EXTENSION_NAME at vkCreateDevice), on top of
//   VK_KHR_cooperative_matrix and the Vulkan memory model the cooperative matrix
//   headers already assume;
// * a cooperative matrix configuration that reports
//   VkCooperativeMatrixPropertiesKHR::memoryLayout equal to
//   VK_COOPERATIVE_MATRIX_LAYOUT_ROW_BLOCKED_INTERLEAVED_ARM or
//   VK_COOPERATIVE_MATRIX_LAYOUT_COLUMN_BLOCKED_INTERLEAVED_ARM - query them with
//   vkGetPhysicalDeviceCooperativeMatrixPropertiesKHR and pick a device that
//   reports the layout, the component type and the 16x16 shape used here. The
//   layouts are device specific and there is no portable fallback, so a shader
//   built with them only runs on hardware that reports them;
// * the buffer a matrix is loaded from must be laid out by the producer with the
//   same layout and stride, and with the blocks interleaved at the same 4-byte
//   granularity. The compiler's shape checks are the only guarantee it can give:
//   it cannot verify what the host actually wrote into the buffer.
//
// See docs/SPIR-V.rst, "Arm Cooperative Matrix Memory Layouts".

#include <vk/arm/cooperative_matrix_layouts.h>

// 16x16 float cooperative matrices: A position for the operand of the multiply-add
// and the accumulator position for the result.
#define TILE 16

// Blocks written by an earlier dispatch in the RowBlockedInterleavedARM layout,
// and the destination the result is written to in the ColumnBlockedInterleavedARM
// layout.
StructuredBuffer<float> g_source : register(t0);
RWStructuredBuffer<float> g_result : register(u0);

// A groupshared staging tile, so the workgroup can hand the matrix between
// invocations without a round trip through memory.
groupshared float g_staging[TILE * TILE];

[numthreads(64, 1, 1)]
void main() {
  using FloatMatA =
      vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, TILE, TILE>;
  using FloatMatAcc =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, TILE, TILE>;

  // Read the A operand from the structured buffer. The MemoryLayout operand is
  // RowBlockedInterleavedARM (4202) and the Stride operand is the constant 1, so
  // the module declares CooperativeMatrixLayoutsARM and
  // SPV_ARM_cooperative_matrix_layouts.
  FloatMatA a = FloatMatA::LoadBlockedInterleaved<
      vk::CooperativeMatrixLayoutRowBlockedInterleavedARM, 1>(g_source, 0);

  // A second copy of the tile, read from the same buffer with the
  // column-blocked layout and a single-block interleaving group.
  FloatMatAcc other = FloatMatAcc::LoadBlockedInterleaved<
      vk::CooperativeMatrixLayoutColumnBlockedInterleavedARM, 1>(
      g_source, TILE * TILE);

  // Use the matrices: scale the A operand by 2 (OpMatrixTimesScalar) and add the
  // other tile to a splat element by element (OpFAdd).
  a = a * 2.0;
  FloatMatAcc acc = FloatMatAcc::Splat(1.0) + other;


  // Hand the result to the rest of the workgroup through groupshared memory, with
  // the ColumnBlockedInterleavedARM layout and an interleaving group of 2 blocks.
  // The workgroup-pointer overloads add the make-available/non-private and
  // make-visible/non-private memory access operands with the workgroup scope.
  acc.StoreBlockedInterleaved<
      vk::CooperativeMatrixLayoutColumnBlockedInterleavedARM, 2>(
      vk::GetGroupSharedAddress(g_staging[0]));
  FloatMatAcc staged = FloatMatAcc::LoadBlockedInterleaved<
      vk::CooperativeMatrixLayoutColumnBlockedInterleavedARM, 2>(
      vk::GetGroupSharedAddress(g_staging[0]));

  // Finally write it out with the row-blocked layout and a single-block
  // interleaving group.
  staged.StoreBlockedInterleaved<
      vk::CooperativeMatrixLayoutRowBlockedInterleavedARM, 1>(g_result, 0);
}
