// RUN: not %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_tracing %s 2>&1 | FileCheck %s
// RUN: not %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_EXT_shader_invocation_reorder %s 2>&1 | FileCheck %s --check-prefix=MOTION
//
// HitObjectGetCurrentTime needs a second extension (F24/L4).
//
// OpHitObjectGetCurrentTimeEXT is the one accessor of
// <vk/ext/invocation_reorder.h> that SPIRV-Tools accepts only with the
// RayTracingMotionBlurNV capability ("OpHitObjectGetCurrentTimeEXT: requires
// RayTracingMotionBlurNV capability"), and that capability in turn is only legal
// together with OpExtension "SPV_NV_ray_tracing_motion_blur"
// ("Capability RayTracingMotionBlurNV is not allowed by Vulkan 1.2 specification
// (or requires extension)"). The accessor therefore requests both extensions,
// and the two RUN lines show that neither half can be dropped:
// * without SPV_EXT_shader_invocation_reorder nothing of the family is allowed,
//   so the missing invocation-reorder extension is reported (first RUN line);
// * with it but without SPV_NV_ray_tracing_motion_blur the accessor itself is
//   refused (second RUN line), which is the state a shader would otherwise
//   compile into a module that no driver without motion blur accepts.
#include <vk/ext/invocation_reorder.h>

RWStructuredBuffer<float> Out : register(u0);

[shader("raygeneration")]
void main() {
  vk::ext::HitObject ho;
  vk::ext::HitObjectRecordEmpty(ho);
  // CHECK: error: SPIR-V extension 'SPV_EXT_shader_invocation_reorder' required for hit object types but not permitted to use
  // MOTION: error: SPIR-V extension 'SPV_NV_ray_tracing_motion_blur' required for OpHitObjectGetCurrentTimeEXT but not permitted to use
  Out[0] = vk::ext::HitObjectGetCurrentTime(ho);
}
