// RUN: %dxc -T ps_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.3 -fspv-extension=SPV_QCOM_image_processing3 %s | FileCheck %s

// SPV_QCOM_image_processing3, two-column (GatherV2QCOM) mode
// (G28/L0, G28/L2 v2).
//
// GatherV2QCOM samples two 1x2 pairs, one column left and one column right of the
// coordinate - the vertical analogue of GatherH2QCOM, and the other half of the
// 12-tap separable upscaling filter. It is one of the three extended modes, so it
// requires ImageGatherExtendedModesQCOM (4544):
//
//   Gather4x1QCOM (0)                   -> ImageGatherLinearQCOM
//   GatherDQCOM (1), GatherH2QCOM (2),
//   GatherV2QCOM (3)                    -> ImageGatherExtendedModesQCOM
//
// L3 is implicit: this file compiling means SPIRV-Tools accepted the module, which
// includes "Mode GatherModesGatherV2QCOM (== 3) requires capability
// ImageGatherExtendedModesQCOM".
#include <vk/qcom/image_processing3.h>

vk::SampledTexture2D<float4> Tex : register(t0);

float4 main(float2 uv : TEXCOORD0) : SV_Target {
  return vk::qcom::ImageGatherV2(Tex, uv);
}

// L1: the extended-modes capability, the extension, and not the linear one.
// CHECK: OpCapability Shader
// CHECK-NOT: OpCapability ImageGatherLinearQCOM
// CHECK: OpCapability ImageGatherExtendedModesQCOM
// CHECK: OpExtension "SPV_QCOM_image_processing3"
// CHECK-NOT: OpExtension "SPV_QCOM_image_processing3"
// CHECK: OpMemoryModel Logical GLSL450
// L2: the constants, captured once.
// CHECK-DAG: [[INT:%[0-9A-Za-z_]+]] = OpTypeInt 32 1
// CHECK-DAG: [[INT0:%[0-9A-Za-z_]+]] = OpConstant [[INT]] 0
// CHECK-DAG: [[INT3:%[0-9A-Za-z_]+]] = OpConstant [[INT]] 3
// L2: (IdResultType, IdResult, Sampled Image, Coordinate, Component, Mode) with
// component 0 (the default) and mode 3 (GatherV2QCOM).
// CHECK: [[IMG:%[0-9A-Za-z_]+]] = OpLoad %type_sampled_image %Tex
// CHECK-NEXT: [[COORD:%[0-9A-Za-z_]+]] = OpLoad %v2float %uv
// CHECK-NEXT: OpImageGatherQCOM %v4float [[IMG]] [[COORD]] [[INT0]] [[INT3]]
