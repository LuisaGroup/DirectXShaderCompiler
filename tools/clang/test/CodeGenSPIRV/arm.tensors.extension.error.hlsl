// RUN: %dxc -T cs_6_0 -E main -fcgl -HV 2021 -fspv-extension=SPV_ARM_tensors %s -spirv | FileCheck %s --check-prefix=NAMED
// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 -fspv-extension=SPV_KHR_8bit_storage %s -spirv 2>&1 | FileCheck %s --check-prefix=NOTLISTED
// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 -fspv-extension=SPV_NOT_A_REAL_EXTENSION %s -spirv 2>&1 | FileCheck %s --check-prefix=LISTED

// L4/L7 gates: SPV_ARM_tensors is a registered extension, and an explicit
// -fspv-extension list is an allow-list that can refuse it.
//
// SPV_ARM_tensors is enabled by default (see enabledByDefault() in
// FeatureManager.cpp), for two reasons. First, the tensor type already ships:
// <vk/arm/tosa.h> declares every TOSA operation over OpTypeTensorARM and those
// declarations request TensorsARM themselves, so making the extension opt-in
// would turn every existing TOSA shader - which passes no -fspv-extension - into
// the NOTLISTED diagnostic below. Second, an explicit list stays an allow-list:
// leaving the extension out of it is an error, naming it in it is accepted, and
// it is listed by the "known extensions are" note, which is what registration
// buys.
//
// The three RUN lines are the whole contract:
//
//  NAMED     - naming the extension is accepted (it used to be "unknown SPIR-V
//              extension 'SPV_ARM_tensors'") and the module still carries the
//              capability and the extension exactly once;
//  NOTLISTED - a list that does not name it refuses every use with the exact
//              diagnostic, so the module never declares an extension the host
//              did not ask for;
//  LISTED    - the extension appears in the list of known extensions that the
//              -fspv-extension diagnostic prints.

#include <vk/arm/tensors.h>

RWByteAddressBuffer outBuf : register(u0);

// NAMED: OpCapability TensorsARM
// NAMED-NOT: OpCapability TensorsARM
// NAMED: OpExtension "SPV_ARM_tensors"
// NAMED-NOT: OpExtension "SPV_ARM_tensors"

// NOTLISTED: error: SPIR-V extension 'SPV_ARM_tensors' required for tensor types but not permitted to use
// NOTLISTED-NOT: OpCapability TensorsARM

// LISTED: note: known extensions are
// LISTED-DAG: SPV_ARM_tensors
// LISTED-DAG: SPV_KHR_8bit_storage

[numthreads(1, 1, 1)] void main() {
  vk::arm::Tensor<float, 2> t;
  vk::arm::Coordinates<2> c = vk::arm::MakeCoordinates(0, 1);
  outBuf.Store(0, asuint(vk::arm::TensorRead(t, c)));
}
