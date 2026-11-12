// RUN: %dxc -T ps_6_0 -E main -fcgl %s -spirv | FileCheck %s

// L5: off-path identity. Without -fspv-extension=SPV_KHR_fma, the extension is
// not enabled, so no OpFmaKHR may be emitted, the FMAKHR capability and the
// SPV_KHR_fma extension string must stay absent, and the fused multiply-add
// keeps its previous lowering: the GLSL.std.450 Fma extended instruction with a
// NoContraction decoration for 32-bit float, and the same extended instruction
// for 'double' (the only form HLSL fma() accepts).
//
// Note on the diagnostic side: because the extension is registered, no
// "unknown SPIR-V extension" error is emitted for SPV_KHR_fma any more; and
// because OpFmaKHR is only ever built when the extension is enabled, there is
// no "extension required but not permitted" diagnostic to catch either. The
// property to gate is therefore the absence asserted here.

// CHECK: OpCapability Shader
// CHECK-NOT: OpCapability FMAKHR
// CHECK-NOT: OpExtension "SPV_KHR_fma"
// CHECK: [[glsl:%[0-9]+]] = OpExtInstImport "GLSL.std.450"
// CHECK: OpMemoryModel Logical GLSL450

float4 main() : SV_Target {
  float a, b, c;
  double d1, d2, d3;
  // CHECK: OpDecorate [[fma:%[0-9]+]] NoContraction

  // CHECK: [[a:%[0-9]+]] = OpLoad %float %a
  // CHECK-NEXT: [[b:%[0-9]+]] = OpLoad %float %b
  // CHECK-NEXT: [[c:%[0-9]+]] = OpLoad %float %c
  // CHECK-NOT: OpFmaKHR
  // CHECK-NEXT: [[fma]] = OpExtInst %float [[glsl]] Fma [[a]] [[b]] [[c]]
  float rf = mad(a, b, c);

  // CHECK: [[d1:%[0-9]+]] = OpLoad %double %d1
  // CHECK-NEXT: [[d2:%[0-9]+]] = OpLoad %double %d2
  // CHECK-NEXT: [[d3:%[0-9]+]] = OpLoad %double %d3
  // CHECK-NOT: OpFmaKHR
  // CHECK-NEXT: {{%[0-9]+}} = OpExtInst %double [[glsl]] Fma [[d1]] [[d2]] [[d3]]
  double rd = fma(d1, d2, d3);

  return float4(rf, rd, 0, 0);
}
