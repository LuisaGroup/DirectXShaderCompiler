// RUN: %dxc -T cs_6_0 -E main -fcgl -HV 2021 -fspv-extension=SPV_ARM_tensors %s -spirv | FileCheck %s

// L0/L1/L2 gates for SPV_ARM_tensors: the tensor type and the three operations
// that read, write and measure it.
//
// The surface is <vk/arm/tensors.h>:
//
//   vk::arm::Tensor<float, 2>   ->  %t = OpTypeTensorARM %float %uint_2
//   vk::arm::Coordinates<2>     ->  %c = OpTypeArray %uint %uint_2
//   vk::arm::MakeCoordinates    ->  %c = OpCompositeConstruct %c %uint_0 %uint_1
//   vk::arm::TensorRead         ->  %r = OpTensorReadARM %float %t %c
//   vk::arm::TensorWrite        ->  OpTensorWriteARM %t %c %v      (no result)
//   vk::arm::TensorSize<d>      ->  %r = OpTensorQuerySizeARM %uint %t %uint_<d>
//
// The instruction numbers are 4163 (OpTypeTensorARM), 4164 (OpTensorReadARM),
// 4165 (OpTensorWriteARM) and 4166 (OpTensorQuerySizeARM); the capability is
// TensorsARM (4174). Each number is the one
// external/SPIRV-Headers/include/spirv/unified1/spirv.core.grammar.json assigns,
// and the mnemonic this test asserts is the one SPIRV-Tools decodes, so a wrong
// number would either print a different mnemonic or be rejected by the
// validator (no test here passes -Vd).
//
// The tensor value comes from an uninitialized local: HLSL has no resource
// spelling for a tensor descriptor, which is why <vk/arm/tensors.h> documents
// that a tensor *resource* is not expressible yet. What this test pins is the
// encoding, not where the handle came from.

#include <vk/arm/tensors.h>

RWByteAddressBuffer outBuf : register(u0);

[numthreads(1, 1, 1)] void main(uint3 tid : SV_DispatchThreadID) {
  // L1: the capability and the extension are inferred from the tensor type, and
  // each appears exactly once. The CHECK-NOT runs are anchored between the
  // surrounding module-level lines so that a duplicated
  // OpCapability/OpExtension fails here.
  // CHECK: OpCapability Shader
  // CHECK: OpCapability TensorsARM
  // CHECK-NOT: OpCapability TensorsARM
  // CHECK: OpExtension "SPV_ARM_tensors"
  // CHECK-NOT: OpExtension "SPV_ARM_tensors"
  // CHECK: OpMemoryModel Logical GLSL450

  // L2: the type carries its element type as a type operand and its rank as the
  // id of a 32-bit integer constant - not as a literal - and the rank of a
  // second tensor shows that the operand is passed through, not hard-coded.
  // CHECK: %[[FLOAT_TENSOR:[a-zA-Z0-9_]+]] = OpTypeTensorARM %float %uint_2
  // CHECK: %[[FLOAT_COORD:[a-zA-Z0-9_]+]] = OpTypeArray %uint %uint_2
  // CHECK: %[[DOUBLE_TENSOR:[a-zA-Z0-9_]+]] = OpTypeTensorARM %double %uint_4
  // CHECK: %[[DOUBLE_COORD:[a-zA-Z0-9_]+]] = OpTypeArray %uint %uint_4

  vk::arm::Tensor<float, 2> f2;
  vk::arm::Coordinates<2> c2 = vk::arm::MakeCoordinates(0, 1);

  // The coordinates are one composite operand of array type, not one operand per
  // dimension: OpCompositeConstruct (80) over the OpTypeArray above.
  // CHECK: %{{[0-9]+}} = OpCompositeConstruct %[[FLOAT_COORD]] %uint_0 %uint_1

  // L2: OpTensorReadARM (4164), result type = the tensor's element type, and the
  // operand order (Tensor, Coordinates). The coordinates operand is the value
  // loaded out of the local, whose type is the OpTypeArray the extension
  // requires.
  // CHECK: %[[READ:[0-9]+]] = OpTensorReadARM %float %{{[0-9]+}} %{{[0-9]+}}
  float v = vk::arm::TensorRead(f2, c2);

  // L2: OpTensorWriteARM (4165) has no result id, and its three operands are
  // (Tensor, Coordinates, Object) - the value written is a plain operand, not an
  // out-parameter pointer or a pointer to the value. Two runs make both halves
  // of that fail loudly:
  //  * the CHECK-NOT of '=' covers the text between the end of the OpFAdd and
  //    the start of the write, so an instruction that did have a result id would
  //    leave "%59 = " there and be caught;
  //  * the CHECK-NOT of None covers the rest of the write line, so a stray
  //    TensorOperands mask - the optional fourth operand - would be caught.
  // CHECK: %{{[0-9]+}} = OpFAdd %float %{{[0-9]+}} %float_1
  // CHECK-NOT: =
  // CHECK: OpTensorWriteARM %[[WT:[0-9]+]] %[[WC:[0-9]+]] %[[WV:[0-9]+]]
  // CHECK-NOT: None
  // CHECK-NEXT: %{{[0-9]+}} = OpLoad %[[FLOAT_TENSOR]]
  vk::arm::TensorWrite(f2, c2, v + 1.0);

  // The dimension of OpTensorQuerySizeARM (4166) must name a constant
  // instruction, so TensorSize takes it as a template argument; the operand is
  // the id of an OpConstant, and the result type is an integer scalar, not the
  // tensor's element type. In -fcgl output the wrapper is a real function (it is
  // inlined once legalization runs, which is what arm.tensors.opt.hlsl checks),
  // so the instruction itself is emitted at the end of the module.
  uint w = vk::arm::TensorSize<1>(f2);

  // The same operations over a rank-4 tensor of doubles: the rank and the
  // element type of the type determine the operands of the instructions, and
  // nothing depends on the rank being 2 or the element type being float.
  vk::arm::Tensor<double, 4> d4;
  vk::arm::Coordinates<4> c4 = vk::arm::MakeCoordinates(0, 1, 2, 3);
  // CHECK: %{{[0-9]+}} = OpCompositeConstruct %[[DOUBLE_COORD]] %uint_0 %uint_1 %uint_2 %uint_3
  // CHECK: %{{[0-9]+}} = OpFMul %double %{{[0-9]+}} %double_2
  // CHECK-NOT: =
  // CHECK: OpTensorWriteARM %{{[0-9]+}} %{{[0-9]+}} %{{[0-9]+}}
  // CHECK-NOT: None
  // CHECK-NEXT: %{{[0-9]+}} = OpAccessChain
  vk::arm::TensorWrite(d4, c4, (double)v * 2.0);

  // The reads feed an observable store, so the operations cannot be dropped as
  // dead code (arm.tensors.opt.hlsl is the gate that runs the optimizer and
  // proves it).
  // CHECK: %{{[0-9]+}} = OpBitcast %uint %{{[0-9]+}}
  outBuf.Store(tid.x * 8, asuint(v));
  outBuf.Store(tid.x * 8 + 4, w);

  // L2: the tensor also crosses a user function boundary. TensorSize's wrapper
  // takes the tensor by value, and LowerTypeVisitor passes a function parameter
  // as a pointer to the parameter's type, so the signature keeps the tensor type
  // - the opaque handle is not flattened into anything.
  // CHECK: %{{[a-zA-Z0-9_]+}} = OpFunctionParameter %_ptr_Function_[[FLOAT_TENSOR]]

  // L2: OpTensorQuerySizeARM (4166) in the emitted wrapper: (Tensor, Dimension),
  // where Dimension is the id of an OpConstant and the result is a uint.
  // CHECK: %[[SIZE:[0-9]+]] = OpTensorQuerySizeARM %uint %{{[0-9]+}} %uint_1
  // CHECK-NEXT: OpReturnValue %[[SIZE]]
}
