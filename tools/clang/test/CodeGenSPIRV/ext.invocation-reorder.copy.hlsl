// RUN: %dxc -T lib_6_9 -E main -fcgl -spirv -fspv-target-env=vulkan1.2 -fspv-extension=SPV_KHR_ray_tracing -fspv-extension=SPV_EXT_shader_invocation_reorder %s | FileCheck %s
//
// Every way a hit object can acquire a value is accepted (F24/L0, F24/L2).
//
// The counterpart of ext.invocation-reorder.uninitialized.error.hlsl: that file
// pins the diagnostic for an object that nothing recorded into, and this one
// pins the four ways in which an object does get a value, none of which may be
// mistaken for the uninitialised case. They are the reason the emitter's
// initialisation tracking is deliberately generous - a legitimate shader must
// never be rejected for a copy.
//
// The encoding of a copy is OpLoad/OpStore of the opaque type:
//
//   %v = OpLoad %hitobject %src
//        OpStore %dst %v
//
// SPIRV-Tools accepts that (nothing in validate_ray_tracing_reorder.cpp forbids
// loading the type, and this file compiles without -Vd), which is what makes a
// hit object usable as an ordinary value in HLSL. Whether a driver gives it
// meaning is the driver's business; DXR's HitObject is a value type with the same
// shape, so an assignment is expected to carry the whole object over.
#include <vk/ext/invocation_reorder.h>

RWStructuredBuffer<uint> Out : register(u0);

// Passing an object to a user-defined function hands the pointer over when the
// parameter is `inout`, so the callee records into the caller's object and the
// call itself marks the object as recorded (`inout` matters: a by-value
// parameter receives a copy, and the callee's recording would then be lost).
void recordInto(inout vk::ext::HitObject hitObject) {
  vk::ext::HitObjectRecordEmpty(hitObject);
}

[shader("raygeneration")]
void main() {
  // 1. A recording instruction.
  vk::ext::HitObject source;
  vk::ext::HitObjectRecordEmpty(source);
  Out[0] = vk::ext::HitObjectGetRayFlags(source);
  // 2. An assignment from another object.
  vk::ext::HitObject assigned;
  assigned = source;
  Out[1] = vk::ext::HitObjectGetRayFlags(assigned);
  // 3. A declaration with an initializer.
  vk::ext::HitObject initialized = source;
  Out[2] = vk::ext::HitObjectGetRayFlags(initialized);
  // 4. A call that hands the object to a user-defined function.
  vk::ext::HitObject throughHelper;
  recordInto(throughHelper);
  Out[3] = vk::ext::HitObjectGetRayFlags(throughHelper);
}

// One opaque type for every object, and one Function variable each. There is no
// OpTypeStruct and no other type: a copy is a load and a store of the opaque
// type, and a call passes the variable itself.
// CHECK-DAG:  [[TYPE:%[0-9A-Za-z_]+]] = OpTypeHitObjectEXT
// CHECK-NOT:  OpTypeHitObjectEXT
// CHECK:      %src_main = OpFunction
// CHECK-DAG:  [[SOURCE:%[0-9A-Za-z_]+]] = OpVariable %{{[0-9A-Za-z_]+}} Function
// CHECK-DAG:  [[ASSIGNED:%[0-9A-Za-z_]+]] = OpVariable %{{[0-9A-Za-z_]+}} Function
// CHECK-DAG:  [[INITIALIZED:%[0-9A-Za-z_]+]] = OpVariable %{{[0-9A-Za-z_]+}} Function
// CHECK-DAG:  [[HELPERARG:%[0-9A-Za-z_]+]] = OpVariable %{{[0-9A-Za-z_]+}} Function
// 1. The source object, recorded into and then read.
// CHECK:      OpHitObjectRecordEmptyEXT [[SOURCE]]
// CHECK:      OpHitObjectGetRayFlagsEXT %uint [[SOURCE]]
// 2. The assignment: an OpLoad of the source and an OpStore into the target,
// which is what carries the object over.
// CHECK:      [[COPY:%[0-9A-Za-z_]+]] = OpLoad [[TYPE]] [[SOURCE]]
// CHECK:      OpStore [[ASSIGNED]] [[COPY]]
// CHECK:      OpHitObjectGetRayFlagsEXT %uint [[ASSIGNED]]
// 3. The declaration with an initializer is the same load/store pair into a
// third variable, and reading it is not the uninitialised case either.
// CHECK:      [[COPY2:%[0-9A-Za-z_]+]] = OpLoad [[TYPE]] [[SOURCE]]
// CHECK:      OpStore [[INITIALIZED]] [[COPY2]]
// CHECK:      OpHitObjectGetRayFlagsEXT %uint [[INITIALIZED]]
// 4. The helper call passes the variable itself - no temporary - and the callee
// records into the caller's object through its own parameter, which is why the
// emitter treats the call as recording.
// CHECK:      OpFunctionCall %void [[HELPER:%[0-9A-Za-z_]+]] [[HELPERARG]]
// CHECK:      OpHitObjectGetRayFlagsEXT %uint [[HELPERARG]]
// The helper body: an OpFunctionParameter of the hit object pointer type and the
// recording instruction on it.
// CHECK:      [[HELPER]] = OpFunction
// CHECK:      [[PARAM:%[0-9A-Za-z_]+]] = OpFunctionParameter %{{[0-9A-Za-z_]+}}
// CHECK:      OpHitObjectRecordEmptyEXT [[PARAM]]
// CHECK:      OpFunctionEnd
