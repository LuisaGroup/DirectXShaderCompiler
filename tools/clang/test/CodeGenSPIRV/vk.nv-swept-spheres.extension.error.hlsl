// RUN: not %dxc -T cs_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 %s 2>&1 | FileCheck %s
// RUN: not %dxc -T cs_6_5 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_query %s 2>&1 | FileCheck %s
//
// SPV_NV_linear_swept_spheres is opt-in (G27/L4).
//
// FeatureManager::enabledByDefault returns false for it, so a module that reads
// sphere (or linear-swept-sphere) parameters has to be asked for explicitly. The
// two RUN lines cover both ways of not asking:
// * the default mode, where every extension that is not opt-in is allowed and
//   this one is not (first RUN line);
// * an explicit allow-list that names another extension but not this one
//   (second RUN line). This is the half that proves the restriction is not
//   bypassable: the accessors must not smuggle the extension into the module
//   through [[vk::ext_extension]], which writes the OpExtension string without
//   consulting FeatureManager and would therefore pass both runs below. The
//   same is true of [[vk::ext_capability]] for the capability - a module that
//   declared RayTracingSpheresGeometryNV without the extension would be rejected
//   by SPIRV-Tools ("Capability RayTracingSpheresGeometryNV is not allowed by
//   Vulkan 1.2 specification (or requires extension)"). Refusing at compile time
//   is the useful error: the shader cannot work without
//   VK_NV_ray_tracing_linear_swept_spheres anyway.
//
// Both diagnostics come from the CapabilityVisitor, i.e. from the instruction
// this shader would have emitted, and name that instruction, so a call that
// would select the wrong capability is also visible in the message. The header
// wrappers (vk::nv::RayQueryIsCandidateSphereHit and friends) produce the same
// diagnostic per wrapper call; they only move the reported location into the
// header, which is why the diagnostic lines below are matched without the
// filename.
#include <vk/nv/linear_swept_spheres.h>

RaytracingAccelerationStructure Scene : register(t0);
RWStructuredBuffer<float> Out : register(u0);

[numThreads(1, 1, 1)]
void main() {
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
  RayDesc ray = {float3(0, 0, 0), 0.0f, float3(0, 0, 1), 100.0f};
  q.TraceRayInline(Scene, RAY_FLAG_NONE, 0xFF, ray);
  while (q.Proceed()) {
  }
  // CHECK: error: SPIR-V extension 'SPV_NV_linear_swept_spheres' required for OpRayQueryGetIntersectionSpherePositionNV but not permitted to use
  Out[0] = vk::nv::RayQueryGetIntersectionSpherePosition(
               q, vk::nv::SphereIntersectionCommitted)
               .x;
  // CHECK: error: SPIR-V extension 'SPV_NV_linear_swept_spheres' required for OpRayQueryGetIntersectionSphereRadiusNV but not permitted to use
  Out[1] = vk::nv::RayQueryGetIntersectionSphereRadius(
      q, vk::nv::SphereIntersectionCandidate);
  // CHECK: error: SPIR-V extension 'SPV_NV_linear_swept_spheres' required for OpRayQueryIsSphereHitNV but not permitted to use
  Out[2] = vk::nv::RayQueryIsSphereHit(q, vk::nv::SphereIntersectionCandidate)
               ? 1.0
               : 0.0;
  // The linear-swept-sphere half is refused by the same extension, with its own
  // instruction named - one capability per geometry kind, one extension for both.
  // CHECK: error: SPIR-V extension 'SPV_NV_linear_swept_spheres' required for OpRayQueryGetIntersectionLSSHitValueNV but not permitted to use
  Out[3] = vk::nv::RayQueryGetIntersectionLSSHitValue(
      q, vk::nv::SphereIntersectionCommitted);
  // CHECK: error: SPIR-V extension 'SPV_NV_linear_swept_spheres' required for OpRayQueryIsLSSHitNV but not permitted to use
  Out[4] =
      vk::nv::RayQueryIsLSSHit(q, vk::nv::SphereIntersectionCandidate) ? 1.0
                                                                     : 0.0;
}
