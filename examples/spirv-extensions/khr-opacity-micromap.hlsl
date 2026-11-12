// RUN: %dxc -T lib_6_9 -E main -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_KHR_opacity_micromap %s

// Opacity micromaps with SPV_KHR_opacity_micromap.
//
// An opacity micromap (OMM) is per-micro-triangle opacity state stored in the
// acceleration structure. Instead of a whole triangle being opaque or
// transparent, each micro-triangle of it carries its own opacity, or is marked
// as unknown so that an any-hit shader is invoked. Alpha-tested foliage, fences
// and chain-link geometry become essentially free: the traversal unit resolves
// the mask, which removes the any-hit shader invocations that alpha testing
// needs today.
//
// HLSL asks for it with a ray flag; SPIR-V expresses it as a module-level
// execution mode, because whether a *module* may traverse opacity micromaps is
// not a per-ray property in Vulkan. DXC therefore derives the execution mode
// from the flag instead of translating the flag:
//
//   RayQuery<RayFlags, RayQueryFlags>
//                                  ^ RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS
//     ^ RAY_FLAG_*                    enables OMM for this ray query object
//
//   TraceRay(..., RayFlags, ...)
//                ^ RAY_FLAG_FORCE_OMM_2_STATE (0x400) - the same 0x400 bit is
//                  SPIR-V's ForceOpacityMicromap2StateKHR
//
// With -fspv-extension=SPV_KHR_opacity_micromap DXC emits, once per entry point
// that requests it:
//
//   OpCapability RayTracingOpacityMicromapExecutionModeKHR ; 6032
//   OpCapability RayTracingOpacityMicromapKHR              ; 5381, only when
//                                                          ; the force-2-state
//                                                          ; ray flag is used
//   OpExtension "SPV_KHR_opacity_micromap"
//   OpExecutionModeId %main OpacityMicromapIdKHR %opacityMicromapEnable ; 6031
//   OpDecorate %opacityMicromapEnable SpecId 0
//   %bool = OpTypeBool
//   %opacityMicromapEnable = OpSpecConstantTrue %bool
//
// The operand of OpacityMicromapIdKHR is an id operand, so the mode is spelled
// OpExecutionModeId; a literal operand (OpExecutionMode ... 1) is invalid.
// The id is a boolean specialization constant:
//
//   * Its default is true, so a pipeline that enables the feature and the
//     pipeline flag gets opacity micromaps without specializing anything.
//   * A host that wants OMM disabled specializes SpecId 0 (see
//     -fvk-opacity-micromap-spec-id=N to move it) to VK_FALSE. The constant is
//     never folded to OpConstantTrue, so specialization always remains possible.
//   * The execution mode only affects *ray query* traversal. Pipeline
//     TraceRay() calls are governed by the pipeline creation flag below, so a
//     TraceRay()-only shader declares an inert mode.
//
// Without the extension the module is unchanged (byte for byte) and DXC warns
// that the opt-in was ignored. Note that RAY_FLAG_FORCE_OMM_2_STATE in a ray
// flags operand without the extension even fails SPIR-V validation, because that
// bit requires the RayTracingOpacityMicromapKHR capability.
//
// Required from the host:
//  * Vulkan device extension VK_KHR_opacity_micromap (requires Vulkan 1.2 with
//    VK_KHR_ray_query / VK_KHR_ray_tracing),
//  * feature bit VkPhysicalDeviceOpacityMicromapFeaturesEXT::micromap (query it
//    with vkGetPhysicalDeviceFeatures2 and chain the structure into
//    VkDeviceCreateInfo::pNext with micromap set to VK_TRUE),
//  * pipeline creation flag
//    VK_PIPELINE_CREATE_RAY_TRACING_OPACITY_MICROMAP_BIT_KHR for every pipeline
//    that issues TraceRay() against micromap-enabled geometry, and a pipeline
//    layout that includes the micromap data,
//  * optionally, VkSpecializationInfo with a VkSpecializationMapEntry for the
//    SpecId above and a VkBool32 value, to override the enable default.
// The compiler cannot check any of these: a shader compiles and validates without
// the device feature, and the traversal result is undefined if the module
// declares the mode while the device does not enable it - or if the acceleration
// structure contains micromaps and the mode is missing (VK_KHR_opacity_micromap
// without the VK_EXT_opacity_micromap fallback).
//
// See the "Opacity micromaps" section of docs/SPIR-V.rst and
// tools/clang/test/CodeGenSPIRV/vk.opacity-micromap*.hlsl.

RaytracingAccelerationStructure Scene : register(t0);

struct Payload {
  float4 color;
};

[shader("raygeneration")]
void main() {
  RayDesc ray = { float3(0.0, 0.0, 0.0), 0.0, float3(1.0, 0.0, 0.0), 1000.0 };

  // Ray query traversal that lets the traversal unit evaluate opacity
  // micromaps: the RayQueryFlags template argument sets the opt-in and the
  // ForceOMM2State ray flag asks for the 2-state (opaque/transparent) evaluation
  // that micromaps provide without any-hit shaders.
  RayQuery<RAY_FLAG_NONE, RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS> query;
  query.TraceRayInline(Scene, RAY_FLAG_FORCE_OMM_2_STATE, 0xFF, ray);
  query.Proceed();

  if (query.CommittedStatus() == COMMITTED_TRIANGLE_HIT) {
    Payload hit = { float4(1.0, 0.0, 0.0, 1.0) };
  }
}
