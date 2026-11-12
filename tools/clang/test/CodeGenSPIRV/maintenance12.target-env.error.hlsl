// RUN: not %dxc -T vs_6_0 -E main -fcgl -spirv -fspv-extension=SPV_KHR_maintenance12 %s 2>&1 | FileCheck %s --check-prefix=EXTENSION
// RUN: not %dxc -T vs_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.4 %s 2>&1 | FileCheck %s --check-prefix=TARGETENV

// G33/L4: the boundary of the feature, stated as two refusals.
//
// VK_KHR_maintenance12 has no SPIR-V equivalent to name. It is a Vulkan *device*
// extension whose only Shader SPIR-V effect is a permission - non-uniform indexing
// of values within a PushConstant-storage variable - and the module expresses that
// permission with the pre-existing NonUniform decoration. It adds no instruction,
// no capability and no module-level extension string. Checked against the vendored
// grammar (external/SPIRV-Headers, v2026.08.0): there is no SPV_KHR_maintenance12
// and no SPV_KHR_maintenance* of any revision; the only "maintenance" names in the
// SPIR-V registry are SPV_EXT_cooperative_matrix_maintenance1.
//
// Consequently:
//  * -fspv-extension=SPV_KHR_maintenance12 must stay an "unknown SPIR-V extension"
//    error. Registering it would let a user request an extension string that no
//    driver recognises and that spirv-val reports as "Found unrecognized
//    extension", and there is no OpExtension to emit for it.
//  * -fspv-target-env=vulkan1.4 must stay an "unknown SPIR-V target environment"
//    error. DXC's target-env list stops at vulkan1.3, and this feature
//    deliberately does not add vulkan1.4: a target env states which SPIR-V version
//    and validator rules the module is generated for, while the maintenance12
//    permission belongs to a device that enables the extension, so it is not a
//    property of the target env at all. The same decoration is emitted and
//    accepted for every -fspv-target-env DXC accepts (see
//    maintenance12.push-constant.nonuniform.hlsl, and the note in docs/SPIR-V.rst
//    that the shipped SPIRV-Tools has no NonUniform/push-constant rule to gate on).
//
// The positive half is every other maintenance12 test file in this directory.

// EXTENSION: error: unknown SPIR-V extension 'SPV_KHR_maintenance12'
// TARGETENV: error: unknown SPIR-V target environment 'vulkan1.4'

struct PushData {
  float4 values[8];
};

[[vk::push_constant]] PushData pc;

float4 main(uint index : ID) : SV_Position {
  return pc.values[NonUniformResourceIndex(index)];
}
