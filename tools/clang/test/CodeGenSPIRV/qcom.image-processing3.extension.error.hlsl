// RUN: not %dxc -T ps_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.3 %s 2>&1 | FileCheck %s
// RUN: not %dxc -T ps_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.3 -fspv-extension=SPV_KHR_fma %s 2>&1 | FileCheck %s

// SPV_QCOM_image_processing3 is opt-in (G28/L4).
//
// FeatureManager::enabledByDefault returns false for it, so a shader that gathers
// with one of the header's entry points has to ask for the extension. The two RUN
// lines cover both ways of not asking:
//
// * the default mode, where every extension that is not opt-in is allowed and
//   this one is not (first RUN line);
// * an explicit allow-list that names another extension but not this one (second
//   RUN line). This is the half that proves the restriction is not bypassable: the
//   entry points must not smuggle the extension into the module through
//   [[vk::ext_extension]], which writes the OpExtension string without consulting
//   FeatureManager and would therefore pass both runs below.
//
// The diagnostic comes from the CapabilityVisitor, i.e. from the instruction the
// shader would have emitted, and points at the call. Refusing at compile time is
// the useful error: the capability the mode declares is what makes the opcode
// legal, and a module that declared ImageGatherLinearQCOM or
// ImageGatherExtendedModesQCOM without OpExtension "SPV_QCOM_image_processing3"
// would be rejected by SPIRV-Tools ("Capability ... is not allowed by Vulkan
// specification (or requires extension)") and by any driver without
// VK_QCOM_image_processing3.
#include <vk/qcom/image_processing3.h>

vk::SampledTexture2D<float4> Tex : register(t0);
vk::SampledTexture2DArray<float4> TexArray : register(t1);

float4 main(float2 uv : TEXCOORD0) : SV_Target {
  // CHECK: error: SPIR-V extension 'SPV_QCOM_image_processing3' required for OpImageGatherQCOM but not permitted to use
  float4 a = vk::qcom::ImageGatherH2(Tex, uv);
  // CHECK: error: SPIR-V extension 'SPV_QCOM_image_processing3' required for OpImageGatherQCOM but not permitted to use
  float4 b = vk::qcom::ImageGather4x1Array(TexArray, float3(uv, 0.0));
  return a + b;
}
