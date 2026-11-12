// RUN: %dxc -T lib_6_9 -E main -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_EXT_shader_invocation_reorder %s | FileCheck %s
//
// SPV_EXT_shader_invocation_reorder after legalization and optimization
// (F24/L6).
//
// Without -fcgl the module goes through legalization (which inlines the entry
// points of <vk/ext/invocation_reorder.h> into the shader that calls them),
// spirv-opt and the capability trimming pass. Three things can go wrong only
// here: the optimizer drops or rewrites a hit object instruction, the trimming
// pass removes ShaderInvocationReorderEXT from a module that still uses it, or
// the optimizer removes the variable the hit object lives in and leaves an
// instruction that reads it. All three produce either a missing instruction or
// an invalid module, and dxc validates what it emits unless -Vd is given, so
// this file compiling at all is the validity gate.
//
// This file deliberately omits SPV_NV_ray_tracing_motion_blur, so it also shows
// that the accessors other than HitObjectGetCurrentTime do not need it.
#include <vk/ext/invocation_reorder.h>

RWStructuredBuffer<uint> U : register(u0);

[shader("raygeneration")]
void main() {
  vk::ext::HitObject ho;
  vk::ext::HitObjectRecordEmpty(ho);
  U[0] = vk::ext::HitObjectGetRayFlags(ho);
  U[1] = vk::ext::HitObjectIsEmpty(ho) ? 1 : 0;
  U[2] = vk::ext::HitObjectGetInstanceId(ho);
  vk::ext::HitObjectSetShaderBindingTableRecordIndex(ho, 4u);
  // Both reorder forms, including the one-argument overload, which must be
  // emitted with the two optional operands left out.
  vk::ext::ReorderThread(ho);
  vk::ext::ReorderThread(9u, 1u);
  // Record into the same object again: the optimizer may not merge the two
  // recording instructions, and the accessor after it must still read %ho.
  vk::ext::HitObjectRecordMiss(ho, 0u, 2u, float3(0, 0, 0), 0.0f, float3(0, 0, 1),
                               10.0f);
  U[3] = vk::ext::HitObjectGetRayTMax(ho) > 0.0 ? 1 : 0;
  U[4] = vk::ext::HitObjectIsMiss(ho) ? 1 : 0;
}

// The capability and both extension strings survive legalization, spirv-opt and
// capability trimming.
// CHECK:      OpCapability ShaderInvocationReorderEXT
// CHECK:      OpExtension "SPV_KHR_ray_tracing"
// CHECK:      OpExtension "SPV_EXT_shader_invocation_reorder"
// CHECK-NOT:  OpExtension "SPV_NV_ray_tracing_motion_blur"
// CHECK:      OpMemoryModel Logical GLSL450
// CHECK:      OpEntryPoint RayGenerationKHR %main "main"
// The opaque type survives, and only the entry point is left: legalization
// inlined the wrapper functions. The variable that holds the object survives in
// its Function storage class.
// CHECK:      [[TYPE:%[0-9A-Za-z_]+]] = OpTypeHitObjectEXT
// CHECK:      %main = OpFunction
// CHECK-NOT:  = OpFunction
// CHECK:      [[HO:%[0-9A-Za-z_]+]] = OpVariable %{{[0-9A-Za-z_]+}} Function
// The whole instruction stream is still there, in source order, and every
// accessor still reads the one object.
// CHECK:      OpHitObjectRecordEmptyEXT [[HO]]
// CHECK:      OpHitObjectGetRayFlagsEXT %uint [[HO]]
// CHECK:      OpHitObjectIsEmptyEXT %bool [[HO]]
// CHECK:      OpHitObjectGetInstanceIdEXT %uint [[HO]]
// CHECK:      OpHitObjectSetShaderBindingTableRecordIndexEXT [[HO]] %uint_4
// The one-argument form has no optional operands.
// CHECK:      OpReorderThreadWithHitObjectEXT [[HO]]
// CHECK-NOT:  OpReorderThreadWithHitObjectEXT [[HO]] %uint
// The hint form keeps both operands.
// CHECK:      OpReorderThreadWithHintEXT %uint_9 %uint_1
// CHECK:      OpHitObjectRecordMissEXT [[HO]] %uint_0 %uint_2
// CHECK:      OpHitObjectGetRayTMaxEXT %float [[HO]]
// CHECK:      OpHitObjectIsMissEXT %bool [[HO]]
// CHECK:      OpFunctionEnd
