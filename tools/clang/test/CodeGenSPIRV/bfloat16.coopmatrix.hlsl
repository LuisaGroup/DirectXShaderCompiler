// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -HV 2021 %s -spirv | FileCheck %s

// SPV_KHR_bfloat16's BFloat16CooperativeMatrixKHR:
// vk::khr::CooperativeMatrix<bfloat16_t, ...> is a cooperative matrix whose
// OpTypeCooperativeMatrixKHR component type is OpTypeFloat 16 BFloat16KHR, so
// the module needs BFloat16CooperativeMatrixKHR in addition to the
// CooperativeMatrixKHR capability the header already requests (the dependent
// capability relation is the thing that is easy to forget) and the
// BFloat16TypeKHR capability of the component type itself.
//
// CHECK: OpCapability CooperativeMatrixKHR
// CHECK: OpCapability BFloat16TypeKHR
// CHECK-NOT: OpCapability BFloat16TypeKHR
// CHECK: OpCapability BFloat16CooperativeMatrixKHR
// CHECK-NOT: OpCapability BFloat16CooperativeMatrixKHR
// CHECK-NOT: OpCapability CooperativeMatrixKHR
// CHECK: OpExtension "SPV_KHR_bfloat16"
// CHECK-NOT: OpExtension "SPV_KHR_bfloat16"
// CHECK-NOT: OpExtension "SPV_KHR_integer_dot_product"

#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<bfloat16_t> data;

[numthreads(64, 1, 1)]
void main() {
  using CoopMatA =
      vk::khr::CooperativeMatrixA<bfloat16_t, vk::ScopeSubgroup, 16, 8>;
  using CoopMatB =
      vk::khr::CooperativeMatrixB<bfloat16_t, vk::ScopeSubgroup, 8, 8>;
  using CoopMatAcc =
      vk::khr::CooperativeMatrixAccumulator<bfloat16_t, vk::ScopeSubgroup, 16,
                                            8>;

  // The component type keeps its BFloat16KHR encoding inside the cooperative
  // matrix type rather than decaying to a plain 16-bit float. The declaration
  // order of the three types depends on template instantiation order.
  // CHECK: %bfloat16 = OpTypeFloat 16 BFloat16KHR
  // CHECK-DAG: [[typeA:%spirvIntrinsicType[_0-9]*]] = OpTypeCooperativeMatrixKHR %bfloat16 %uint_3 %uint_16 %uint_8 %uint_0
  // CHECK-DAG: [[typeB:%spirvIntrinsicType[_0-9]*]] = OpTypeCooperativeMatrixKHR %bfloat16 %uint_3 %uint_8 %uint_8 %uint_1
  // CHECK-DAG: [[typeAcc:%spirvIntrinsicType[_0-9]*]] = OpTypeCooperativeMatrixKHR %bfloat16 %uint_3 %uint_16 %uint_8 %uint_2

  CoopMatA a =
      CoopMatA::Load<vk::CooperativeMatrixLayoutColumnMajorKHR>(data, 0, 64);
  CoopMatB b =
      CoopMatB::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(data, 8, 64);
  CoopMatAcc c =
      CoopMatAcc::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(data, 16, 64);

  // A bfloat16 component type is not an integer type, so the
  // Matrix*SignedComponentsKHR operand bits must all be clear: the mask operand
  // has to be NoneKHR.
  // CHECK: OpCooperativeMatrixMulAddKHR [[typeAcc]] {{%[0-9]+}} {{%[0-9]+}} {{%[0-9]+}} NoneKHR
  CoopMatAcc r = vk::khr::cooperativeMatrixMultiplyAdd(a, b, c);

  // CHECK: OpCooperativeMatrixLengthKHR %uint [[typeAcc]]
  uint32_t length = CoopMatAcc::GetLength();

  // The three loads and the store, reached through the header's helper
  // functions.
  // CHECK: [[la:%[0-9]+]] = OpCooperativeMatrixLoadKHR [[typeA]]
  // CHECK: [[lb:%[0-9]+]] = OpCooperativeMatrixLoadKHR [[typeB]]
  // CHECK: [[lc:%[0-9]+]] = OpCooperativeMatrixLoadKHR [[typeAcc]]
  // CHECK: OpCooperativeMatrixStoreKHR

  r.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(data, 0, 64);
  data[1] = bfloat16_t(float(length));
}
