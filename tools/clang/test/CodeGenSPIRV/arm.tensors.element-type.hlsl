// RUN: %dxc -T cs_6_2 -E main -fcgl -HV 2021 -enable-16bit-types -fspv-extension=SPV_ARM_tensors %s -spirv | FileCheck %s

// L2 gate for the *element type* of a tensor, and for rank 1.
//
// OpTypeTensorARM's Element Type is an operand of the type, not its result type,
// so SPIR-V CodeGen's generic handling of a type never visits it: a
// Tensor<half, N> would lose OpCapability Float16 unless the tensor case in
// CapabilityVisitor propagates the capabilities of the element type. This file is
// the gate for that - it is the only place where a tensor's element type needs a
// capability of its own (float, double, int and uint need none beyond what the
// shader already declares).
//
// It also covers rank 1 and dimension 0: Coordinates<1> is a one-element
// OpTypeArray, and TensorSize<0> is the only dimension a rank-1 tensor has.
// TensorWrite takes the value in a non-deduced context
// (tensors_detail::Identity), so a literal converts to the element type instead
// of participating in template argument deduction - `TensorWrite(h, c, 1.0)` is
// written to a half here.

#include <vk/arm/tensors.h>

RWByteAddressBuffer outBuf : register(u0);

[numthreads(1, 1, 1)] void main() {
  // The element type needs a capability of its own even though the instruction
  // that carries the type does not: half is Float16, and the tensor adds
  // TensorsARM next to it.
  // CHECK: OpCapability Float16
  // CHECK: OpCapability TensorsARM
  // CHECK: OpExtension "SPV_ARM_tensors"

  vk::arm::Tensor<half, 1> h;
  vk::arm::Coordinates<1> c = vk::arm::MakeCoordinates(0);
  // CHECK: %[[HALF:half]] = OpTypeFloat 16
  // CHECK: %[[ONE:[a-zA-Z0-9_]+]] = OpConstant %half 0x1p+0
  // The element type and the rank are the two operands of the type.
  // CHECK: %{{[a-zA-Z0-9_]+}} = OpTypeTensorARM %[[HALF]] %uint_1
  // CHECK: %{{[a-zA-Z0-9_]+}} = OpTypeArray %uint %uint_1
  vk::arm::TensorWrite(h, c, 1.0);
  // CHECK: OpTensorWriteARM %{{[0-9]+}} %{{[0-9]+}} %[[ONE]]
  half v = vk::arm::TensorRead(h, c);
  // CHECK: %{{[0-9]+}} = OpTensorReadARM %[[HALF]] %{{[0-9]+}} %{{[0-9]+}}
  outBuf.Store(0, uint(vk::arm::TensorSize<0>(h)));
  // CHECK: %{{[0-9]+}} = OpTensorQuerySizeARM %uint %{{[0-9]+}} %uint_0
  outBuf.Store(4, asuint(float(v)));
}
