// RUN: %dxc -T cs_6_2 -E main -spirv -HV 2018 -fcgl -Vd -enable-16bit-types %s | FileCheck %s

// bfloat16_t is a real 16-bit type with the BFloat16KHR encoding independent
// of -enable-16bit-types (see bfloat16.basic.hlsl and bfloat16.buffer.hlsl,
// which run without the option). When both bfloat16_t and float16_t are
// used together, the two 16-bit float types must remain distinct: the
// bfloat16_t usage must request only BFloat16TypeKHR, while Float16 is
// requested for the actual float16_t usage.

// CHECK: OpCapability BFloat16TypeKHR
// CHECK: OpCapability Float16
// CHECK-NOT: OpCapability StorageInputOutput16

// CHECK: %bfloat16 = OpTypeFloat 16 BFloat16KHR
// CHECK: %half = OpTypeFloat 16
// CHECK: %v2bfloat16 = OpTypeVector %bfloat16 2
// CHECK: %v2half = OpTypeVector %half 2

[numthreads(1, 1, 1)]
void main() {
  bfloat16_t bf = bfloat16_t(1.5);
  bfloat16_t2 bfv = bfloat16_t2(bf, bf);
  float16_t h = float16_t(1.5h);
  float16_t2 hv = float16_t2(h, h);

  // Conversions widen through binary32 for both types.
  // CHECK: OpLoad %bfloat16 %bf
  // CHECK: OpFConvert %float
  // CHECK: OpLoad %half %h
  // CHECK: OpFConvert %float
  float a = bf;
  float b = h;

  // Same-width conversions still need OpFConvert because the encodings differ.
  // CHECK: [[bf16bits:%[0-9]+]] = OpLoad %bfloat16 %bf
  // CHECK-NEXT: [[ashalf:%[0-9]+]] = OpFConvert %half [[bf16bits]]
  // CHECK-NEXT: OpStore %hb [[ashalf]]
  float16_t hb = float16_t(bf);
  // CHECK: [[halfbits:%[0-9]+]] = OpLoad %half %h
  // CHECK-NEXT: [[asbfloat:%[0-9]+]] = OpFConvert %bfloat16 [[halfbits]]
  // CHECK-NEXT: OpStore %bfb [[asbfloat]]
  bfloat16_t bfb = bfloat16_t(h);

  float4 o = float4(a + b + float(bfv.x) + float(hv.x) + float(hb) + float(bfb),
                    0, 0, 0);
}
