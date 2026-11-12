// RUN: not %dxc -T ps_6_0 -E main -fcgl -fspv-target-env=vulkan1.1 -fspv-extension=SPV_EXT_long_vector %s -spirv 2>&1 | FileCheck %s

// L4 gate: a long vector cannot be a stage input or output.
//
// SPV_EXT_long_vector lists the storage classes long vectors may be allocated
// in: Function, Private, UniformConstant, Uniform, Workgroup, StorageBuffer,
// PhysicalStorageBuffer, PushConstant, ShaderRecordBufferKHR, CrossWorkgroup and
// Generic. Input and Output are not among them, so
//
//   %in_var_COLOR0 = OpVariable %_ptr_Input_spirvIntrinsicType Input
//
// is invalid SPIR-V, and SPIRV-Tools says so:
//   [VUID-StandaloneSpirv-Type-12297] Long vector types with more than 4
//   components (or types containing them) not supported in storage class Input
//
// DXC diagnoses it instead of emitting that module. The check lives in
// CapabilityVisitor::addCapabilityForType, because the storage class a type is
// used in is only known there (visitInstruction passes the instruction's storage
// class down), and it is reported once per compile even though a stage variable's
// type is reachable from several instructions.
//
// The workaround for a shader that has a long vector it wants to hand to the next
// stage is to keep the value in Function/Private storage and write it out through
// ordinary vectors, or through a buffer in Uniform/StorageBuffer storage.

#include <vk/ext/long_vector.h>

// CHECK: error: a long vector (vk::ext::LongVector) cannot be used as stage input or output
float4 main(vk::ext::LongVector<float, 8> v : COLOR0) : SV_Target {
  return float4(vk::ext::Get<0>(v), 1, 2, 3);
}
