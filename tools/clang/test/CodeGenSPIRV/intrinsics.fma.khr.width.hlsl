// RUN: %dxc -T ps_6_2 -E main -fcgl -enable-16bit-types -fspv-extension=SPV_KHR_fma %s -spirv | FileCheck %s

// L4: the width restriction of this retargeting. OpFmaKHR is only used for
// 32-bit float (Vulkan gates it per width through shaderFmaFloat16/32/64), so a
// fused multiply-add on 'half', 'min16float' and 'double' keeps the GLSL.std.450
// Fma extended instruction even when SPV_KHR_fma is enabled. Since no 32-bit
// float call site exists in this module, neither the FMAKHR capability nor the
// SPV_KHR_fma extension is emitted either - and a module that did emit OpFmaKHR
// without the FMAKHR capability would be rejected by the validator, which runs
// for every compile here.
//
// -enable-16bit-types is required so that 'half' is realized as a 16-bit float
// instead of a 32-bit one; it makes the "%half" result type asserted below mean
// what it says. ('min16float' promotes to 'half' in that mode, hence the
// -Wconversion warnings; the promoted type is what the module encodes, which is
// the %v2half case below.)

// CHECK: OpCapability Shader
// CHECK-NOT: OpCapability FMAKHR
// CHECK-NOT: OpExtension "SPV_KHR_fma"
// CHECK: [[glsl:%[0-9]+]] = OpExtInstImport "GLSL.std.450"
// CHECK: OpMemoryModel Logical GLSL450

// CHECK: %float = OpTypeFloat 32
// CHECK: %half = OpTypeFloat 16
// CHECK: %double = OpTypeFloat 64

half hMad(half a, half b, half c) { return mad(a, b, c); }
min16float2 m2Mad(min16float2 a, min16float2 b, min16float2 c) { return mad(a, b, c); }
double dMad(double a, double b, double c) { return mad(a, b, c); }
double4 d4Fma(double4 a, double4 b, double4 c) { return fma(a, b, c); }

float4 main() : SV_Target {
  half a, b, c;
  min16float2 a2, b2, c2;
  double d1, d2, d3;
  double4 e1, e2, e3;
  return float4(hMad(a, b, c), m2Mad(a2, b2, c2).x, dMad(d1, d2, d3),
                d4Fma(e1, e2, e3).x);
}

// 'half' must not be retargeted to OpFmaKHR.
// CHECK: %hMad = OpFunction %half None
// CHECK: [[hA:%[0-9]+]] = OpLoad %half
// CHECK-NEXT: [[hB:%[0-9]+]] = OpLoad %half
// CHECK-NEXT: [[hC:%[0-9]+]] = OpLoad %half
// CHECK-NOT: OpFmaKHR
// CHECK-NEXT: [[hR:%[0-9]+]] = OpExtInst %half [[glsl]] Fma [[hA]] [[hB]] [[hC]]

// 'min16float2' must not be retargeted to OpFmaKHR either.
// CHECK: %m2Mad = OpFunction %v2half None
// CHECK: [[mA:%[0-9]+]] = OpLoad %v2half
// CHECK-NEXT: [[mB:%[0-9]+]] = OpLoad %v2half
// CHECK-NEXT: [[mC:%[0-9]+]] = OpLoad %v2half
// CHECK-NOT: OpFmaKHR
// CHECK-NEXT: [[mR:%[0-9]+]] = OpExtInst %v2half [[glsl]] Fma [[mA]] [[mB]] [[mC]]

// 'double' must not be retargeted to OpFmaKHR, for mad() ...
// CHECK: %dMad = OpFunction %double None
// CHECK: [[dA:%[0-9]+]] = OpLoad %double
// CHECK-NEXT: [[dB:%[0-9]+]] = OpLoad %double
// CHECK-NEXT: [[dC:%[0-9]+]] = OpLoad %double
// CHECK-NOT: OpFmaKHR
// CHECK-NEXT: [[dR:%[0-9]+]] = OpExtInst %double [[glsl]] Fma [[dA]] [[dB]] [[dC]]

// ... and for fma() on double4, which is the only form HLSL fma() has.
// CHECK: %d4Fma = OpFunction %v4double None
// CHECK: [[eA:%[0-9]+]] = OpLoad %v4double
// CHECK-NEXT: [[eB:%[0-9]+]] = OpLoad %v4double
// CHECK-NEXT: [[eC:%[0-9]+]] = OpLoad %v4double
// CHECK-NOT: OpFmaKHR
// CHECK-NEXT: [[eR:%[0-9]+]] = OpExtInst %v4double [[glsl]] Fma [[eA]] [[eB]] [[eC]]
// CHECK-NOT: OpFmaKHR
// CHECK: OpFunctionEnd
