// RUN: %dxc -T cs_6_0 -E main -fcgl -HV 2021 %s -spirv | FileCheck %s

// SPV_KHR_bfloat16's BFloat16DotProductKHR: dot() on bfloat16_t vector operands
// lowers to OpDot with a BFloat16KHR component type.
//
// OpDot - not OpSDot/OpUDot - is the instruction the extension extends.
// ValidateSameSignedDot (SPIRV-Tools' OpSDot/OpUDot check) requires an integer
// result type, so a bfloat16 component cannot be encoded with the integer dot
// product instructions; ValidateDot is where BFloat16DotProductKHR is enforced.
// The module therefore must NOT pick up the SPV_KHR_integer_dot_product
// capabilities as well.

// The capability and the extension are declared exactly once, and neither the
// DotProduct family nor the packed-8-bit dependency is dragged in.
// CHECK: OpCapability Shader
// CHECK-NOT: OpCapability Float16
// CHECK-NOT: OpCapability StorageInputOutput16
// CHECK-NOT: OpCapability DotProduct
// CHECK-NOT: OpCapability DotProductInput4x8BitPacked
// CHECK: OpCapability BFloat16TypeKHR
// CHECK-NOT: OpCapability BFloat16TypeKHR
// CHECK-NOT: OpCapability DotProduct
// CHECK: OpCapability BFloat16DotProductKHR
// CHECK-NOT: OpCapability BFloat16DotProductKHR
// CHECK-NOT: OpCapability DotProduct
// CHECK-NOT: OpCapability DotProductInput4x8BitPacked
// CHECK: OpExtension "SPV_KHR_bfloat16"
// CHECK-NOT: OpExtension "SPV_KHR_bfloat16"
// CHECK-NOT: OpExtension "SPV_KHR_integer_dot_product"
// CHECK: OpMemoryModel

// bfloat16_t is still an OpTypeFloat 16 with the BFloat16KHR encoding.
// CHECK: %bfloat16 = OpTypeFloat 16 BFloat16KHR
// CHECK: %v2bfloat16 = OpTypeVector %bfloat16 2
// CHECK: %v4bfloat16 = OpTypeVector %bfloat16 4

RWStructuredBuffer<bfloat16_t> Out;
RWStructuredBuffer<float> OutF;

[numthreads(1, 1, 1)]
void main() {
  bfloat16_t2 a = bfloat16_t2(1.0, 2.0);
  bfloat16_t2 b = bfloat16_t2(3.0, 4.0);
  bfloat16_t4 c = bfloat16_t4(1.0, 2.0, 3.0, 4.0);
  bfloat16_t4 d = bfloat16_t4(5.0, 6.0, 7.0, 8.0);

  // The result type is the bfloat16_t component type, not float, and the
  // operands are consumed as bfloat16 vectors: widening them with OpFConvert
  // first would satisfy an opcode-only check while defeating the capability.
  // CHECK-NOT: OpFConvert %v2float
  // CHECK: [[a2:%[0-9]+]] = OpLoad %v2bfloat16 %a
  // CHECK-NEXT: [[b2:%[0-9]+]] = OpLoad %v2bfloat16 %b
  // CHECK-NEXT: [[dot2:%[0-9]+]] = OpDot %bfloat16 [[a2]] [[b2]]
  bfloat16_t r2 = dot(a, b);
  // CHECK-NEXT: OpStore %r2 [[dot2]]
  Out[0] = r2;

  // A 4-component dot product is the same instruction; only the operand width
  // differs.
  // CHECK: [[c4:%[0-9]+]] = OpLoad %v4bfloat16 %c
  // CHECK-NEXT: [[d4:%[0-9]+]] = OpLoad %v4bfloat16 %d
  // CHECK-NEXT: [[dot4:%[0-9]+]] = OpDot %bfloat16 [[c4]] [[d4]]
  bfloat16_t r4 = dot(c, d);
  // CHECK-NEXT: OpStore %r4 [[dot4]]
  Out[1] = r4;

  // The documented conversion model still applies to the result: a float
  // destination widens the bfloat16 dot product with a trailing OpFConvert
  // instead of widening the operands.
  // CHECK: [[af:%[0-9]+]] = OpLoad %v2bfloat16 %a
  // CHECK-NEXT: [[bf:%[0-9]+]] = OpLoad %v2bfloat16 %b
  // CHECK-NEXT: [[dotf:%[0-9]+]] = OpDot %bfloat16 [[af]] [[bf]]
  // CHECK-NEXT: OpFConvert %float [[dotf]]
  OutF[0] = dot(a, b);
}
