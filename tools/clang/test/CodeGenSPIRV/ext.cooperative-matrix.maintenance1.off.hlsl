// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 %s | FileCheck %s
// SPV_EXT_cooperative_matrix_maintenance1, off path (G16/L5).
//
// Sharing the module header with an extension is not a request for it: this
// shader includes <vk/khr/cooperative_matrix.h> and uses the base
// SPV_KHR_cooperative_matrix operations (Load / cast / Store), and none of the
// maintenance1 instructions, so neither the four capabilities nor
// OpExtension "SPV_EXT_cooperative_matrix_maintenance1" may appear. The
// extension is registered in FeatureManager and enabled by default, so this is
// also the check that "enabled by default" does not mean "emitted always".
//
// The two exclude regions below are anchored so that they cover the places the
// thing being excluded could appear: the first one spans the whole capability and
// extension block (from the base cooperative matrix capability up to
// OpMemoryModel), the second spans everything from there to the store, which is
// the last instruction of the shader.
#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<int> data;
int stride;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  using IntMatA = vk::khr::CooperativeMatrixA<int, vk::ScopeSubgroup, 16, 4>;
  using FloatMatA = vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, 16, 4>;
  IntMatA int_matrix =
      IntMatA::Load<vk::CooperativeMatrixLayoutColumnMajorKHR>(data, 0, stride);
  FloatMatA float_matrix = int_matrix.cast<float>();
  float_matrix.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(data, 64, stride);
}

// CHECK: OpCapability CooperativeMatrixKHR
// CHECK-NOT: CooperativeMatrixConversionsEXT
// CHECK-NOT: CooperativeMatrixReductionsEXT
// CHECK-NOT: CooperativeMatrixPerElementOperationsEXT
// CHECK-NOT: CooperativeMatrixGetCoordinateEXT
// CHECK-NOT: SPV_EXT_cooperative_matrix_maintenance1
// CHECK-NOT: CooperativeMatrixConversionsNV
// CHECK-NOT: SPV_NV_cooperative_matrix2
// CHECK: OpMemoryModel
// CHECK-NOT: OpCooperativeMatrixConvertUseEXT
// CHECK-NOT: OpCooperativeMatrixReduceEXT
// CHECK-NOT: OpCooperativeMatrixPerElementOpEXT
// CHECK-NOT: OpCooperativeMatrixGetCoordinateEXT
// CHECK: OpCooperativeMatrixStoreKHR
