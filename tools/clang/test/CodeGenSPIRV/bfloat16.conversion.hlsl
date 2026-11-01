// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2018 -fcgl -Vd %s | FileCheck %s

// Explicit numeric conversions involving bfloat16_t use the generic SPIR-V
// conversion instructions: OpFConvert for float-to-float (via binary32) and
// OpConvert{FToS,FToU,SToF,UToF} for conversions to/from integer types.

// CHECK-NOT: OpCapability Float16

[numthreads(1, 1, 1)]
void main() {
  bfloat16_t bf = bfloat16_t(1.5);
  float f = bf;
  // CHECK: [[bf:%[0-9]+]] = OpLoad %bfloat16
  // CHECK-NEXT: OpFConvert %float [[bf]]
  // CHECK-NEXT: OpStore %f
  f = float(bf);

  bfloat16_t bf2 = bfloat16_t(f);
  // CHECK: [[fval:%[0-9]+]] = OpLoad %float %f
  // CHECK-NEXT: OpFConvert %bfloat16 [[fval]]
  // CHECK-NEXT: OpStore %bf2
  bf2 = bfloat16_t(f);

  bfloat16_t2 v = bfloat16_t2(bf, bf2);
  float2 vf = v;
  // CHECK: [[bv:%[0-9]+]] = OpLoad %v2bfloat16 %v
  // CHECK-NEXT: OpFConvert %v2float [[bv]]
  // CHECK-NEXT: OpStore %vf
  vf = float2(v);

  v = bfloat16_t2(vf);
  // CHECK: [[vfval:%[0-9]+]] = OpLoad %v2float %vf
  // CHECK-NEXT: OpFConvert %v2bfloat16 [[vfval]]
  // CHECK-NEXT: OpStore %v
  v = bfloat16_t2(vf);

  int i = int(bf);
  // CHECK: [[bfi:%[0-9]+]] = OpLoad %bfloat16 %bf
  // CHECK-NEXT: OpConvertFToS %int [[bfi]]
  // CHECK-NEXT: OpStore %i
  i = int(bf);

  bf = bfloat16_t(i);
  // CHECK: [[ival:%[0-9]+]] = OpLoad %int %i
  // CHECK: OpSConvert %short [[ival]]
  // CHECK-NEXT: OpConvertSToF %bfloat16
  // CHECK-NEXT: OpStore %bf
  bf = bfloat16_t(i);

  uint u = uint(bf);
  // CHECK: [[bfu:%[0-9]+]] = OpLoad %bfloat16 %bf
  // CHECK-NEXT: OpConvertFToU %uint [[bfu]]
  // CHECK-NEXT: OpStore %u
  u = uint(bf);

  bf = bfloat16_t(u);
  // CHECK: [[uval:%[0-9]+]] = OpLoad %uint %u
  // CHECK: OpUConvert %ushort [[uval]]
  // CHECK-NEXT: OpConvertUToF %bfloat16
  // CHECK-NEXT: OpStore %bf
  bf = bfloat16_t(u);

  // Widening conversion of a whole matrix happens per row.
  bfloat16_t2x2 m;
  m._11 = bf; m._12 = bf2; m._21 = bf; m._22 = bf2;
  float2x2 mf = m;
  // CHECK: [[m:%[0-9]+]] = OpLoad %mat2v2bfloat16 %m
  // CHECK-NEXT: OpCompositeExtract %v2bfloat16 [[m]] 0
  // CHECK-NEXT: OpFConvert %v2float
  // CHECK-NEXT: OpCompositeExtract %v2bfloat16 [[m]] 1
  // CHECK-NEXT: OpFConvert %v2float
  // CHECK-NEXT: OpCompositeConstruct %mat2v2float
  // CHECK-NEXT: OpStore %mf
  mf = float2x2(m);
}
