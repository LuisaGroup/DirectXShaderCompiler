// RUN: %dxc -T ps_6_0 -E main -fcgl -fspv-extension=SPV_KHR_fma %s -spirv | FileCheck %s

// L1 + L2 for the vector forms of a 32-bit float fused multiply-add: one
// OpFmaKHR per call, with the vector result type of the call, and no
// per-component expansion into scalar OpFmaKHR instructions.
// See intrinsics.fma.khr.hlsl for why the HLSL spelling here is mad().

// CHECK: OpCapability FMAKHR
// CHECK: OpExtension "SPV_KHR_fma"
// CHECK: OpMemoryModel Logical GLSL450

float4 main() : SV_Target {
  float2 a2, b2, c2;
  float3 a3, b3, c3;
  float4 a4, b4, c4;
  float2 r2 = mad(a2, b2, c2);
  float3 r3 = mad(a3, b3, c3);
  float4 r4 = mad(a4, b4, c4);

  // CHECK: [[a2:%[0-9]+]] = OpLoad %v2float %a2
  // CHECK-NEXT: [[b2:%[0-9]+]] = OpLoad %v2float %b2
  // CHECK-NEXT: [[c2:%[0-9]+]] = OpLoad %v2float %c2
  // CHECK-NEXT: [[fma2:%[0-9]+]] = OpFmaKHR %v2float [[a2]] [[b2]] [[c2]]
  // CHECK-NEXT: OpStore %r2 [[fma2]]

  // CHECK: [[a3:%[0-9]+]] = OpLoad %v3float %a3
  // CHECK-NEXT: [[b3:%[0-9]+]] = OpLoad %v3float %b3
  // CHECK-NEXT: [[c3:%[0-9]+]] = OpLoad %v3float %c3
  // CHECK-NEXT: [[fma3:%[0-9]+]] = OpFmaKHR %v3float [[a3]] [[b3]] [[c3]]
  // CHECK-NEXT: OpStore %r3 [[fma3]]

  // CHECK: [[a4:%[0-9]+]] = OpLoad %v4float %a4
  // CHECK-NEXT: [[b4:%[0-9]+]] = OpLoad %v4float %b4
  // CHECK-NEXT: [[c4:%[0-9]+]] = OpLoad %v4float %c4
  // CHECK-NOT: OpFmaKHR %float
  // CHECK-NEXT: [[fma4:%[0-9]+]] = OpFmaKHR %v4float [[a4]] [[b4]] [[c4]]
  // CHECK-NEXT: OpStore %r4 [[fma4]]

  return r4 + float4(r2.x + r2.y, r3.x + r3.y + r3.z, 0, 0);
}
