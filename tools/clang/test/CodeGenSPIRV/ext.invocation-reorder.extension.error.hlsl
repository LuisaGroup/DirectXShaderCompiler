// RUN: not %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 %s 2>&1 | FileCheck %s
// RUN: not %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_tracing %s 2>&1 | FileCheck %s
//
// SPV_EXT_shader_invocation_reorder is opt-in (F24/L4).
//
// FeatureManager::enabledByDefault returns false for it, so a shader that uses a
// hit object has to ask for it explicitly. The two RUN lines cover both ways of
// not asking:
// * the default mode, where every extension that is not opt-in is allowed and
//   this one is not (first RUN line);
// * an explicit allow-list that names another extension but not this one
//   (second RUN line). This is the half that proves the restriction is not
//   bypassable: the entry points of <vk/ext/invocation_reorder.h> must not
//   smuggle the extension into the module through [[vk::ext_extension]], which
//   writes the OpExtension string without consulting FeatureManager and would
//   therefore pass both runs.
//
// The diagnostic is emitted three times here because three different places
// request the extension: the type of the declared hit object, the recording
// instruction and the accessor. Every one of them is a reason a driver without
// VK_EXT_ray_tracing_invocation_reorder would reject the module, so refusing at
// compile time is the useful error: the shader cannot work on such a device
// anyway.
#include <vk/ext/invocation_reorder.h>

RWStructuredBuffer<uint> Out : register(u0);

[shader("raygeneration")]
void main() {
  // CHECK: error: SPIR-V extension 'SPV_EXT_shader_invocation_reorder' required for hit object types but not permitted to use
  vk::ext::HitObject ho;
  // CHECK: error: SPIR-V extension 'SPV_EXT_shader_invocation_reorder' required for OpHitObjectRecordEmptyEXT but not permitted to use
  vk::ext::HitObjectRecordEmpty(ho);
  // CHECK: error: SPIR-V extension 'SPV_EXT_shader_invocation_reorder' required for OpHitObjectGetRayFlagsEXT but not permitted to use
  Out[0] = vk::ext::HitObjectGetRayFlags(ho);
}
