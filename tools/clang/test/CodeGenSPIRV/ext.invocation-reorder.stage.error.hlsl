// RUN: not %dxc -T cs_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_EXT_shader_invocation_reorder %s 2>&1 | FileCheck %s
//
// The feature is refused outside the ray tracing stages (F24/L4).
//
// The extension places two different restrictions, and the split matters
// because a shader that reorders also reads the object it reorders by:
// * OpReorderThreadWithHintEXT and OpReorderThreadWithHitObjectEXT require the
//   RayGenerationKHR execution model;
// * the OpHitObject*EXT instructions require RayGenerationKHR, ClosestHitKHR or
//   MissKHR.
// SPIRV-Tools registers exactly those two limitations and rejects the module
// otherwise ("... requires RayGenerationKHR execution model"), so a module built
// from this shader would be invalid whatever the compiler did; reporting it here
// is the useful error, and the stage of the entry point is only known while the
// call is lowered.
//
// A compute shader is not one of the three execution models, so every call is
// rejected. ext.invocation-reorder.reorder-stage.error.hlsl covers the narrower
// half: a closest hit shader, where the accessors are allowed and only the
// reorder entry point is not.
#include <vk/ext/invocation_reorder.h>

RWStructuredBuffer<uint> Out : register(u0);

[numthreads(1, 1, 1)]
void main() {
  // Declaring the object is not itself a diagnostic: the stage restriction is
  // attached to the instructions, so the declaration is not reported here.
  vk::ext::HitObject ho;
  // CHECK: error: hit object instructions can only be used in a ray generation, closest hit or miss shader: the OpHitObject*EXT instructions of SPV_EXT_shader_invocation_reorder require the RayGenerationKHR, ClosestHitKHR or MissKHR execution model, and the current entry point is a 'cs' shader
  vk::ext::HitObjectRecordEmpty(ho);
  // CHECK: error: hit object instructions can only be used in a ray generation, closest hit or miss shader: the OpHitObject*EXT instructions of SPV_EXT_shader_invocation_reorder require the RayGenerationKHR, ClosestHitKHR or MissKHR execution model, and the current entry point is a 'cs' shader
  Out[0] = vk::ext::HitObjectGetRayFlags(ho);
  // CHECK: error: ReorderThread can only be used in a ray generation shader: OpReorderThreadWithHintEXT and OpReorderThreadWithHitObjectEXT require the RayGenerationKHR execution model, and the current entry point is a 'cs' shader
  vk::ext::ReorderThread(0u, 0u);
}
