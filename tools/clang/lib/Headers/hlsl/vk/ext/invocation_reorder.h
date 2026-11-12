// Copyright (c) 2026 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Invocation reordering: VK_EXT_ray_tracing_invocation_reorder /
// SPV_EXT_shader_invocation_reorder.
//
// A ray generation shader that traces many rays has no way to tell the
// implementation which rays could be traced together, so every ray is traced
// where the shader happens to ask for it and the memory accesses of one
// invocation are unlikely to be coherent with the next. Invocation reordering
// makes the ray a *value* that the shader builds first and traces second: a hit
// object records a ray, the implementation groups ("repacks") the invocations
// that hold similar hit objects, and the reordered invocation continues with the
// traversal. The shader states its intent twice:
//
//   vk::ext::HitObject ho;
//   vk::ext::HitObjectRecordMiss(ho, rayFlags, missIndex, origin, tMin,
//                                direction, tMax);
//   vk::ext::ReorderThread(ho, /*hint*/ 0, /*bits*/ 0);  // or without the two
//   float t = vk::ext::HitObjectGetRayTMax(ho);
//
// The two entry points below lower to OpReorderThreadWithHintEXT (5314) and
// OpReorderThreadWithHitObjectEXT (5315), the hit object type to
// OpTypeHitObjectEXT (5313), and everything else to the OpHitObject*EXT
// instruction of the same name.
//
// The hit object is a SPIR-V *opaque type* whose instructions take the object
// through a pointer, not by value:
//
//   %ho = OpVariable %_ptr_Function_hitobject Function
//         OpHitObjectGetRayTMaxEXT %float %ho
//
// SPIRV-Tools enforces exactly that
// (external/SPIRV-Tools/source/val/validate_ray_tracing_reorder.cpp,
// ValidateHitObjectPointerEXT: "Hit Object must be a pointer" / "Type must be
// OpTypeHitObjectEXT"), which is why every accessor below takes the hit object
// as a [[vk::ext_reference]] parameter: the call passes the address of the
// variable, and no expression can be passed where an object is expected. The
// entry points are free functions in namespace vk::ext rather than members of a
// HitObject class, because a class needs an HLSL type that the DXIL backend and
// the SPIR-V backend share, and these instructions have no DXIL encoding.
// This header is therefore SPIR-V only, like <vk/ext/long_vector.h>: the
// vk::SpirvOpaqueType template it builds the type from is only declared by the
// front end when SPIR-V CodeGen is enabled, so a DXIL compile of a shader that
// includes it fails at the HitObject declaration below instead of silently
// lowering to something else.
//
// Module surface: OpCapability ShaderInvocationReorderEXT (5388) and
// OpExtension "SPV_EXT_shader_invocation_reorder", emitted by SPIR-V CodeGen
// from the instructions and the type itself (the OpTypeHitObjectEXT case in
// CapabilityVisitor::addCapabilityForType and the OpHitObject*EXT /
// OpReorderThread*EXT cases in its instruction visitor), not by
// [[vk::ext_capability]] / [[vk::ext_extension]] on the declarations below:
// those attributes write the capability and the extension string
// unconditionally, so -fspv-extension could neither select nor refuse them. The
// extension is opt-in, like SPV_NV_cluster_acceleration_structure: without
// -fspv-extension=SPV_EXT_shader_invocation_reorder every use is a compile error
// instead of a module that declares an extension the host never asked for.
// The capability itself requires RayTracingKHR, which a ray generation entry
// point already declares; a shader without a ray-tracing entry point is rejected
// before that (see the stage restriction below).
//
// Where the hit object comes from, and what is missing (see docs/SPIR-V.rst):
// - This landing provides the two constructions that need nothing but ordinary
//   HLSL values: HitObjectRecordEmpty (an object that records no intersection:
//   IsEmpty() is true) and HitObjectRecordMiss (a miss: the object records the
//   ray and the miss shader index). Everything else reads such an object.
// - OpHitObjectRecordFromQueryEXT (5304), which turns a RayQuery into a hit
//   object, needs an operand of storage class HitObjectAttributeEXT (5411) for
//   the hit attributes. HLSL has no syntax for a variable in that storage class,
//   so it is not exposed yet rather than faked with a Function-storage stand-in
//   that SPIRV-Tools rejects ("Hit Object Attributes id must be a OpVariable of
//   storage class HitObjectAttributeEXT").
// - OpHitObjectTraceRayEXT (5316) and the three *ReorderExecute* instructions
//   (5310-5312) trace the ray themselves and need a payload variable in storage
//   class RayPayloadKHR. The only instruction that creates such a variable today
//   is the HLSL TraceRay intrinsic (SpirvEmitter::processTraceRay), which builds
//   it from its own payload argument; a [[vk::ext_instruction]] declaration
//   would pass an ordinary Function-storage variable and be rejected ("payload
//   must be a OpVariable of storage class RayPayloadKHR or
//   IncomingRayPayloadKHR"). Tracing into a hit object, and therefore obtaining
//   a *hit* (as opposed to miss or empty) hit object, is the documented
//   construction gap of this header.
// - OpHitObjectGetIntersectionTriangleVertexPositionsEXT (5307) returns a
//   three-element array of float3 and additionally requires the
//   RayTracingPositionFetchKHR capability; an array-returning accessor is a
//   separate change.
// - The motion-blur variants (5317 OpHitObjectTraceRayMotionEXT, 5306
//   OpHitObjectRecordMissMotionEXT, 5312 ...TraceMotionReorderExecuteEXT) are
//   not exposed, but OpHitObjectGetCurrentTimeEXT (5320) is: it is the one
//   accessor a shader can use on a hit object it already holds. It additionally
//   requires the RayTracingMotionBlurNV capability and therefore the
//   SPV_NV_ray_tracing_motion_blur extension, which SPIR-V CodeGen requests from
//   that instruction on top of SPV_EXT_shader_invocation_reorder; a shader that
//   calls it has to enable both extensions.
// - OpHitObjectGetClusterIdNV (5346) is *not* provided here. The vendored
//   validator requires its hit object operand to be a pointer to
//   OpTypeHitObjectNV (ValidateHitObjectPointer: "Type must be
//   OpTypeHitObjectNV"), i.e. the type of the NV extension, and rejects the
//   EXT type this header declares; reading a cluster ID from an EXT hit object
//   would therefore be an invalid module.
//
// Requirements and restrictions, all diagnosed rather than miscompiled:
// - Ray tracing stages only, and reorder is narrower than that:
//   OpReorderThread*EXT requires the RayGenerationKHR execution model, the
//   accessors accept RayGenerationKHR, ClosestHitKHR and MissKHR. Both rules are
//   enforced while the call is lowered, so a compute or pixel shader that uses
//   this header is a compile error instead of a module SPIRV-Tools rejects
//   ("... requires RayGenerationKHR execution model").
// - A hit object that nothing has recorded into holds no defined value. Using
//   one is also a compile error, but only for a local variable of the current
//   function: an object that arrives through a parameter or through a struct
//   member cannot be tracked here. A recording instruction, an assignment from
//   another object, a declaration with an initializer, and a call that hands the
//   object to a user-defined function all count as giving it a value. Note that
//   such a function only modifies the caller's object when its parameter is
//   inout - a by-value HitObject parameter receives a copy, which is the object
//   the callee then records into.
// - The extension is opt-in: without
//   -fspv-extension=SPV_EXT_shader_invocation_reorder every call is a compile
//   error.
// - OpHitObjectGetCurrentTimeEXT additionally needs
//   -fspv-extension=SPV_NV_ray_tracing_motion_blur (see above).
//
// Required from the host - the compiler cannot check any of this:
// - the VK_EXT_ray_tracing_invocation_reorder device extension and its
//   rayTracingInvocationReorder feature bit,
// - VK_KHR_ray_tracing_pipeline (the only pipeline that can run the three
//   execution models above),
// - for HitObjectGetCurrentTime: the VK_NV_ray_tracing_motion_blur device
//   extension and its rayTracingMotionBlur feature bit,
// - a ray tracing pipeline (the reorder has no pipeline or host call of its own),
//   and the reorder mode the extension's properties struct reports. The hint the
//   shader passes is a request: an implementation may reorder differently than
//   the shader intended, or not at all, so a shader must not depend on the order
//   its invocations run in after the call.
//
// See docs/SPIR-V.rst ("Invocation reordering") and
// examples/spirv-extensions/ext-invocation-reorder.hlsl.
#ifndef _HLSL_VK_EXT_INVOCATION_REORDER_H_
#define _HLSL_VK_EXT_INVOCATION_REORDER_H_

namespace vk {
namespace ext {
// A hit object: the value that records one ray and the intersection it found.
// Lowers to OpTypeHitObjectEXT (5313), an opaque type with no operands and no
// result type, i.e. the same shape as OpTypeRayQueryKHR. A shader declares one
// as a local variable and passes it to the instructions below by reference.
// It is an ordinary HLSL value otherwise: `ho1 = ho2` and
// `vk::ext::HitObject ho2 = ho1` are accepted and encode as OpLoad/OpStore of the
// opaque type, and an object can be a member of a Function-storage struct (the
// member access becomes an OpAccessChain that still yields a pointer to it).
using HitObject = vk::SpirvOpaqueType</* OpTypeHitObjectEXT */ 5313>;

// Records an empty hit object: one that records no intersection at all.
// Lowers to OpHitObjectRecordEmptyEXT (IdRef Hit Object), no result:
//   OpHitObjectRecordEmptyEXT %ho
// IsEmpty() is true afterwards, IsHit() and IsMiss() are false, and the
// intersection accessors (GetHitKind, GetInstanceId, ...) have no defined value
// until the object is recorded into again.
[[vk::ext_instruction(/* OpHitObjectRecordEmptyEXT */ 5318)]] void
HitObjectRecordEmpty([[vk::ext_reference]] HitObject hitObject);

// Records a miss: the ray described by (origin, tMin, direction, tMax) travels
// through the scene without hitting anything, and the traversal continues in
// the miss shader with index missIndex, which also receives rayFlags.
// Lowers to OpHitObjectRecordMissEXT (5305, IdRef Hit Object, IdRef Ray Flags,
// IdRef Miss Index, IdRef Ray Origin, IdRef Ray TMin, IdRef Ray Direction,
// IdRef Ray TMax), no result. IsMiss() is true afterwards and the ray accessors
// (GetRayFlags, GetRayTMin/GetRayTMax, GetWorldRayOrigin, ...) are defined.
[[vk::ext_instruction(/* OpHitObjectRecordMissEXT */ 5305)]] void
HitObjectRecordMiss([[vk::ext_reference]] HitObject hitObject, uint rayFlags,
                    uint missIndex, float3 origin, float tMin, float3 direction,
                    float tMax);

// The ray flags the hit object was recorded with (the rayFlags argument of
// HitObjectRecordMiss). Lowers to OpHitObjectGetRayFlagsEXT (5308, IdRef Hit
// Object), 32-bit integer result.
[[vk::ext_instruction(/* OpHitObjectGetRayFlagsEXT */ 5308)]] uint
HitObjectGetRayFlags([[vk::ext_reference]] HitObject hitObject);

// The origin of the ray as the object sees it, i.e. in object space, and in
// world space. Lower to OpHitObjectGetObjectRayOriginEXT (5327) /
// OpHitObjectGetWorldRayOriginEXT (5330) and their direction counterparts
// (5328 / 5329), 3-component float results.
[[vk::ext_instruction(/* OpHitObjectGetObjectRayOriginEXT */ 5327)]] float3
HitObjectGetObjectRayOrigin([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpHitObjectGetObjectRayDirectionEXT */ 5328)]] float3
HitObjectGetObjectRayDirection([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpHitObjectGetWorldRayOriginEXT */ 5330)]] float3
HitObjectGetWorldRayOrigin([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpHitObjectGetWorldRayDirectionEXT */ 5329)]] float3
HitObjectGetWorldRayDirection([[vk::ext_reference]] HitObject hitObject);

// The ray t interval of the recorded ray. Lower to OpHitObjectGetRayTMinEXT
// (5347) / OpHitObjectGetRayTMaxEXT (5333), 32-bit float results.
[[vk::ext_instruction(/* OpHitObjectGetRayTMinEXT */ 5347)]] float
HitObjectGetRayTMin([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpHitObjectGetRayTMaxEXT */ 5333)]] float
HitObjectGetRayTMax([[vk::ext_reference]] HitObject hitObject);

// The object-to-world and world-to-object transforms of the instance that was
// hit, as a 3-row, 4-column affine matrix. Lower to
// OpHitObjectGetObjectToWorldEXT (5331) / OpHitObjectGetWorldToObjectEXT (5332).
// SPIRV-Tools fixes the encoding of the result: "expected Result Type matrix to
// have a Column Count of 4" and "expected Result Type matrix to have a Column
// Type of 3-component 32-bit float vectors", i.e. OpTypeMatrix with four
// %v3float columns, which is what the SPIR-V backend emits for float4x3 (HLSL
// rows become SPIR-V columns). Use them the way DXR uses ObjectToWorld3x4() /
// WorldToObject3x4(); both are undefined unless the object recorded an
// intersection (not an empty and not a miss object).
[[vk::ext_instruction(/* OpHitObjectGetObjectToWorldEXT */ 5331)]] float4x3
HitObjectGetObjectToWorld([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpHitObjectGetWorldToObjectEXT */ 5332)]] float4x3
HitObjectGetWorldToObject([[vk::ext_reference]] HitObject hitObject);

// The intersection the object recorded. Lower to OpHitObjectGetHitKindEXT
// (5322), OpHitObjectGetPrimitiveIndexEXT (5323),
// OpHitObjectGetGeometryIndexEXT (5324), OpHitObjectGetInstanceIdEXT (5325) and
// OpHitObjectGetInstanceCustomIndexEXT (5326), 32-bit integer results. They are
// only defined for an object that recorded an intersection.
[[vk::ext_instruction(/* OpHitObjectGetHitKindEXT */ 5322)]] uint
HitObjectGetHitKind([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpHitObjectGetPrimitiveIndexEXT */ 5323)]] uint
HitObjectGetPrimitiveIndex([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpHitObjectGetGeometryIndexEXT */ 5324)]] uint
HitObjectGetGeometryIndex([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpHitObjectGetInstanceIdEXT */ 5325)]] uint
HitObjectGetInstanceId([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpHitObjectGetInstanceCustomIndexEXT */ 5326)]] uint
HitObjectGetInstanceCustomIndex([[vk::ext_reference]] HitObject hitObject);

// The shader binding table record the object's traversal resolved to, and the
// shader record buffer handle of that record. Lower to
// OpHitObjectGetShaderBindingTableRecordIndexEXT (5348), a 32-bit integer
// result, and OpHitObjectGetShaderRecordBufferHandleEXT (5349), a 2-component
// integer vector result.
[[vk::ext_instruction(
    /* OpHitObjectGetShaderBindingTableRecordIndexEXT */ 5348)]] uint
HitObjectGetShaderBindingTableRecordIndex(
    [[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(
    /* OpHitObjectGetShaderRecordBufferHandleEXT */ 5349)]] uint2
HitObjectGetShaderRecordBufferHandle(
    [[vk::ext_reference]] HitObject hitObject);

// Overrides the shader binding table record index the object will be traced
// with, which is how a shader picks a different hit group for a reordered
// traversal. Lowers to OpHitObjectSetShaderBindingTableRecordIndexEXT (5309,
// IdRef Hit Object, IdRef SBT Record Index), no result.
[[vk::ext_instruction(
    /* OpHitObjectSetShaderBindingTableRecordIndexEXT */ 5309)]] void
HitObjectSetShaderBindingTableRecordIndex(
    [[vk::ext_reference]] HitObject hitObject, uint sbtRecordIndex);

// The state of the object. Lower to OpHitObjectIsEmptyEXT (5350),
// OpHitObjectIsHitEXT (5351) and OpHitObjectIsMissEXT (5352), bool results.
// They are mutually exclusive: IsMiss() is true for an object recorded by
// HitObjectRecordMiss, IsEmpty() for one recorded by HitObjectRecordEmpty, and
// IsHit() for an object that recorded an intersection, which this header cannot
// construct yet (see the note at the top).
[[vk::ext_instruction(/* OpHitObjectIsEmptyEXT */ 5350)]] bool
HitObjectIsEmpty([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpHitObjectIsHitEXT */ 5351)]] bool
HitObjectIsHit([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpHitObjectIsMissEXT */ 5352)]] bool
HitObjectIsMiss([[vk::ext_reference]] HitObject hitObject);

// The current time of the object's ray, in the same units as the ray time of a
// motion-blurred trace. Lowers to OpHitObjectGetCurrentTimeEXT (5320), a
// 32-bit float result.
//
// This is the one accessor that needs a second extension: SPIRV-Tools requires
// the RayTracingMotionBlurNV capability for it ("<op>: requires
// RayTracingMotionBlurNV capability"), so SPIR-V CodeGen emits that capability
// and OpExtension "SPV_NV_ray_tracing_motion_blur" on top of
// SPV_EXT_shader_invocation_reorder and a shader that calls it has to pass
// -fspv-extension=SPV_NV_ray_tracing_motion_blur as well.
[[vk::ext_instruction(/* OpHitObjectGetCurrentTimeEXT */ 5320)]] float
HitObjectGetCurrentTime([[vk::ext_reference]] HitObject hitObject);

// Reorders this invocation without a hit object: the implementation groups the
// invocations of the wave that pass a similar hint. Lowers to
// OpReorderThreadWithHintEXT (5314, IdRef Hint, IdRef Bits), no result:
//   OpReorderThreadWithHintEXT %uint_hint %uint_bits
// Both operands are 32-bit integers; the hint is the value the shader asks the
// implementation to sort by, and bits is the mask of hint bits the shader
// actually uses. SPIRV-Tools only checks the operand types, so the meaning of
// the pair is the driver's business.
//
// Unlike the DXIL ReorderThread intrinsic, this is an ordinary instruction in
// SPIR-V, not a block terminator: the block continues after it and the
// instructions that follow are part of the reordered invocation.
[[vk::ext_instruction(/* OpReorderThreadWithHintEXT */ 5314)]] void
ReorderThread(uint hint, uint bits);

// Reorders this invocation by the hit object it holds. Lowers to
// OpReorderThreadWithHitObjectEXT (5315, IdRef Hit Object, IdRef Hint?,
// IdRef Bits?), no result:
//   OpReorderThreadWithHitObjectEXT %ho
//   OpReorderThreadWithHitObjectEXT %ho %uint_hint %uint_bits
// The two optional operands are both-or-neither (SPIRV-Tools: "Hint and Bits are
// optional together"), which is why the header declares one overload without
// them and one with both.
[[vk::ext_instruction(/* OpReorderThreadWithHitObjectEXT */ 5315)]] void
ReorderThread([[vk::ext_reference]] HitObject hitObject);

[[vk::ext_instruction(/* OpReorderThreadWithHitObjectEXT */ 5315)]] void
ReorderThread([[vk::ext_reference]] HitObject hitObject, uint hint, uint bits);
} // namespace ext
} // namespace vk

#endif // _HLSL_VK_EXT_INVOCATION_REORDER_H_
