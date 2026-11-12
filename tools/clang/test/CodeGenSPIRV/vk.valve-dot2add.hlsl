// RUN: %dxc -T ps_6_4 -E main -enable-16bit-types -fcgl -fspv-extension=SPV_VALVE_mixed_float_dot_product %s -spirv | FileCheck %s

// HLSL Change - SPV_VALVE_mixed_float_dot_product, gates G11/L1 + G11/L2.
//
// With -fspv-extension=SPV_VALVE_mixed_float_dot_product,
//     float dot2add( half2 a, half2 b, float acc );
// is emitted as the fused OpFDot2MixAcc32VALVE (6916) instead of the unfused
// OpFMul / OpFConvert / OpCompositeExtract / OpFAdd / OpFAdd sequence, and the
// module declares the DotProductFloat16AccFloat32VALVE capability (6912) and
// the extension string. The capability is per (input precision, accumulator
// precision) pair, so it is the FP16-input / FP32-accumulator one here.
// Without the flag nothing changes; see vk.valve-dot2add.off.hlsl.
//
// The extension is vendor-specific (VALVE): only drivers that advertise
// VK_VALVE_shader_mixed_float_dot_product accept the module, which is why the
// extension is opt-in rather than on by default.
//
// The first call site uses inputs for which "round once" and "round twice"
// differ, so a reviewer can check the numeric difference by hand even though
// FileCheck can only assert the encoding. With
//     a = b = (1 + 2^-10, ...), acc = 0
// the unfused path first rounds the product to FP16 and then adds in FP32:
//     fl16((1 + 2^-10)^2) = 1 + 2^-9, dot = 2 + 2^-9 = 2.001953125
// while the fused path keeps the product exact and rounds once:
//     (1 + 2^-10)^2 + 1 = 2 + 2^-9 + 2^-20 = 2.00195407867431640625
// i.e. the assertion below is "one instruction, therefore one rounding".
//
// L1: exactly one OpCapability DotProductFloat16AccFloat32VALVE and exactly one
// OpExtension "SPV_VALVE_mixed_float_dot_product".
// CHECK:      OpCapability Shader
// CHECK:      OpCapability Float16
// CHECK:      OpCapability DotProductFloat16AccFloat32VALVE
// CHECK-NOT:  OpCapability DotProductFloat16AccFloat32VALVE
// CHECK:      OpExtension "SPV_VALVE_mixed_float_dot_product"
// CHECK-NOT:  OpExtension "SPV_VALVE_mixed_float_dot_product"
// CHECK:      OpMemoryModel Logical GLSL450
// CHECK:      OpEntryPoint Fragment %main "main" %out_var_SV_Target
float main() : SV_Target {
  half2 a = half2(1.0009765625, 2.0);
  half2 b = half2(1.0009765625, 0.5);
  float acc = 0.0;
  // L2: opcode, result type and operand order. The three operands are three
  // separate OpLoads captured in source order, so a swapped operand fails.
  // CHECK:      [[a:%[0-9]+]] = OpLoad %v2half %a
  // CHECK-NEXT: [[b:%[0-9]+]] = OpLoad %v2half %b
  // CHECK-NEXT: [[acc:%[0-9]+]] = OpLoad %float %acc
  // CHECK-NOT:  OpFMul %v2half
  // CHECK-NOT:  OpFConvert %v2float
  // CHECK-NEXT: [[r0:%[0-9]+]] = OpFDot2MixAcc32VALVE %float [[a]] [[b]] [[acc]]
  // CHECK-NEXT: OpStore %r0 [[r0]]
  float r0 = dot2add(a, b, acc);

  half4 c = half4(1.0, 2.0, 3.0, 4.0);
  half4 d = half4(5.0, 6.0, 7.0, 8.0);
  int acc2 = 7;
  // L2, second call shape: the accumulator is converted to float and is still
  // the third operand.
  // CHECK:      [[c:%[0-9]+]] = OpLoad %v4half %c
  // CHECK-NEXT: [[cx:%[0-9]+]] = OpVectorShuffle %v2half [[c]] [[c]] 0 1
  // CHECK:      [[d:%[0-9]+]] = OpLoad %v4half %d
  // CHECK-NEXT: [[dy:%[0-9]+]] = OpVectorShuffle %v2half [[d]] [[d]] 2 3
  // CHECK:      [[acc2:%[0-9]+]] = OpLoad %int %acc2
  // CHECK-NEXT: [[acc2f:%[0-9]+]] = OpConvertSToF %float [[acc2]]
  // CHECK-NEXT: [[r1:%[0-9]+]] = OpFDot2MixAcc32VALVE %float [[cx]] [[dy]] [[acc2f]]
  // CHECK-NEXT: OpStore %r1 [[r1]]
  float r1 = dot2add(c.xy, d.zw, acc2);

  return r0 + r1;
}
