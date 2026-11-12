// RUN: %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_EXT_shader_invocation_reorder -fspv-extension=SPV_NV_ray_tracing_motion_blur %s | FileCheck %s
//
// SPV_EXT_shader_invocation_reorder: the hit object type, its accessors and the
// two reorder entry points, with their capability and extensions (F24/L0,
// F24/L1, F24/L2). L3 is implicit: dxc validates every module it emits unless
// -Vd is given, so this file compiling at all is the validity gate - and this is
// also the case where an operand the validator rejects (a hit object that is not
// a pointer to OpTypeHitObjectEXT, a reorder hint that is not a 32-bit integer, a
// matrix result that is not 4 columns of float3) fails.
//
// The entry API is header-only (<vk/ext/invocation_reorder.h>): DXR has
// HitObject, but the SPIR-V instructions have no DXIL counterpart, so the
// declarations are free functions in namespace vk::ext and every one of them is
// a [[vk::ext_instruction]] declaration that SPIR-V CodeGen replaces with the
// instruction in place of the call.
//
// The hit object is an opaque SPIR-V type whose instructions take the object
// through a pointer (SPIRV-Tools, ValidateHitObjectPointerEXT: "Hit Object must
// be a pointer" / "Type must be OpTypeHitObjectEXT"), so every accessor below
// passes the local variable %ho and nothing is loaded or copied.
//
// What this file cannot prove: no driver implements the extension here, so the
// reordering itself (and whether the hint means anything to an implementation) is
// unverifiable; the hit object only records a miss, because tracing into one
// needs a payload variable the front end cannot declare yet (see the header).
#include <vk/ext/invocation_reorder.h>

RWStructuredBuffer<uint> U : register(u0);
RWStructuredBuffer<float> F : register(u1);

[shader("raygeneration")]
void main() {
  // The one construction that needs nothing but ordinary HLSL values: an object
  // that records the miss described by (origin, tMin, direction, tMax). Every
  // operand below is chosen so that a swapped pair is visible in the encoding.
  vk::ext::HitObject ho;
  vk::ext::HitObjectRecordMiss(ho, 0u, 3u, float3(1, 2, 3), 0.5f,
                               float3(0, 0, -1), 100.0f);
  // Rays.
  F[0] = vk::ext::HitObjectGetRayTMin(ho);
  F[1] = vk::ext::HitObjectGetRayTMax(ho);
  F[2] = vk::ext::HitObjectGetCurrentTime(ho);
  F[3] = vk::ext::HitObjectGetObjectRayOrigin(ho).x;
  F[4] = vk::ext::HitObjectGetObjectRayDirection(ho).y;
  F[5] = vk::ext::HitObjectGetWorldRayOrigin(ho).z;
  F[6] = vk::ext::HitObjectGetWorldRayDirection(ho).x;
  U[0] = vk::ext::HitObjectGetRayFlags(ho);
  // Transforms: SPIRV-Tools fixes the result type to four float3 columns.
  float4x3 o2w = vk::ext::HitObjectGetObjectToWorld(ho);
  float4x3 w2o = vk::ext::HitObjectGetWorldToObject(ho);
  // Intersection. Undefined for the miss object recorded above by construction,
  // but still a defined instruction with a defined encoding.
  U[1] = vk::ext::HitObjectGetHitKind(ho);
  U[2] = vk::ext::HitObjectGetPrimitiveIndex(ho);
  U[3] = vk::ext::HitObjectGetGeometryIndex(ho);
  U[4] = vk::ext::HitObjectGetInstanceId(ho);
  U[5] = vk::ext::HitObjectGetInstanceCustomIndex(ho);
  // Shader binding table.
  U[6] = vk::ext::HitObjectGetShaderBindingTableRecordIndex(ho);
  uint2 handle = vk::ext::HitObjectGetShaderRecordBufferHandle(ho);
  vk::ext::HitObjectSetShaderBindingTableRecordIndex(ho, 7u);
  // State.
  U[7] = vk::ext::HitObjectIsEmpty(ho) ? 1 : 0;
  U[8] = vk::ext::HitObjectIsHit(ho) ? 1 : 0;
  U[9] = vk::ext::HitObjectIsMiss(ho) ? 1 : 0;
  // Both reorder forms, in the only execution model that allows them. The hint
  // and bits of the second call are non-zero so that the two optional operands
  // cannot be confused with each other or dropped.
  vk::ext::ReorderThread(7u, 3u);
  vk::ext::ReorderThread(ho, 5u, 2u);
  // Keep every value live so that nothing is folded away.
  F[7] = o2w[0][0] + w2o[1][1] + float(handle.x) + float(handle.y);
}

// L1: the capability and the extension, once each.
// RayTracingKHR is the capability ShaderInvocationReorderEXT depends on, and a
// ray generation entry point declares it; RayTracingMotionBlurNV is the extra
// capability OpHitObjectGetCurrentTimeEXT requires (SPIRV-Tools: "<op>: requires
// RayTracingMotionBlurNV capability"), and it in turn comes with its own
// extension. All three capabilities and all three extension strings must appear
// exactly once.
// CHECK:      OpCapability RayTracingKHR
// CHECK:      OpCapability ShaderInvocationReorderEXT
// CHECK:      OpCapability RayTracingMotionBlurNV
// CHECK-NOT:  OpCapability ShaderInvocationReorderEXT
// CHECK-NOT:  OpCapability RayTracingMotionBlurNV
// CHECK:      OpExtension "SPV_KHR_ray_tracing"
// CHECK:      OpExtension "SPV_EXT_shader_invocation_reorder"
// CHECK:      OpExtension "SPV_NV_ray_tracing_motion_blur"
// CHECK-NOT:  OpExtension "SPV_EXT_shader_invocation_reorder"
// CHECK-NOT:  OpExtension "SPV_NV_ray_tracing_motion_blur"
// CHECK:      OpMemoryModel Logical GLSL450
// CHECK:      OpEntryPoint RayGenerationKHR %main "main"
//
// L2.type: one OpTypeHitObjectEXT, with no operands at all (the instruction is
// (IdResult) only), and the object lives in a Function variable that the
// instructions below read through its pointer. The pointer's pointee being the
// OpTypeHitObjectEXT id is what rules out a struct fallback: had the type been
// lowered to an OpTypeStruct, the first line would not exist at all.
// The other two types are the ones SPIRV-Tools demands of the results:
// four %v3float columns for the transforms and a 2-component integer vector for
// the shader record buffer handle.
// CHECK-DAG:  [[TYPE:%[0-9A-Za-z_]+]] = OpTypeHitObjectEXT
// CHECK-DAG:  [[PTR:%[0-9A-Za-z_]+]] = OpTypePointer Function [[TYPE]]
// CHECK-DAG:  [[MAT:%[0-9A-Za-z_]+]] = OpTypeMatrix %v3float 4
// CHECK-DAG:  [[V2UINT:%[0-9A-Za-z_]+]] = OpTypeVector %uint 2
// CHECK:      OpFunction
// CHECK:      [[HO:%[0-9A-Za-z_]+]] = OpVariable [[PTR]] Function
//
// L2: the recording instruction. Operand order is
// (Hit Object, Ray Flags, Miss Index, Ray Origin, Ray TMin, Ray Direction,
// Ray TMax): the miss index is 3 and the interval is (0.5, 100), so a swap of
// the miss index with either endpoint, or of the two float3 vectors, fails.
// CHECK:      OpHitObjectRecordMissEXT [[HO]] %uint_0 %uint_3 [[ORIGIN:%[0-9A-Za-z_]+]] %float_0_5 [[DIRECTION:%[0-9A-Za-z_]+]] %float_100
//
// L2: every accessor, each reading the one object, with the result type
// SPIRV-Tools requires for it.
// CHECK:      OpHitObjectGetRayTMinEXT %float [[HO]]
// CHECK:      OpHitObjectGetRayTMaxEXT %float [[HO]]
// CHECK:      OpHitObjectGetCurrentTimeEXT %float [[HO]]
// CHECK:      OpHitObjectGetObjectRayOriginEXT %v3float [[HO]]
// CHECK:      OpHitObjectGetObjectRayDirectionEXT %v3float [[HO]]
// CHECK:      OpHitObjectGetWorldRayOriginEXT %v3float [[HO]]
// CHECK:      OpHitObjectGetWorldRayDirectionEXT %v3float [[HO]]
// CHECK:      OpHitObjectGetRayFlagsEXT %uint [[HO]]
// The transforms are [[MAT]]: four columns of three floats, i.e. the
// "Column Count of 4" / "Column Type of 3-component 32-bit float vectors" the
// validator demands, which is what the backend emits for HLSL float4x3.
// CHECK:      OpHitObjectGetObjectToWorldEXT [[MAT]] [[HO]]
// CHECK:      OpHitObjectGetWorldToObjectEXT [[MAT]] [[HO]]
// CHECK:      OpHitObjectGetHitKindEXT %uint [[HO]]
// CHECK:      OpHitObjectGetPrimitiveIndexEXT %uint [[HO]]
// CHECK:      OpHitObjectGetGeometryIndexEXT %uint [[HO]]
// CHECK:      OpHitObjectGetInstanceIdEXT %uint [[HO]]
// CHECK:      OpHitObjectGetInstanceCustomIndexEXT %uint [[HO]]
// CHECK:      OpHitObjectGetShaderBindingTableRecordIndexEXT %uint [[HO]]
// CHECK:      OpHitObjectGetShaderRecordBufferHandleEXT %v2uint [[HO]]
// The setter is the one member of the family that writes to the object; operand
// order is (Hit Object, SBT Record Index).
// CHECK:      OpHitObjectSetShaderBindingTableRecordIndexEXT [[HO]] %uint_7
// CHECK:      OpHitObjectIsEmptyEXT %bool [[HO]]
// CHECK:      OpHitObjectIsHitEXT %bool [[HO]]
// CHECK:      OpHitObjectIsMissEXT %bool [[HO]]
//
// L2.reorder: both forms. The hint form is (Hint, Bits), the hit object form is
// (Hit Object, Hint?, Bits?) - the two non-zero values prove the order, and the
// one-argument form is covered by the opt test.
// CHECK:      OpReorderThreadWithHintEXT %uint_7 %uint_3
// CHECK:      OpReorderThreadWithHitObjectEXT [[HO]] %uint_5 %uint_2
// CHECK:      OpFunctionEnd
