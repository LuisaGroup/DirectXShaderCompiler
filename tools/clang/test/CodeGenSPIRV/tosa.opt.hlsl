// RUN: %dxc -T cs_6_0 -E main %s -spirv | FileCheck %s

// L6 optimizer-survival gate for the TOSA.001000.1 extended instruction set.
//
// The same calls as tosa.basic.hlsl, compiled *without* -fcgl, so SpirvEmitter
// runs HLSL legalization, the spirv-opt pass list and the capability-trimming pass
// before validation. Three things can go wrong only here, and only this test
// catches them:
//
//  * Capability trimming (SpirvEmitter::spirvToolsTrimCapabilities) could drop
//    TensorsARM, leaving a module that declares OpTypeTensorARM without its
//    capability. It does not: the vendored trimming pass only touches the
//    capabilities in its own table, and TensorsARM is not in it. Validation would
//    fail loudly if that changed ("Opcode TypeTensorARM requires one of these
//    capabilities: TensorsARM"), which is the negative control for this gate -
//    nothing here is compiled with -Vd.
//  * The optimizer could rewrite the OpExtInst chain. An extended instruction from
//    a set that spirv-opt has no rules for is an opaque node, so the plausible
//    failure is deletion rather than rewriting: every result below feeds the next
//    call and then an OpStore, so a chain that disappears shows up here.
//  * Legalization could copy the tensor values through Function storage in a way
//    that changes the result type. The assertions chain the ids, so a tensor that
//    came back as something other than OpTypeTensorARM breaks the match.
//
// The instruction stream itself is not asserted operand by operand: that is what
// tosa.basic.hlsl is for, and the post-optimizer stream is allowed to differ in
// everything except what is checked here.

#include <vk/arm/tosa.h>

using namespace vk::arm::tosa;

RWStructuredBuffer<float> g_out : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  Tensor<float> a;
  Tensor<float> b;
  Tensor<int> i;

  // One chain that touches the features most likely to be rewritten: a binary
  // operation, an operation with an attribute operand, an operation whose result
  // element type differs, and a shape operation whose coefficient operand is a
  // constant composite.
  Tensor<float> sum = Add(a, b);
  Tensor<float> mag = Abs(sum);
  Tensor<float> big = Maximum(NanModeIgnore, mag, b);
  Tensor<float> shaped = Reshape(big, int2(4, 4));
  Tensor<float> conv = Cast<float>(i);
  Tensor<float> both = Add(shaped, conv);

  // L1+L2 after legalization, optimization and trimming.
  //
  // The tensor values do *not* become SSA chains here: a tensor is opaque, so
  // legalization cannot forward it through a register, and each named temporary
  // stays an OpVariable in Function storage with an OpStore into it and an OpLoad
  // out of it. That is the shape this gate pins - the OpExtInst results are
  // chained through those loads, and each match names the variable it went
  // through. A pass that started folding five opaque instructions into one, or
  // that turned the chain into something else, breaks it.
  // CHECK: OpCapability TensorsARM
  // CHECK-NOT: OpCapability TensorsARM
  // CHECK: OpExtension "SPV_ARM_tensors"
  // CHECK-NOT: OpExtension "SPV_ARM_tensors"
  // CHECK: %[[TOSA:[0-9]+]] = OpExtInstImport "TOSA.001000.1"
  // CHECK-NOT: OpExtInstImport
  // CHECK: %[[TF:[A-Za-z0-9_]+]] = OpTypeTensorARM %float
  // CHECK: %[[TI:[A-Za-z0-9_]+]] = OpTypeTensorARM %int
  // CHECK: %[[ADD:[0-9]+]] = OpExtInst %[[TF]] %[[TOSA]] ADD %{{[0-9]+}} %{{[0-9]+}}
  // CHECK: OpStore %[[SUM:[0-9]+]] %[[ADD]]
  // CHECK: %[[SUML:[0-9]+]] = OpLoad %[[TF]] %[[SUM]]
  // CHECK: %[[ABS:[0-9]+]] = OpExtInst %[[TF]] %[[TOSA]] ABS %[[SUML]]
  // CHECK: OpStore %[[MAG:[0-9]+]] %[[ABS]]
  // CHECK: %[[MAGL:[0-9]+]] = OpLoad %[[TF]] %[[MAG]]
  // CHECK: %[[MAX:[0-9]+]] = OpExtInst %[[TF]] %[[TOSA]] MAXIMUM %int_1 %[[MAGL]] %{{[0-9]+}}
  // CHECK: OpStore %[[BIG:[0-9]+]] %[[MAX]]
  // CHECK: %[[BIGL:[0-9]+]] = OpLoad %[[TF]] %[[BIG]]
  // CHECK: %[[RES:[0-9]+]] = OpExtInst %[[TF]] %[[TOSA]] RESHAPE %[[BIGL]] %{{[0-9]+}}
  // CHECK: OpStore %[[SHP:[0-9]+]] %[[RES]]
  // CHECK: %[[CAST:[0-9]+]] = OpExtInst %[[TF]] %[[TOSA]] CAST %{{[0-9]+}}
  // CHECK: OpStore %[[CNV:[0-9]+]] %[[CAST]]
  // CHECK: %[[SHPL:[0-9]+]] = OpLoad %[[TF]] %[[SHP]]
  // CHECK: %[[CNVL:[0-9]+]] = OpLoad %[[TF]] %[[CNV]]
  // CHECK: OpExtInst %[[TF]] %[[TOSA]] ADD %[[SHPL]] %[[CNVL]]

  g_out[0] = float(tid.x);
}
