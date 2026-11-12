// RUN: not %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_KHR_shader_clock %s 2>&1 | FileCheck %s
// SPV_EXT_cooperative_matrix_maintenance1: the extension is an allow-list entry,
// not an always-on switch (G16/L4, L7).
//
// The extension is enabled by default, so a shader that uses the maintenance1
// entry points needs no flag. But -fspv-extension= is an allow-list as soon as it
// is given at all: this file lists an unrelated extension, so
// SPV_EXT_cooperative_matrix_maintenance1 is *not* enabled and the module would
// not be allowed to declare CooperativeMatrixGetCoordinateEXT (5438) - the
// capability is what makes the instruction legal, so emitting it without the
// capability produces a module SPIRV-Tools rejects. DXC reports the entry point
// instead. CapabilityVisitor does the same for
// OpCooperativeMatrixConvertUseEXT, and the emitter does it for the two
// instructions that need a synthesized function reference, with
// "requires the SPV_EXT_cooperative_matrix_maintenance1 extension".
//
// Note the exact wording: "required for <opcode> but not permitted to use" is
// FeatureManager::requestExtension's message, so this also pins that
// SPV_EXT_cooperative_matrix_maintenance1 is registered (an unregistered name
// would have been rejected earlier, as "unknown SPIR-V extension").
// CHECK: error: SPIR-V extension 'SPV_EXT_cooperative_matrix_maintenance1' required for OpCooperativeMatrixGetCoordinateEXT but not permitted to use
#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<int> outbuf;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  using Acc = vk::khr::CooperativeMatrixAccumulator<int, vk::ScopeSubgroup, 16, 16>;

  Acc acc = Acc::Splat(1);
  uint2 coordinate = acc.GetCoordinate(tid.x);
  outbuf[0] = coordinate.x + coordinate.y;
}
