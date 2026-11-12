// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fspv-target-env=vulkan1.3 %s

// Reductions, use conversions, per-element operations and index-to-coordinate
// conversion on cooperative matrices, with VK_EXT_cooperative_matrix_maintenance1
// / SPV_EXT_cooperative_matrix_maintenance1.
//
// SPV_KHR_cooperative_matrix can load, store, multiply and splat a matrix, but it
// cannot take a matrix apart or hand one role's tile to another role. The
// maintenance1 extension adds four operations, each with its own capability:
// OpCooperativeMatrixConvertUseEXT (5293)   CooperativeMatrixConversionsEXT (5429)
// OpCooperativeMatrixReduceEXT (5366)   CooperativeMatrixReductionsEXT (5430)
// OpCooperativeMatrixPerElementOpEXT (5369) CooperativeMatrixPerElementOperationsEXT (5432)
// OpCooperativeMatrixGetCoordinateEXT (5363)  CooperativeMatrixGetCoordinateEXT (5438)
// The header entry points are CooperativeMatrix::ConvertUse, ::Reduce,
// ::PerElementOp and ::GetCoordinate in <vk/khr/cooperative_matrix.h>. A module
// that uses any of them declares the matching capability and, once,
// OpExtension "SPV_EXT_cooperative_matrix_maintenance1"; this compiler does that
// automatically, so the RUN line above needs no -fspv-extension, and
// -fspv-extension=SPV_EXT_cooperative_matrix_maintenance1 is only needed when a
// -fspv-extension list is given (an explicit list is an allow-list and would
// otherwise switch the extension off).
//
// What the shader below does, in the shape of a two-stage GEMM:
// * the accumulator tile C of a 16x16 step is loaded from a structured buffer;
// * C is reduced across rows to one value per row (a row-sum of the partial
// accumulators, which a shared-memory reduction would otherwise need one
// invocation per element for);
// * the coordinate of element `tid.x` is asked for, which is what a lane needs in
// order to know which (row, column) of the *source* tile the accumulator element
// it holds came from;
// * C is reinterpreted as the A operand of the next multiply-add. The values are
// not touched: only the CooperativeMatrixUse of the type changes.
// One 16x16 accumulator and one 16x1 result are used so that the shapes are legal
// for both the reduce (Row keeps the row count) and the conversion (which keeps
// every shape and only changes the use).
//
// What the host has to do, none of which the compiler can check:
// * enable VkPhysicalDeviceCooperativeMatrixFeaturesKHR::cooperativeMatrix before
// creating the pipeline, and query
// VkPhysicalDeviceCooperativeMatrixPropertiesKHR through
// vkGetPhysicalDeviceCooperativeMatrixPropertiesKHR (or the
// cooperativeMatrixProperties2 form when chaining
// VkCooperativeMatrixPropertiesKHR) for the shapes, component types and scopes
// this shader asks for: 16x16 and 16x1 accumulators in Subgroup scope. The
// extension adds no new property struct, so a host that already exposes the base
// extension's properties is enough - the four capabilities are reported through
// VkPhysicalDeviceCooperativeMatrixFeaturesKHR only if the driver implements
// them, which is why the shader must stay optional in the application;
// * the maintenance1 pNext chain: VkCooperativeMatrixPropertiesKHR reports the
// (M, N, K, AType, BType, CType, ResultType, saturatingAccumulation, scope)
// tuples the device accepts. A driver without VK_EXT_cooperative_matrix_maintenance1
// accepts the module only if the four instructions were not used, so an
// application that compiles this shader has to select it at pipeline creation.

#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<float> g_accumulator;   // 16x16 partial accumulator tile
RWStructuredBuffer<float> g_nextA;         // 16x16 A operand of the next stage
RWStructuredBuffer<float> g_rowSum;        // 16x1 row reduction of the tile
RWStructuredBuffer<float> g_blockSum;      // 8x8 2x2-block reduction of the tile
RWStructuredBuffer<uint2> g_coordinates;   // where each lane's element came from

static const uint TILE = 16;
static const uint stride = TILE * 4;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  using Accumulator =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, TILE, TILE>;
  using AccumulatorRow =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, TILE, 1>;
  using MatrixA = vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, TILE, TILE>;

  // The C tile of this step.
  Accumulator c =
      Accumulator::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(g_accumulator,
                                                               0, stride);

  // Reduce it across rows: 16x16 -> 16x1, one value per row.
  // The mode is a template argument because the CooperativeMatrixReduce operand
  // of the instruction is a literal bit mask, not an id; Row is 0x1. The last
  // operand of OpCooperativeMatrixReduceEXT in the module is a reference to a
  // combine function that this compiler synthesizes (__coopmat_combine, which
  // returns OpUndef), so the instruction is encoded but the combining arithmetic
  // is not defined - see docs/SPIR-V.rst.
  AccumulatorRow rowSum = c.Reduce<TILE, 1, vk::CooperativeMatrixReduceRow>();
  rowSum.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(g_rowSum, 0, stride);

  // Reduce every 2x2 block to one value: 16x16 -> 8x8. For this mode the result
  // has to be exactly half the source in both dimensions, so the shape is part of
  // the template arguments and a wrong one is a compile error.
  using AccumulatorBlock =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, TILE / 2,
                                            TILE / 2>;
  AccumulatorBlock blockSum =
      c.Reduce<TILE / 2, TILE / 2, vk::CooperativeMatrixReduce2x2>();
  blockSum.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(g_blockSum, 0, stride);

  // Map this lane's element index to the (row, column) it came from. The result
  // is a uvec2: OpCooperativeMatrixGetCoordinateEXT requires a two-component
  // 32-bit integer vector.
  uint2 coordinate = c.GetCoordinate(tid.x);
  g_coordinates[tid.x] = coordinate;

  // Apply a per-element operation. The result type has to be identical to the
  // source type, so this only makes sense once the operation is known; like the
  // reduce, the referenced function (__coopmat_perelem) is synthesized and its
  // body is not defined yet.
  Accumulator scaled = c.PerElementOp();

  // Hand the accumulator to the A operand position of the next multiply-add. The
  // 16x16 shape and the component type are unchanged; only the use differs, which
  // is the one conversion the extension allows besides A/B -> accumulator.
  MatrixA nextA = scaled.ConvertUse<vk::CooperativeMatrixUseMatrixAKHR>();
  nextA.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(g_nextA, 0, stride);
}
