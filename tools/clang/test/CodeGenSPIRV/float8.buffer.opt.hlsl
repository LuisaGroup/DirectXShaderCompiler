// RUN: %dxc -T cs_6_0 -E main -HV 2021 %s -spirv | FileCheck %s

// L6: the float8 storage layout of float8.buffer.hlsl after the full
// post-processing chain. The one-byte ArrayStride and the struct member offsets
// must reach the final module unchanged; an optimizer that treated OpTypeFloat 8
// as a 32-bit type would rewrite them, and the capability trim pass must keep
// Float8EXT and SPV_EXT_float8 alive.
//
// CHECK-NOT: OpCapability Int8
// CHECK-NOT: OpCapability StorageBuffer8BitAccess
// CHECK-NOT: OpCapability UniformAndStorageBuffer8BitAccess
// CHECK: OpCapability Float8EXT
// CHECK-NOT: OpCapability Float8EXT
// CHECK: OpExtension "SPV_EXT_float8"
// CHECK-NOT: OpExtension "SPV_EXT_float8"

struct S {
  float8_e4m3_t a;
  float8_e5m2_t b;
  float8_e4m3_t2 c;
  float d;
};

// The layout after optimization: the struct keeps its one-byte members at the
// natural offsets and is 8 bytes wide, and the float8 buffer element is one
// byte.
// CHECK: OpMemberDecorate %S 0 Offset 0
// CHECK: OpMemberDecorate %S 1 Offset 1
// CHECK: OpMemberDecorate %S 2 Offset 2
// CHECK: OpMemberDecorate %S 3 Offset 4
// CHECK: OpDecorate %_runtimearr_S ArrayStride 8
// CHECK: OpDecorate %_runtimearr_fp8e4m3 ArrayStride 1

// Both encodings survive as 8-bit floats.
// CHECK: %fp8e4m3 = OpTypeFloat 8 Float8E4M3EXT
// CHECK: %fp8e5m2 = OpTypeFloat 8 Float8E5M2EXT
// CHECK: %v2fp8e4m3 = OpTypeVector %fp8e4m3 2
// CHECK-NOT: OpTypeFloat 8{{$}}
// CHECK: %S = OpTypeStruct %fp8e4m3 %fp8e5m2 %v2fp8e4m3 %float

StructuredBuffer<S> In;
RWStructuredBuffer<float8_e4m3_t> Out;

[numthreads(1, 1, 1)]
void main() {
  S s = In[0];
  // The arithmetic widens each float8 member to float, and the store converts
  // the float back to the stored format.
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  float sum = float(s.a) + float(s.b) + float(s.c.x) + float(s.c.y) + s.d;
  // CHECK: OpFConvert %fp8e4m3
  // CHECK: OpStore
  Out[0] = float8_e4m3_t(sum);
}
