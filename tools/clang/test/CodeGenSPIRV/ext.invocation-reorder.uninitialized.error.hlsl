// RUN: not %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_EXT_shader_invocation_reorder %s 2>&1 | FileCheck %s
//
// A hit object holds no value until something records into it (F24/L4).
//
// This is the diagnostic that guards the construction gap documented in
// <vk/ext/invocation_reorder.h>: the only constructions this landing provides
// are HitObjectRecordEmpty and HitObjectRecordMiss, because tracing into a hit
// object needs a payload variable the front end cannot declare yet. A shader
// that declares an object and reads it without recording into it would get an
// undefined value for every accessor (the instructions are legal SPIR-V either
// way, so the validator cannot help), so the emitter tracks which local objects
// acquire a value and refuses the read.
//
// What counts as acquiring a value is deliberately generous, so that no
// legitimate shader is rejected: a recording instruction, an assignment from
// another object, a declaration with an initializer, and passing the object to a
// user-defined function (which receives it by pointer and may record into it).
// Those four accepted forms are the subject of ext.invocation-reorder.copy.hlsl;
// this file only pins the diagnostic for the object that has none of them.
//
// The tracking is per function and flow-insensitive, and it only covers local
// variables of the function being translated: an object that arrives through a
// parameter or through a struct member cannot be tracked here and is not
// diagnosed.
#include <vk/ext/invocation_reorder.h>

RWStructuredBuffer<uint> Out : register(u0);

[shader("raygeneration")]
void main() {
  vk::ext::HitObject unrecorded;
  // CHECK: error: hit object 'unrecorded' is used before any instruction recorded it: a vk::ext::HitObject holds no defined value until vk::ext::HitObjectRecordEmpty or vk::ext::HitObjectRecordMiss has been called on it
  Out[0] = vk::ext::HitObjectGetRayFlags(unrecorded);
  // The same object is fine once it has been recorded into.
  vk::ext::HitObjectRecordEmpty(unrecorded);
  Out[1] = vk::ext::HitObjectGetRayFlags(unrecorded);
  // A second object is a second decision: recording into one says nothing about
  // the other.
  vk::ext::HitObject alsoUnrecorded;
  // CHECK: error: hit object 'alsoUnrecorded' is used before any instruction recorded it: a vk::ext::HitObject holds no defined value until vk::ext::HitObjectRecordEmpty or vk::ext::HitObjectRecordMiss has been called on it
  vk::ext::ReorderThread(alsoUnrecorded);
}

// The other half of the rule - which ways of giving an object a value are
// accepted - is a positive test: ext.invocation-reorder.copy.hlsl.
