// RUN: %dxc -T ps_6_4 -E main -enable-16bit-types -fcgl %s -spirv | FileCheck %s

// HLSL Change - SPV_VALVE_mixed_float_dot_product, gate G11/L5 (off-path
// identity).
//
// Without -fspv-extension=SPV_VALVE_mixed_float_dot_product the extension is not
// enabled, so dot2add keeps its previous lowering byte for byte -- the unfused
// OpFMul / OpFConvert / OpCompositeExtract / OpFAdd / OpFAdd sequence, which
// rounds the product to FP16 and then accumulates in FP32 -- and neither the
// DotProductFloat16AccFloat32VALVE capability (6912) nor the extension string
// may appear.
//
// Note on the diagnostic side: because the extension is registered, no
// "unknown SPIR-V extension" error is emitted for
// SPV_VALVE_mixed_float_dot_product any more, and because
// OpFDot2MixAcc32VALVE is only ever built when the extension is enabled there is
// no "extension required but not permitted" diagnostic to catch either. The
// property to gate is therefore the absence asserted here. The shader is
// vk.valve-dot2add.hlsl verbatim, so the two files differ only in the flag.
//
// CHECK:      OpCapability Shader
// CHECK-NOT:  OpCapability DotProductFloat16AccFloat32VALVE
// CHECK-NOT:  OpCapability DotProductFloat16AccFloat16VALVE
// CHECK-NOT:  OpCapability DotProductBFloat16AccVALVE
// CHECK-NOT:  OpCapability DotProductFloat8AccFloat32VALVE
// CHECK-NOT:  OpExtension "SPV_VALVE_mixed_float_dot_product"
// CHECK:      OpMemoryModel Logical GLSL450
// CHECK:      OpEntryPoint Fragment %main "main" %out_var_SV_Target
float main() : SV_Target {
  half2 a = half2(1.0009765625, 2.0);
  half2 b = half2(1.0009765625, 0.5);
  float acc = 0.0;
  // The unfused lowering: multiply in FP16, widen to FP32, add the two lanes,
  // then add the accumulator.
  // CHECK:      [[a:%[0-9]+]] = OpLoad %v2half %a
  // CHECK-NEXT: [[b:%[0-9]+]] = OpLoad %v2half %b
  // CHECK-NEXT: [[acc:%[0-9]+]] = OpLoad %float %acc
  // CHECK-NEXT: [[mul:%[0-9]+]] = OpFMul %v2half [[a]] [[b]]
  // CHECK-NEXT: [[conv:%[0-9]+]] = OpFConvert %v2float [[mul]]
  // CHECK-NEXT: [[e0:%[0-9]+]] = OpCompositeExtract %float [[conv]] 0
  // CHECK-NEXT: [[e1:%[0-9]+]] = OpCompositeExtract %float [[conv]] 1
  // CHECK-NEXT: [[dot:%[0-9]+]] = OpFAdd %float [[e0]] [[e1]]
  // CHECK-NEXT: [[r0:%[0-9]+]] = OpFAdd %float [[dot]] [[acc]]
  // CHECK-NOT:  OpFDot2MixAcc32VALVE
  // CHECK-NEXT: OpStore %r0 [[r0]]
  float r0 = dot2add(a, b, acc);

  half4 c = half4(1.0, 2.0, 3.0, 4.0);
  half4 d = half4(5.0, 6.0, 7.0, 8.0);
  int acc2 = 7;
  // CHECK:      [[c:%[0-9]+]] = OpLoad %v4half %c
  // CHECK-NEXT: [[cx:%[0-9]+]] = OpVectorShuffle %v2half [[c]] [[c]] 0 1
  // CHECK:      [[d:%[0-9]+]] = OpLoad %v4half %d
  // CHECK-NEXT: [[dy:%[0-9]+]] = OpVectorShuffle %v2half [[d]] [[d]] 2 3
  // CHECK:      [[acc2:%[0-9]+]] = OpLoad %int %acc2
  // CHECK-NEXT: [[acc2f:%[0-9]+]] = OpConvertSToF %float [[acc2]]
  // CHECK-NEXT: [[mul2:%[0-9]+]] = OpFMul %v2half [[cx]] [[dy]]
  // CHECK-NEXT: [[conv2:%[0-9]+]] = OpFConvert %v2float [[mul2]]
  // CHECK-NEXT: [[f0:%[0-9]+]] = OpCompositeExtract %float [[conv2]] 0
  // CHECK-NEXT: [[f1:%[0-9]+]] = OpCompositeExtract %float [[conv2]] 1
  // CHECK-NEXT: [[dot2:%[0-9]+]] = OpFAdd %float [[f0]] [[f1]]
  // CHECK-NEXT: [[r1:%[0-9]+]] = OpFAdd %float [[dot2]] [[acc2f]]
  // CHECK-NOT:  OpFDot2MixAcc32VALVE
  // CHECK-NEXT: OpStore %r1 [[r1]]
  float r1 = dot2add(c.xy, d.zw, acc2);

  return r0 + r1;
}
