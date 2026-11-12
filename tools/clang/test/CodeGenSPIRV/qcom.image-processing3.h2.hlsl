// RUN: %dxc -T ps_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.3 -fspv-extension=SPV_QCOM_image_processing3 %s | FileCheck %s

// SPV_QCOM_image_processing3, two-row (GatherH2QCOM) mode (G28/L0, G28/L2 h2).
//
// GatherH2QCOM samples two 2x1 pairs, one row above and one row below the
// coordinate. With GatherV2QCOM (two 1x2 pairs) and an ordinary 2x2 gather it
// builds the 12 taps of a separable upscaling filter. It is one of the three
// extended modes, so it requires ImageGatherExtendedModesQCOM (4544):
//
//   Gather4x1QCOM (0)                   -> ImageGatherLinearQCOM
//   GatherDQCOM (1), GatherH2QCOM (2),
//   GatherV2QCOM (3)                    -> ImageGatherExtendedModesQCOM
//
// This file also exercises the component template argument: component 3 is the
// fourth channel, so a lowering that dropped the component - or that passed the
// template argument as an extra operand - cannot produce the instruction below.
//
// L3 is implicit: this file compiling means SPIRV-Tools accepted the module, which
// includes "Mode GatherModesGatherH2QCOM (== 2) requires capability
// ImageGatherExtendedModesQCOM".
#include <vk/qcom/image_processing3.h>

vk::SampledTexture2D<float4> Tex : register(t0);

float4 main(float2 uv : TEXCOORD0) : SV_Target {
  // component 3 (w/alpha), mode 2 (GatherH2QCOM)
  return vk::qcom::ImageGatherH2<3>(Tex, uv);
}

// L1: the extended-modes capability, the extension, and not the linear one.
// CHECK: OpCapability Shader
// CHECK-NOT: OpCapability ImageGatherLinearQCOM
// CHECK: OpCapability ImageGatherExtendedModesQCOM
// CHECK: OpExtension "SPV_QCOM_image_processing3"
// CHECK-NOT: OpExtension "SPV_QCOM_image_processing3"
// CHECK: OpMemoryModel Logical GLSL450
// L2: the constants, captured once. Component 3 and mode 2 are the only ones the
// instruction may name.
// CHECK-DAG: [[INT:%[0-9A-Za-z_]+]] = OpTypeInt 32 1
// CHECK-DAG: [[INT2:%[0-9A-Za-z_]+]] = OpConstant [[INT]] 2
// CHECK-DAG: [[INT3:%[0-9A-Za-z_]+]] = OpConstant [[INT]] 3
// L2: (IdResultType, IdResult, Sampled Image, Coordinate, Component, Mode) with
// component 3 and mode 2.
// CHECK: [[IMG:%[0-9A-Za-z_]+]] = OpLoad %type_sampled_image %Tex
// CHECK-NEXT: [[COORD:%[0-9A-Za-z_]+]] = OpLoad %v2float %uv
// CHECK-NEXT: OpImageGatherQCOM %v4float [[IMG]] [[COORD]] [[INT3]] [[INT2]]
