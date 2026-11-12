// RUN: %dxc -T lib_6_9 -E main -spirv -fcgl -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_EXT_shader_invocation_reorder %s

// Invocation reordering with VK_EXT_ray_tracing_invocation_reorder /
// SPV_EXT_shader_invocation_reorder.
//
// A ray generation shader that traces many rays has no way to tell the
// implementation which rays belong together, so every ray is traced at the point
// in the shader that asks for it. Invocations of a wave then walk the
// acceleration structure from unrelated starting points: the nodes and the
// geometry they fetch are different, the caches hold no shared lines, and the
// time the invocations spend waiting for memory is time the wave is not
// executing. Invocation reordering lets the shader give the implementation the
// material to fix that: the ray becomes a *value* - a hit object - that the
// shader builds first and traverses second, with a hint that says which
// invocations are worth grouping together. The implementation repacks the
// invocations that hold similar objects ("reorder" a wave), and the traversal
// then starts from rays that are likely to touch the same memory, so one fetch
// serves several invocations.
//
// What it buys, and what it does not:
// * the win is memory coherence during traversal - it shows up as fewer and
//   better-predicted memory accesses in the acceleration-structure traversal,
//   which is why the extension is worth having in a shader that traces many
//   short, diverging rays (shadows, AO, GI sampling) and worth little in a shader
//   that traces one long ray;
// * the hint is a *request*. An implementation may ignore it, may group by it
//   differently than the shader intended, or may not reorder at all, so a shader
//   must not depend on the order the invocations run in;
// * the object a shader can read back is what the implementation resolved for
//   it, so the accessors below describe the object, not the ray parameters the
//   shader wrote.
//
// How it is spelled in HLSL: <vk/ext/invocation_reorder.h> declares the hit
// object type (OpTypeHitObjectEXT, 5313) and the instructions of the extension
// as free functions in namespace vk::ext, each a [[vk::ext_instruction]]
// declaration that SPIR-V CodeGen replaces with the instruction in place of the
// call. For the shader below the compiler emits:
//
//   OpCapability RayTracingKHR
//   OpCapability ShaderInvocationReorderEXT
//   OpExtension "SPV_KHR_ray_tracing"
//   OpExtension "SPV_EXT_shader_invocation_reorder"
//   %hitobject = OpTypeHitObjectEXT          ; opaque, no operands
//   %ho        = OpVariable %_ptr_Function_hitobject Function
//                  OpHitObjectRecordMissEXT %ho %uint_0 %uint_7 ... 
//                  OpReorderThreadWithHitObjectEXT %ho %uint_hint %uint_bits
//   %t         = OpHitObjectGetRayTMaxEXT %float %ho
//   %dir       = OpHitObjectGetWorldRayDirectionEXT %v3float %ho
//
// The two reorder forms are ReorderThread(hint, bits) - no hit object, the hint
// alone - and ReorderThread(hitObject[, hint, bits]). The hit object form is the
// interesting one: the implementation groups by the object, and the optional hint
// and bits refine that ("these n low bits of my own sort key are what matters").
//
// Restrictions, all diagnosed by the compiler rather than miscompiled:
// * Ray tracing stages only, and reorder is narrower still: OpReorderThread*EXT
//   requires the RayGenerationKHR execution model, the OpHitObject*EXT accessors
//   accept RayGenerationKHR, ClosestHitKHR and MissKHR. A compute or pixel
//   shader that calls into this header is a compile error.
// * -fspv-extension=SPV_EXT_shader_invocation_reorder. The extension is opt-in: a
//   driver that does not expose VK_EXT_ray_tracing_invocation_reorder rejects a
//   module that declares ShaderInvocationReorderEXT.
// * -fspv-extension=SPV_KHR_ray_tracing as well, because a RayGenerationKHR entry
//   point is what SPV_KHR_ray_tracing is for and the capability the extension
//   depends on comes from it.
// * A hit object holds no value until something records into it. Reading one
//   that no recording instruction has written to is a compile error (this shader
//   records first); the compiler can only track local variables of the function
//   it is translating.
// * HitObjectGetCurrentTime additionally needs
//   -fspv-extension=SPV_NV_ray_tracing_motion_blur, because SPIRV-Tools requires
//   the RayTracingMotionBlurNV capability for it.
//
// The construction gap, in this landing: a hit object can be made *empty*
// (HitObjectRecordEmpty) or made to record a *miss* (HitObjectRecordMiss, used
// below). Recording an actual hit needs one of two instructions that this header
// does not provide yet:
// * OpHitObjectRecordFromQueryEXT (5304), which turns a RayQuery into a hit
//   object, needs an operand of storage class HitObjectAttributeEXT, and HLSL has
//   no syntax for a variable in that storage class;
// * OpHitObjectTraceRayEXT (5316) and the *ReorderExecute* instructions trace the
//   ray themselves and need a payload variable in storage class RayPayloadKHR;
//   only the HLSL TraceRay intrinsic creates one.
// Both would need a new front-end surface, so they are not faked here; see
// docs/SPIR-V.rst ("Invocation reordering"). The reorder and the accessors of
// this header are complete, and a shader that obtains a hit object through
// either of the two missing instructions later needs no change to them.
//
// Required from the host - the compiler cannot check any of this:
// * the VK_EXT_ray_tracing_invocation_reorder device extension (enable
//   VK_EXT_RAY_TRACING_INVOCATION_REORDER_EXTENSION_NAME at vkCreateDevice),
// * its rayTracingInvocationReorder feature bit, queried and enabled through the
//   extension's feature struct in the VkPhysicalDeviceFeatures2 /
//   VkDeviceCreateInfo pNext chain,
// * a ray tracing pipeline: VK_KHR_ray_tracing_pipeline and the RayGenerationKHR
//   stage this shader compiles for,
// * a shader binding table whose miss records are indexed by the miss index this
//   shader records; reordering does not change how a shadow ray is dispatched,
//   only in which order invocations reach the traversal,
// * nothing else: the reorder is a shader-side request, and there is no pipeline
//   flag or host call that turns it on or off per shader.
//
// See docs/SPIR-V.rst ("Invocation reordering") and
// tools/clang/test/CodeGenSPIRV/ext.invocation-reorder*.hlsl for the tests that
// pin the capability, the type and instruction encodings, the optimizer path and
// the diagnostics.

#include <vk/ext/invocation_reorder.h>

// One ray per pixel of the dispatch, traced from the launch index.
struct Camera {
  float4x4 viewProjInverse;
};

ConstantBuffer<Camera> g_camera : register(b0);
RaytracingAccelerationStructure g_scene : register(t0);
RWStructuredBuffer<float4> g_color : register(u0);

// The miss shader index the recorded object names, and how many bits of the hint
// the shader cares about. The hint itself is the shader's own notion of "these
// invocations belong together": here the three sign bits of the ray direction.
static const uint kMissShaderIndex = 7;
static const uint kHintBits = 3u;

[shader("raygeneration")]
void main() {
  const uint2 pixel = DispatchRaysIndex().xy;
  const uint2 size = DispatchRaysDimensions().xy;

  // Pixel -> ray. The direction is what the hint below is derived from.
  const float2 ndc = (float2(pixel) + 0.5) * 2.0 / float2(size) - 1.0;
  const float3 direction =
      normalize(mul(float4(ndc, 0.5, 0.0), g_camera.viewProjInverse).xyz);

  // Build the object first. With this landing the only constructions available
  // are "empty" and the miss recorded here; a hit would come from a trace or a
  // ray query (see the header comment). The ray is described by
  // (origin, tMin, direction, tMax) in exactly the order the instruction wants.
  vk::ext::HitObject hitObject;
  vk::ext::HitObjectRecordMiss(hitObject, 0u, kMissShaderIndex,
                               float3(0.0, 0.0, 0.0), 0.001, direction, 1000.0);

  // Ask the implementation to group this invocation with the others that hold a
  // similar object. The hint packs the ray's quadrant, and kHintBits says how
  // many of its low bits the shader cares about: an implementation may group by
  // the bits that are set in the mask and ignore the rest. The call is an
  // ordinary instruction in SPIR-V - the invocation continues after it - but what
  // runs next may be a repacked wave, so nothing after this point may depend on
  // the values the lanes of the original wave happened to hold.
  const uint hint = (direction.x > 0.0 ? 1u : 0u) | (direction.y > 0.0 ? 2u : 0u) |
                    (direction.z > 0.0 ? 4u : 0u);
  vk::ext::ReorderThread(hitObject, hint, kHintBits);

  // Read back what the object carries. These are the ray parameters the object
  // recorded, resolved by the implementation; every accessor takes the object by
  // reference, so nothing is copied.
  const float tMax = vk::ext::HitObjectGetRayTMax(hitObject);
  const float3 worldDirection = vk::ext::HitObjectGetWorldRayDirection(hitObject);
  const uint rayFlags = vk::ext::HitObjectGetRayFlags(hitObject);

  // The state of the object decides what is meaningful. Here the recorded ray is
  // a miss, so IsMiss is true, IsEmpty and IsHit are false, and the intersection
  // accessors (HitObjectGetPrimitiveIndex and friends) have no defined value -
  // they are only read for an object that recorded an intersection.
  float4 color = float4(0.0, 0.0, 0.0, 1.0);
  if (vk::ext::HitObjectIsEmpty(hitObject)) {
    color = float4(0.0, 0.0, 0.0, 1.0);
  } else if (vk::ext::HitObjectIsMiss(hitObject)) {
    // A miss: shade the ray the object carries, which is what a miss shader
    // would do had the ray been traced.
    color = float4(0.1, 0.1, 0.1, 1.0) * abs(worldDirection.y) * tMax;
  } else {
    // A hit: the intersection the object recorded. Unreachable with this
    // landing's constructions, and kept so that the code a shader needs once the
    // trace-into-a-hit-object instructions land is visible.
    color = float4(float(vk::ext::HitObjectGetInstanceId(hitObject)) * 0.01,
                   float(vk::ext::HitObjectGetPrimitiveIndex(hitObject)) * 0.01,
                   float(vk::ext::HitObjectGetGeometryIndex(hitObject)) * 0.01,
                   1.0);
    color.rgb *= vk::ext::HitObjectGetHitKind(hitObject) == 3u ? 1.0 : 0.5;
  }
  // The flags the object was recorded with are available whether or not it is a
  // miss, so a shader can check that it is reading the object it expects.
  color.a = rayFlags == 0u ? 1.0 : color.a;

  g_color[pixel.y * size.x + pixel.x] = color;
}
