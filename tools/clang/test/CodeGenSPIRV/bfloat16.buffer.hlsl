// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2018 -fcgl -Vd %s | FileCheck %s

// bfloat16_t members in structured buffers have 2-byte size and 2-byte
// alignment regardless of -enable-16bit-types, and load/store through the
// normal buffer access paths.

struct S {
  bfloat16_t a;
  bfloat16_t2 b;
  float c;
};

// bfloat16_t usage requests only the BFloat16TypeKHR capability, not Float16.
// CHECK: OpCapability BFloat16TypeKHR
// CHECK-NOT: OpCapability Float16

// bfloat16_t members have 2-byte size and 2-byte alignment.
// CHECK: OpMemberDecorate %S 0 Offset 0
// CHECK: OpMemberDecorate %S 1 Offset 2
// CHECK: OpMemberDecorate %S 2 Offset 8
// CHECK: OpDecorate %_runtimearr_S ArrayStride 12

// The BFloat16KHR type must be used; the Float16 capability and plain 16-bit
// float types must not appear.
// CHECK-NOT: OpCapability Float16
// CHECK: %bfloat16 = OpTypeFloat 16 BFloat16KHR
// CHECK-NOT: OpTypeFloat 16{{$}}
// CHECK: %S = OpTypeStruct %bfloat16 %v2bfloat16 %float
StructuredBuffer<S> g_buf;
RWStructuredBuffer<S> g_out;

[numthreads(1, 1, 1)]
void main() {
// CHECK: [[ptr:%[0-9]+]] = OpAccessChain %_ptr_Uniform_bfloat16 %g_buf %int_0 %uint_0 %int_0
// CHECK-NEXT: [[ld:%[0-9]+]] = OpLoad %bfloat16 [[ptr]]
// CHECK-NEXT: [[outptr:%[0-9]+]] = OpAccessChain %_ptr_Uniform_bfloat16 %g_out %int_0 %uint_0 %int_0
// CHECK-NEXT: OpStore [[outptr]] [[ld]]
  g_out[0].a = g_buf[0].a;

// CHECK: [[ptr2:%[0-9]+]] = OpAccessChain %_ptr_Uniform_v2bfloat16 %g_buf %int_0 %uint_2 %int_1
// CHECK-NEXT: [[ld2:%[0-9]+]] = OpLoad %v2bfloat16 [[ptr2]]
// CHECK-NEXT: [[outptr2:%[0-9]+]] = OpAccessChain %_ptr_Uniform_v2bfloat16 %g_out %int_0 %uint_1 %int_1
// CHECK-NEXT: OpStore [[outptr2]] [[ld2]]
  g_out[1].b = g_buf[2].b;
}
