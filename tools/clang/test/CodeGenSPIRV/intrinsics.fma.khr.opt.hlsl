// RUN: %dxc -T ps_6_0 -E main -fspv-extension=SPV_KHR_fma %s -spirv | FileCheck %s

// L6: optimizer survival. This test deliberately omits -fcgl, so legalization,
// spirv-opt and the capability trimming pass all run over the module (and it is
// validated afterwards). OpFmaKHR, its FMAKHR capability and the SPV_KHR_fma
// extension have to survive that, and the instruction must not be turned back
// into the GLSL.std.450 Fma extended instruction.
//
// The inputs come from stage inputs so that nothing folds away, and no -Od/-O3
// flag is passed: this is the default optimization level of the compiler.

// CHECK: OpCapability Shader
// CHECK: OpCapability FMAKHR
// CHECK-NOT: OpCapability FMAKHR
// CHECK: OpExtension "SPV_KHR_fma"
// CHECK-NOT: OpExtension "SPV_KHR_fma"
// CHECK: OpMemoryModel Logical GLSL450

// CHECK: %v4float = OpTypeVector %float 4

float4 main(float4 a : A, float4 b : B, float4 c : C) : SV_Target {
  // CHECK: [[fma:%[0-9]+]] = OpFmaKHR %v4float
  // CHECK-NOT: OpExtInst %v4float {{%[0-9]+}} Fma
  // CHECK: OpStore %out_var_SV_Target [[fma]]
  return mad(a, b, c);
}
