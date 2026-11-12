// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.3 -fspv-extension=SPV_QCOM_image_processing3 %s | FileCheck %s --check-prefix=OFF
// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.3 %s | FileCheck %s --check-prefix=OFF

// SPV_QCOM_image_processing3 off path (G28/L5).
//
// The shader includes <vk/qcom/image_processing3.h> and gathers with an ordinary
// Texture2D, i.e. it never calls one of the header's entry points. Nothing of the
// feature may appear in the module: no ImageGatherLinearQCOM, no
// ImageGatherExtendedModesQCOM, no OpExtension "SPV_QCOM_image_processing3", no
// OpImageGatherQCOM - and the pre-existing gather must keep its exact encoding
// (OpImageGather, not OpImageGatherQCOM).
//
// The first RUN line is the interesting one: the extension is enabled and still
// must not be declared, because a module that declares an extension it does not
// use invites a driver to reject it for nothing (and the capability trimming pass
// would have to remove it again). The second RUN line is the default mode, where
// the extension is not enabled at all. Neither run needs the flag, so the header
// itself must not require it: it is a set of declarations with no definition and
// no attribute that writes a capability or an extension string.
#include <vk/qcom/image_processing3.h>

Texture2D<float4> Tex : register(t0);
SamplerState Samp : register(s0);
RWStructuredBuffer<float4> Out : register(u0);

[numThreads(1, 1, 1)]
void main() {
  float2 uv = float2(0.5, 0.5);
  // The ordinary 2x2 gather and its per-channel spellings are untouched.
  Out[0] = Tex.Gather(Samp, uv);
  Out[1] = Tex.GatherGreen(Samp, uv, int2(1, 1));
}

// OFF: OpCapability Shader
// OFF-NOT: OpCapability ImageGatherLinearQCOM
// OFF-NOT: OpCapability ImageGatherExtendedModesQCOM
// OFF: OpMemoryModel Logical GLSL450
// OFF-NOT: OpExtension "SPV_QCOM_image_processing3"
// OFF: OpEntryPoint GLCompute
// The pre-existing gather keeps its opcode, its result type and its component
// operand: Gather is component 0, GatherGreen is component 1.
// OFF: [[IMG:%[0-9A-Za-z_]+]] = OpLoad %type_2d_image %Tex
// OFF: [[SAMP:%[0-9A-Za-z_]+]] = OpLoad %type_sampler %Samp
// OFF: [[SI:%[0-9A-Za-z_]+]] = OpSampledImage %type_sampled_image [[IMG]] [[SAMP]]
// OFF: OpImageGather %v4float [[SI]] {{%[A-Za-z0-9_]+}} %int_0
// OFF-NOT: OpImageGatherQCOM
// OFF: [[SI2:%[0-9A-Za-z_]+]] = OpSampledImage %type_sampled_image {{%[A-Za-z0-9_]+}} {{%[A-Za-z0-9_]+}}
// OFF: OpImageGather %v4float [[SI2]] {{%[A-Za-z0-9_]+}} %int_1 ConstOffset {{%[A-Za-z0-9_]+}}
// OFF-NOT: OpImageGatherQCOM
// OFF: OpFunctionEnd
