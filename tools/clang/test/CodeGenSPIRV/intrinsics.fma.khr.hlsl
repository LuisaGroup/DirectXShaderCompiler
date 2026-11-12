// RUN: %dxc -T ps_6_0 -E main -fcgl -fspv-extension=SPV_KHR_fma %s -spirv | FileCheck %s

// With SPV_KHR_fma enabled, a fused multiply-add on 32-bit float is emitted as
// the OpFmaKHR core instruction (capability FMAKHR) instead of the GLSL.std.450
// Fma extended instruction.
//
// mad() is the HLSL spelling that accepts 'float': HLSL fma() is a 'double'-only
// intrinsic (it maps to dx.op.fma, which takes doubles), and DXC only uses
// OpFmaKHR for 32-bit float, so the 'double' form of both intrinsics keeps the
// extended instruction (see intrinsics.fma.khr.width.hlsl). Without
// -fspv-extension=SPV_KHR_fma nothing changes at all, not even the extension
// string (see intrinsics.fma.off.hlsl).

// L1: exactly one OpCapability FMAKHR and exactly one OpExtension "SPV_KHR_fma".
// CHECK: OpCapability Shader
// CHECK: OpCapability FMAKHR
// CHECK-NOT: OpCapability FMAKHR
// CHECK: OpExtension "SPV_KHR_fma"
// CHECK-NOT: OpExtension "SPV_KHR_fma"
// CHECK: OpMemoryModel Logical GLSL450
// CHECK: %float = OpTypeFloat 32

float4 main() : SV_Target {
  float a, b, c, result;
  // L2: opcode, result type and operand order. The three operands are three
  // separate OpLoads captured in source order, so a swapped operand fails.
  // CHECK: [[a:%[0-9]+]] = OpLoad %float %a
  // CHECK-NEXT: [[b:%[0-9]+]] = OpLoad %float %b
  // CHECK-NEXT: [[c:%[0-9]+]] = OpLoad %float %c
  // CHECK-NEXT: [[fma:%[0-9]+]] = OpFmaKHR %float [[a]] [[b]] [[c]]
  // CHECK-NEXT: OpStore %result [[fma]]
  result = mad(a, b, c);
  return result;
}
