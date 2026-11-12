// RUN: %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_EXT_shader_invocation_reorder %s | FileCheck %s --check-prefix=OFF
// RUN: %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 %s | FileCheck %s --check-prefix=OFF
//
// SPV_EXT_shader_invocation_reorder off path (F24/L5).
//
// The shader includes <vk/ext/invocation_reorder.h>, so the hit object type and
// every entry point of the extension are declared, but it declares no hit object
// and calls into the extension nowhere. Nothing of the feature may reach the
// module: no ShaderInvocationReorderEXT, no RayTracingMotionBlurNV, no
// OpExtension for either extension, no OpTypeHitObjectEXT, no OpHitObject*EXT
// and no OpReorderThread*EXT. The pre-existing ray query instructions this
// shader does use must keep their exact encoding.
//
// The first RUN line is the interesting one: the extension is enabled and still
// must not be declared, because a module that declares an extension it does not
// use invites a driver to reject it for nothing. The second RUN line is the
// default mode, where -fspv-extension is not passed at all, so the extension is
// not even allowed - and declaring the header must still be accepted, because a
// shader cannot know which of the extensions it includes are enabled.
#include <vk/ext/invocation_reorder.h>

RaytracingAccelerationStructure Scene : register(t0);
RWStructuredBuffer<uint> Out : register(u0);

[shader("raygeneration")]
void main() {
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
  RayDesc ray = {float3(0, 0, 0), 0.0f, float3(0, 0, 1), 100.0f};
  q.TraceRayInline(Scene, RAY_FLAG_NONE, 0xFF, ray);
  while (q.Proceed()) {
    Out[1] = q.CandidateInstanceIndex();
  }
  Out[0] = q.CommittedInstanceIndex();
}

// The ray query the shader does use keeps its own capability and extension.
// OFF:      OpCapability RayQueryKHR
// OFF-NOT:  OpCapability ShaderInvocationReorderEXT
// OFF-NOT:  OpCapability RayTracingMotionBlurNV
// OFF:      OpExtension "SPV_KHR_ray_query"
// OFF-NOT:  OpExtension "SPV_EXT_shader_invocation_reorder"
// OFF-NOT:  OpExtension "SPV_NV_ray_tracing_motion_blur"
// OFF-NOT:  OpTypeHitObjectEXT
// OFF-NOT:  OpHitObject
// OFF-NOT:  OpReorderThread
// OFF:      OpMemoryModel Logical GLSL450
// OFF:      OpEntryPoint RayGenerationKHR %main "main"
// OFF:      [[RQ:%[0-9A-Za-z_]+]] = OpVariable %_ptr_Function_rayQueryKHR Function
// The pre-existing accessors are untouched: same opcode, same result type, same
// candidate/committed selector as before the extension existed.
// OFF:      OpRayQueryGetIntersectionInstanceIdKHR %uint [[RQ]] %uint_0
// OFF:      OpRayQueryGetIntersectionInstanceIdKHR %uint [[RQ]] %uint_1
// OFF:      OpFunctionEnd
