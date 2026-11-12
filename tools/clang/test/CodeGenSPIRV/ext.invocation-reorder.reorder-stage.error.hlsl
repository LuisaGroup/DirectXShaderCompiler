// RUN: not %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_EXT_shader_invocation_reorder %s 2>&1 | FileCheck %s
//
// Reordering is ray generation only (F24/L4).
//
// The accessors of <vk/ext/invocation_reorder.h> are allowed in a closest hit
// shader (SPIRV-Tools: "requires RayGenerationKHR, ClosestHitKHR and MissKHR
// execution models"), but the two reorder entry points are not: they register
// the stricter RayGenerationKHR-only limitation. A closest hit shader that reads
// a hit object therefore compiles, and the same shader must be refused as soon
// as it tries to reorder - which is exactly what this file checks: the accessor
// below produces no diagnostic and the reorder call produces the one CHECK line.
#include <vk/ext/invocation_reorder.h>

RWStructuredBuffer<uint> Out : register(u0);

struct [raypayload] Payload {
  float4 color : read(caller) : write(closesthit);
};
struct Attribs {
  float2 bary;
};

[shader("closesthit")]
void main(inout Payload p, in Attribs a) {
  vk::ext::HitObject ho;
  vk::ext::HitObjectRecordEmpty(ho);
  Out[0] = vk::ext::HitObjectGetRayFlags(ho);
  // CHECK: error: ReorderThread can only be used in a ray generation shader: OpReorderThreadWithHintEXT and OpReorderThreadWithHitObjectEXT require the RayGenerationKHR execution model, and the current entry point is a 'closesthit' shader
  vk::ext::ReorderThread(ho);
}
