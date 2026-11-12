// RUN: %dxc -T cs_6_0 -E main -HV 2021 -fspv-extension=SPV_ARM_tensors %s -spirv | FileCheck %s

// L6 gate: the tensor instructions survive the shipped post-processing.
//
// arm.tensors.hlsl is the same shader with -fcgl, i.e. before legalization, the
// spiral optimizer and capability trimming. This file is the same source without
// -fcgl: everything runs, and the module still validates (no -Vd anywhere), so
// what is asserted here is that
//
//  * OpCapability TensorsARM and OpExtension "SPV_ARM_tensors" are still emitted,
//    once each, after the optimizer has rewritten the module;
//  * the three operations are *not* dropped: the read feeds a store and the
//    sizes feed a store, so they have observable results, and the writes are
//    side effects;
//  * the wrapper functions the header's templates emit in -fcgl output are gone:
//    MakeCoordinates and TensorSize are inlined, and the coordinates become an
//    OpConstantComposite, which is the encoding a hand-written module would use.
//
// A tensor read whose result is unused *is* removed by the optimizer (it is a
// pure instruction), and then the capability can disappear with it when nothing
// else uses a tensor; that is why this test keeps every result live.

#include <vk/arm/tensors.h>

RWByteAddressBuffer outBuf : register(u0);

[numthreads(1, 1, 1)] void main(uint3 tid : SV_DispatchThreadID) {
  // CHECK: OpCapability TensorsARM
  // CHECK-NOT: OpCapability TensorsARM
  // CHECK: OpExtension "SPV_ARM_tensors"
  // CHECK-NOT: OpExtension "SPV_ARM_tensors"

  vk::arm::Tensor<float, 2> f2;
  vk::arm::Coordinates<2> c2 = vk::arm::MakeCoordinates(0, 1);
  float v = vk::arm::TensorRead(f2, c2);
  vk::arm::TensorWrite(f2, c2, v + 1.0);
  uint w = vk::arm::TensorSize<1>(f2);
  vk::arm::Tensor<double, 4> d4;
  vk::arm::Coordinates<4> c4 = vk::arm::MakeCoordinates(0, 1, 2, 3);
  vk::arm::TensorWrite(d4, c4, (double)v * 2.0);
  outBuf.Store(tid.x * 8, asuint(v));
  outBuf.Store(tid.x * 8 + 4, w);

  // The ranked types survive with their rank operand, as ids of OpConstants.
  // CHECK: %[[FLOAT_TENSOR:[a-zA-Z0-9_]+]] = OpTypeTensorARM %float %uint_2
  // CHECK: %[[DOUBLE_TENSOR:[a-zA-Z0-9_]+]] = OpTypeTensorARM %double %uint_4

  // The coordinates are constant-folded into an OpConstantComposite of the
  // OpTypeArray the extension requires - the form a hand-written module uses -
  // and are then the coordinate operand of the read and of both writes.
  // CHECK: %[[COORD2:[0-9]+]] = OpConstantComposite %{{[a-zA-Z0-9_]+}} %uint_0 %uint_1
  // CHECK: %[[COORD4:[0-9]+]] = OpConstantComposite %{{[a-zA-Z0-9_]+}} %uint_0 %uint_1 %uint_2 %uint_3

  // CHECK: %[[READ:[0-9]+]] = OpTensorReadARM %float %{{[0-9]+}} %[[COORD2]]
  // CHECK: OpTensorWriteARM %{{[0-9]+}} %[[COORD2]] %{{[0-9]+}}
  // CHECK: %[[SIZE:[0-9]+]] = OpTensorQuerySizeARM %uint %{{[0-9]+}} %uint_1
  // CHECK: OpTensorWriteARM %{{[0-9]+}} %[[COORD4]] %{{[0-9]+}}

  // The read and the size still reach the buffer, so nothing above was dead.
  // CHECK: OpBitcast %uint %{{[0-9]+}}
  // CHECK: OpStore %{{[0-9]+}} %[[SIZE]]
}
