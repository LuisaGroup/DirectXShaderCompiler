// RUN: %dxc -T cs_6_0 -E main -fcgl -HV 2021 %s -spirv | FileCheck %s

// The other half of the L1 gate for BFloat16DotProductKHR: bfloat16_t is used,
// but no dot product is written, so only BFloat16TypeKHR may appear. The
// capability is inferred from the construct, never from the type, exactly like
// DotProduct and DotProductInput4x8BitPacked are inferred from OpSDot/OpUDot
// and not from an integer vector.

// CHECK: OpCapability Shader
// CHECK-NOT: OpCapability DotProduct
// CHECK-NOT: OpCapability DotProductInput4x8BitPacked
// CHECK: OpCapability BFloat16TypeKHR
// CHECK-NOT: OpCapability BFloat16DotProductKHR
// CHECK-NOT: OpCapability DotProduct
// CHECK-NOT: OpCapability DotProductInput4x8BitPacked
// CHECK: OpExtension "SPV_KHR_bfloat16"
// CHECK-NOT: OpExtension "SPV_KHR_integer_dot_product"
// CHECK: OpMemoryModel
// CHECK-NOT: OpDot
// CHECK: OpEntryPoint
// CHECK: %bfloat16 = OpTypeFloat 16 BFloat16KHR
// CHECK: %main = OpFunction
// CHECK-NOT: OpDot
// CHECK: %src_main = OpFunction
// CHECK-NOT: OpDot

RWStructuredBuffer<bfloat16_t> Buf;
RWStructuredBuffer<float> Out;

[numthreads(1, 1, 1)]
void main() {
  // Widening loads, so the BFloat16KHR type is genuinely used.
  float f = float(Buf[0]) + float(Buf[1]);
  Out[0] = f;
  // No dot product: no BFloat16DotProductKHR, and no OpDot at all.
  // CHECK: OpFConvert %float
  // CHECK-NOT: OpDot
  // CHECK: OpFunctionEnd
}
