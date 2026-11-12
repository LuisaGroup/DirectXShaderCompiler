// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -fcgl -HV 2021 %s | FileCheck %s

// A cooperative matrix with a *floating-point* component type must not set any
// of the Matrix*SignedComponentsKHR / MatrixResultSignedComponentsKHR operand
// bits: SPIRV-Tools only allows those for integer components.
//
// Those bits come from the HasSignedIntegerComponentType probe in
// vk/khr/cooperative_matrix.h, which used to test integer-ness with
// "(T(0) - T(1) < T(0))" - an expression that is also true for float, so a float
// multiply-add emitted "MatrixASignedComponentsKHR|MatrixBSignedComponentsKHR|..."
// and the module failed validation. The probe now uses integer division, and this
// test pins the result.
// The integer counterpart is coopmatrix_muladd_test.hlsl, which keeps asserting
// the signed-components mask for int and must stay unchanged.

// CHECK: OpCapability CooperativeMatrixKHR
// CHECK: OpExtension "SPV_KHR_cooperative_matrix"
// CHECK-DAG: [[typeA:%spirvIntrinsicType[_0-9]*]] = OpTypeCooperativeMatrixKHR %float %uint_3 %uint_16 %uint_4 %uint_0
// CHECK-DAG: [[typeB:%spirvIntrinsicType[_0-9]*]] = OpTypeCooperativeMatrixKHR %float %uint_3 %uint_4 %uint_8 %uint_1
// CHECK-DAG: [[typeC:%spirvIntrinsicType[_0-9]*]] = OpTypeCooperativeMatrixKHR %float %uint_3 %uint_16 %uint_8 %uint_2
// The decisive assertion: no signed-components bit for a float matrix.
// Note: with -fcgl the multiply-add is emitted inside the header helper
// function, i.e. before the user function's loads, so the load forms are not
// ordered against it here.
// CHECK: OpCooperativeMatrixMulAddKHR [[typeC]] {{%[0-9]+}} {{%[0-9]+}} {{%[0-9]+}} NoneKHR
// CHECK-NOT: OpCooperativeMatrixMulAddKHR {{.*}}SignedComponentsKHR

#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<float> data;
uint stride;

[numthreads(64, 1, 1)] void main() {
  using FloatMatA = vk::khr::CooperativeMatrixA<float, vk::ScopeSubgroup, 16, 4>;
  using FloatMatB = vk::khr::CooperativeMatrixB<float, vk::ScopeSubgroup, 4, 8>;
  using FloatMatAc =
      vk::khr::CooperativeMatrixAccumulator<float, vk::ScopeSubgroup, 16, 8>;

  FloatMatA a = FloatMatA::Load<vk::CooperativeMatrixLayoutColumnMajorKHR>(
      data, 0, stride);
  FloatMatB b =
      FloatMatB::Load<vk::CooperativeMatrixLayoutRowMajorKHR>(data, 32, stride);
  FloatMatAc r;
  r = cooperativeMatrixMultiplyAdd(a, b, r);
  if (r.Get(0) > 0.0)
    data[0] = r.Get(0);
}
