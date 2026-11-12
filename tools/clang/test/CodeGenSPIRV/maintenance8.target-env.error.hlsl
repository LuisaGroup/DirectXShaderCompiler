// RUN: not %dxc -T ps_6_0 -E main -fcgl -spirv -fspv-extension=SPV_KHR_maintenance8 %s 2>&1 | FileCheck %s --check-prefix=EXTENSION
// RUN: not %dxc -T ps_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.4 %s 2>&1 | FileCheck %s --check-prefix=TARGETENV

// G31/L4: the boundary of the feature, stated as two refusals.
//
// VK_KHR_maintenance8 has no SPIR-V equivalent to name. It is a Vulkan *device
// extension* whose Shader SPIR-V effect is a change to the rules of the Vulkan
// SPIR-V *environment*, adopted through the
// VkPhysicalDeviceMaintenance8FeaturesKHR::maintenance8 feature bit; it adds no
// instruction, no capability and no module-level extension string. Checked
// against the vendored grammar (external/SPIRV-Headers, v2026.08.0) and against
// the Khronos SPIR-V registry: there is no SPV_KHR_maintenance8 and no
// SPV_KHR_maintenance* of any revision. The only "maintenance" names in the
// SPIR-V registry are SPV_EXT_cooperative_matrix_maintenance1.
//
// Consequently:
//  * -fspv-extension=SPV_KHR_maintenance8 must stay an "unknown SPIR-V
//    extension" error. Registering it would let a user request an extension
//    string that no driver recognises and that spirv-val reports as
//    "Found unrecognized extension", and there is no OpExtension to emit for it.
//  * -fspv-target-env=vulkan1.4 must stay an "unknown SPIR-V target environment"
//    error. The feature is legal on Vulkan 1.4 devices, but DXC's target-env
//    list stops at vulkan1.3 and this feature deliberately does not add
//    vulkan1.4: a target env states which SPIR-V version and validator rules the
//    module is generated for, and the maintenance8 relaxation is available to a
//    Vulkan 1.1/1.2/1.3 device that enables the extension, so it is not a
//    property of the target env at all. The rule is applied wherever DXC
//    generates the operand (see SpirvEmitter::spirvToolsValidate and
//    docs/SPIR-V.rst, "Dynamic image offsets and signed remainder").
//
// The positive half is every other maintenance8 test file in this directory.

// EXTENSION: error: unknown SPIR-V extension 'SPV_KHR_maintenance8'

// TARGETENV: error: unknown SPIR-V target environment 'vulkan1.4'

float4 main(int2 dynamicOffset : A) : SV_Target {
  return float4(dynamicOffset, 0, 1);
}
