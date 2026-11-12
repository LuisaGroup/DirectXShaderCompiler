// RUN: %dxc -T cs_6_2 -E main -spirv -HV 2021 -fcgl -enable-16bit-types %s | FileCheck %s

// float8 and float16_t side by side.
//
// A float8 type is always 8 bits wide and never aliases float16_t, but it does
// convert into float16_t and back through an explicit cast (both float8 formats
// are exactly representable in binary16). The module therefore has to carry both
// encodings: OpTypeFloat 8 with Float8E4M3EXT for float8_e4m3_t and an
// unencoded OpTypeFloat 16 for float16_t, which also means the Float16
// capability is requested for the float16_t half only.

// CHECK: OpCapability Float16
// CHECK: OpCapability Float8EXT
// CHECK-NOT: OpCapability Float8EXT
// CHECK: OpExtension "SPV_EXT_float8"
// CHECK-DAG: %half = OpTypeFloat 16
// CHECK-DAG: %fp8e4m3 = OpTypeFloat 8 Float8E4M3EXT
// CHECK-DAG: %fp8e5m2 = OpTypeFloat 8 Float8E5M2EXT
// CHECK-DAG: %v2half = OpTypeVector %half 2
// CHECK-NOT: OpTypeFloat 16 BFloat16KHR
// A plain 8-bit float must not appear.
// CHECK-NOT: OpTypeFloat 8{{$}}

[numthreads(1, 1, 1)]
void main() {
  float16_t h = float16_t(1.5h);
  float8_e4m3_t e4m3 = float8_e4m3_t(float(h));
  float8_e5m2_t e5m2 = float8_e5m2_t(float(h));

  // float8 -> float16_t: one OpFConvert, no detour through float.
  // CHECK: [[a:%[0-9]+]] = OpLoad %fp8e4m3 %e4m3
  // CHECK-NEXT: [[b:%[0-9]+]] = OpFConvert %half [[a]]
  // CHECK-NEXT: OpStore %h1 [[b]]
  float16_t h1 = float16_t(e4m3);
  h1 = float16_t(e4m3);
  // CHECK: [[c:%[0-9]+]] = OpLoad %fp8e5m2 %e5m2
  // CHECK-NEXT: [[d:%[0-9]+]] = OpFConvert %half [[c]]
  // CHECK-NEXT: OpStore %h2 [[d]]
  float16_t h2 = float16_t(e5m2);

  // float16_t -> float8: the narrowing conversion is explicit as well.
  // CHECK: [[e:%[0-9]+]] = OpLoad %half %h
  // CHECK-NEXT: [[g:%[0-9]+]] = OpFConvert %fp8e4m3 [[e]]
  // CHECK-NEXT: OpStore %e4m3
  e4m3 = float8_e4m3_t(h);

  // float16_t vectors keep their own encoding too.
  float16_t2 hv = float16_t2(h1, h2);
  // CHECK: OpLoad %v2half
  // CHECK-NEXT: OpFConvert %v2fp8e4m3
  float8_e4m3_t2 f8v = float8_e4m3_t2(hv);
  float x = float(h1) + float(h2) + float(e4m3) + float(f8v.x);
  float4 o = float4(x, 0, 0, 0);
}
