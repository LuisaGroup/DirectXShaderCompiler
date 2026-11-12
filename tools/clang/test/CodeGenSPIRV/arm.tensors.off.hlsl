// RUN: %dxc -T cs_6_0 -E main -fcgl -HV 2021 %s -spirv | FileCheck %s
// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-extension=SPV_KHR_8bit_storage %s -spirv | FileCheck %s

// L5 gate: with the feature off, the module is exactly what it was before
// SPV_ARM_tensors existed.
//
// The shader includes <vk/arm/tensors.h> and uses none of it, which is the
// interesting case: the capability and the extension are inferred from the
// OpTypeTensorARM type, so a header that requested them from its declarations -
// or a compiler that emitted them from an include - would show up here. The
// second RUN adds an explicit -fspv-extension list that does not name
// SPV_ARM_tensors, so it also covers the allow-list mode of FeatureManager; the
// same list *with* the extension is arm.tensors.hlsl, and a tensor used under a
// list that omits it is arm.tensors.extension.error.hlsl.
//
// Nothing in the module may be added, and the two guards below are what would
// catch a leak: the tensor type, any tensor operation, the capability and the
// extension.

#include <vk/arm/tensors.h>

RWByteAddressBuffer outBuf : register(u0);

typedef vk::arm::Tensor<float, 2> UnusedTensor;
typedef vk::arm::Coordinates<2> UnusedCoordinates;

[numthreads(1, 1, 1)] void main(uint3 tid : SV_DispatchThreadID) {
  // CHECK: OpCapability Shader
  // CHECK-NOT: OpCapability TensorsARM
  // CHECK-NOT: OpExtension "SPV_ARM_tensors"
  // CHECK: OpMemoryModel Logical GLSL450
  // CHECK-NOT: OpTypeTensorARM
  // CHECK-NOT: OpTensorReadARM
  // CHECK-NOT: OpTensorWriteARM
  // CHECK-NOT: OpTensorQuerySizeARM
  // CHECK-NOT: OpTypeArray %uint %uint_2
  outBuf.Store(tid.x * 4, tid.x);
}
