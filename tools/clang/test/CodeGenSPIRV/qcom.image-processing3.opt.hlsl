// RUN: %dxc -T cs_6_0 -E main -spirv -fspv-target-env=vulkan1.3 -fspv-extension=SPV_QCOM_image_processing3 %s | FileCheck %s

// SPV_QCOM_image_processing3 after legalization and optimization (G28/L6).
//
// Without -fcgl the module goes through legalization, spirv-opt and the capability
// trimming pass. Two things can go wrong only here: an optimization drops or
// rewrites the gather (few passes know the opcode), or the trimming pass removes
// ImageGatherLinearQCOM / ImageGatherExtendedModesQCOM from a module that still
// uses it, which the validator would then reject - so this file compiling at all
// is also the validity gate without -Vd.
//
// All four modes are used, so both capabilities have to survive, and the four
// component/mode pairs differ so that a pass that folded two calls together (or
// remapped the constants) cannot pass the four CHECK lines below.
#include <vk/qcom/image_processing3.h>

vk::SampledTexture2D<float4> Tex : register(t0);
RWStructuredBuffer<float4> Out : register(u0);

[numThreads(1, 1, 1)]
void main() {
  float2 uv = float2(0.5, 0.5);
  // One call per mode, each with a different component.
  Out[0] = vk::qcom::ImageGather4x1<0>(Tex, uv); // linear  (0)
  Out[1] = vk::qcom::ImageGatherD<1>(Tex, uv);   // diamond (1)
  Out[2] = vk::qcom::ImageGatherH2<3>(Tex, uv);  // two rows (2)
  Out[3] = vk::qcom::ImageGatherV2<2>(Tex, uv);  // two columns (3)
}

// Both capabilities and the extension survive legalization, spirv-opt and the
// capability trimming pass.
// CHECK: OpCapability ImageGatherLinearQCOM
// CHECK: OpCapability ImageGatherExtendedModesQCOM
// CHECK: OpExtension "SPV_QCOM_image_processing3"
// The instruction still takes its component and mode from 32-bit integer
// constants.
// CHECK-DAG: [[INT:%[0-9A-Za-z_]+]] = OpTypeInt 32 1
// CHECK-DAG: [[INT0:%[0-9A-Za-z_]+]] = OpConstant [[INT]] 0
// CHECK-DAG: [[INT1:%[0-9A-Za-z_]+]] = OpConstant [[INT]] 1
// CHECK-DAG: [[INT2:%[0-9A-Za-z_]+]] = OpConstant [[INT]] 2
// CHECK-DAG: [[INT3:%[0-9A-Za-z_]+]] = OpConstant [[INT]] 3
// CHECK: [[TEX:%[0-9A-Za-z_]+]] = OpVariable %_ptr_UniformConstant_type_sampled_image UniformConstant
// Only the entry point is left: nothing of the header survives as a function.
// CHECK: %main = OpFunction
// CHECK-NOT: = OpFunction
// The four gathers, still in source order, each reading the one image object of
// the entry point with its own component and mode.
// CHECK: [[IMG0:%[0-9A-Za-z_]+]] = OpLoad %type_sampled_image [[TEX]]
// CHECK-NEXT: OpImageGatherQCOM %v4float [[IMG0]] {{%[A-Za-z0-9_]+}} [[INT0]] [[INT0]]
// CHECK: [[IMG1:%[0-9A-Za-z_]+]] = OpLoad %type_sampled_image [[TEX]]
// CHECK-NEXT: OpImageGatherQCOM %v4float [[IMG1]] {{%[A-Za-z0-9_]+}} [[INT1]] [[INT1]]
// CHECK: [[IMG2:%[0-9A-Za-z_]+]] = OpLoad %type_sampled_image [[TEX]]
// CHECK-NEXT: OpImageGatherQCOM %v4float [[IMG2]] {{%[A-Za-z0-9_]+}} [[INT3]] [[INT2]]
// CHECK: [[IMG3:%[0-9A-Za-z_]+]] = OpLoad %type_sampled_image [[TEX]]
// CHECK-NEXT: OpImageGatherQCOM %v4float [[IMG3]] {{%[A-Za-z0-9_]+}} [[INT2]] [[INT3]]
// The region between the fourth gather and the end of the entry point holds no
// further gather: the four calls above are the whole module.
// CHECK-NOT: OpImageGatherQCOM
// CHECK: OpFunctionEnd
