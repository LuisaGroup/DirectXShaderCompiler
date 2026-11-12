// RUN: %dxc -T ps_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.3 -fspv-extension=SPV_QCOM_image_processing3 %s | FileCheck %s

// SPV_QCOM_image_processing3, diamond (GatherDQCOM) mode (G28/L0, G28/L2 d).
//
// GatherDQCOM samples the four texels at the cardinal offsets around the
// coordinate, which with a point sample of the centre texel is the 5-tap kernel of
// contrast adaptive sharpening. It is one of the three extended modes, so it
// requires ImageGatherExtendedModesQCOM (4544) and must not declare
// ImageGatherLinearQCOM (4543), which only covers Gather4x1QCOM:
//
//   Gather4x1QCOM (0)                   -> ImageGatherLinearQCOM
//   GatherDQCOM (1), GatherH2QCOM (2),
//   GatherV2QCOM (3)                    -> ImageGatherExtendedModesQCOM
//
// The two capabilities are selected from the Mode operand of the instruction, per
// call shape, so a lowering that always emitted the first mode - or always the
// first capability - cannot pass this file and qcom.image-processing3.hlsl.
//
// Two files per mode exist because a single file with four calls would still pass
// if the mode were hard-coded; the mode literal is what each of them asserts.
// L3 is implicit: this file compiling means SPIRV-Tools accepted the module, which
// includes "Mode GatherModesGatherDQCOM (== 1) requires capability
// ImageGatherExtendedModesQCOM" for this mode.
#include <vk/qcom/image_processing3.h>

vk::SampledTexture2D<float4> Tex : register(t0);

float4 main(float2 uv : TEXCOORD0) : SV_Target {
  return vk::qcom::ImageGatherD(Tex, uv);
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
// CHECK-DAG: [[INT1:%[0-9A-Za-z_]+]] = OpConstant [[INT]] 1
// L2: (IdResultType, IdResult, Sampled Image, Coordinate, Component, Mode) with
// component 0 (the default) and mode 1 (GatherDQCOM). The two trailing operands
// differ here, so a swapped component/mode cannot pass this line and the ones in
// qcom.image-processing3.hlsl and qcom.image-processing3.v2.hlsl.
// CHECK: [[IMG:%[0-9A-Za-z_]+]] = OpLoad %type_sampled_image %Tex
// CHECK-NEXT: [[COORD:%[0-9A-Za-z_]+]] = OpLoad %v2float %uv
// CHECK-NEXT: OpImageGatherQCOM %v4float [[IMG]] [[COORD]] [[INT0]] [[INT1]]
