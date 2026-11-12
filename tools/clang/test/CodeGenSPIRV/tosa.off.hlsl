// RUN: %dxc -T cs_6_0 -E main -fcgl %s -spirv | FileCheck %s

// L5 off-path regression for the TOSA.001000.1 extended instruction set.
//
// <vk/arm/tosa.h> only declares templates, enumerators and
// [[vk::ext_instruction]] prototypes, so including it adds nothing to a module
// that does not call one of them: no OpExtInstImport "TOSA.001000.1", no
// OpCapability TensorsARM, no OpExtension "SPV_ARM_tensors", no OpTypeTensorARM
// and no TOSA instruction.
//
// The import in particular is emitted lazily, by SpirvBuilder::getExtInstSet, the
// first time an instruction that names the set is built. That is not incidental:
// every module that includes this header would otherwise gain a dead import and a
// dead capability, and - because OpTypeTensorARM requires TensorsARM - a module
// that merely mentioned the header could not be created on a device without the
// Arm tensor model. The include-plus-ordinary-HLSL case has to stay byte for byte
// the module it was before this header existed.
//
// Note that no command-line flag appears on the RUN line: unlike a Vulkan
// extension, TOSA cannot be selected or refused, because there is nothing to
// select - the set name in the import string is the whole contract.
//
// The CHECK-NOT regions are anchored between the lines that bound them, so they
// cover the capability block, the extension block, the import block and the type
// block, instead of being vacuous end-of-file assertions.

#include <vk/arm/tosa.h>

// The enumerator the header declares is a plain integer value, so naming it here
// has to stay a compile-time constant and not become an instruction.
static const vk::arm::tosa::NanMode g_mode = vk::arm::tosa::NanModeIgnore;

RWStructuredBuffer<float> g_in : register(u0);
RWStructuredBuffer<float> g_out : register(u1);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // CHECK: OpCapability Shader
  // CHECK-NOT: OpCapability TensorsARM
  // CHECK: OpExtension "{{SPV_[A-Za-z0-9_]+}}"
  // CHECK-NOT: OpExtension "SPV_ARM_tensors"
  // CHECK-NOT: OpExtInstImport
  // CHECK: OpMemoryModel Logical GLSL450
  // CHECK: OpEntryPoint GLCompute
  // CHECK-NOT: OpTypeTensorARM

  // The near miss this pins is the ordinary float the module already carries: a
  // tensor of float and a float differ only by the OpTypeTensorARM wrapper, so the
  // absence of the wrapper - not the absence of the element type - is the signal.
  g_out[tid.x] = g_in[tid.x] * (g_mode == vk::arm::tosa::NanModeIgnore ? 2.0 : 1.0);

  // CHECK: OpStore
  // CHECK-NOT: OpTypeTensorARM
  // CHECK-NOT: OpExtInstImport
}
