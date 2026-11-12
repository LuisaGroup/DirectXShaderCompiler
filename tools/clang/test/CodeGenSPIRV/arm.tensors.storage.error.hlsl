// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 -DGLOBAL %s -spirv 2>&1 | FileCheck %s --check-prefix=GLOBAL
// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 -DSTRUCTURED %s -spirv 2>&1 | FileCheck %s --check-prefix=STRUCTURED
// RUN: not %dxc -T vs_6_0 -E main -fcgl -HV 2021 -DSTAGE_IO %s -spirv 2>&1 | FileCheck %s --check-prefix=STAGE_IO

// L4 gates: the two places a tensor type may not appear, both of which produce
// SPIR-V that SPIRV-Tools *accepts* - so a diagnostic here is the only thing
// between the shader and a module no Vulkan implementation can use.
//
//  GLOBAL      - an HLSL global of tensor type. The front end places it in
//                $Globals, an OpTypeStruct in Uniform storage, so the tensor
//                ends up as a member of a uniform block. SPIRV-Tools does not
//                check struct members for OpTypeTensorARM, so the module
//                validates and then cannot be bound: no descriptor matches a
//                tensor inside a uniform buffer. [vk::binding] on such a global
//                is refused earlier, with "variable 'x' will be placed in
//                $Globals so cannot have vk::binding attribute".
//  STRUCTURED  - an RWStructuredBuffer of tensor type, i.e. the same member in a
//                StorageBuffer block. Also accepted by SPIRV-Tools, also
//                unboundable.
//  STAGE_IO    - a tensor as a stage interface member. SPV_ARM_tensors makes a
//                tensor an opaque descriptor handle, which has no varying
//                encoding; SPIRV-Tools happens not to check the interface list
//                of an opaque type, so again only this diagnostic catches it.
//
// The storage classes that *are* reachable - Function (a loaded handle),
// Private and Workgroup - are left alone: a function-scope handle is what every
// use of the type goes through, and arm.tensors.hlsl compiles one.

#ifdef GLOBAL
#include <vk/arm/tensors.h>
vk::arm::Tensor<float, 2> gTensor;
// GLOBAL: error: a tensor (vk::arm::Tensor) cannot be a member of a uniform, storage buffer or push constant block
// GLOBAL-SAME: no host can bind a tensor to it
// GLOBAL-NOT: OpCapability TensorsARM
[numthreads(1, 1, 1)] void main() { }
#endif

#ifdef STRUCTURED
#include <vk/arm/tensors.h>
RWStructuredBuffer<vk::arm::Tensor<float, 2> > tensors;
// STRUCTURED: error: a tensor (vk::arm::Tensor) cannot be a member of a uniform, storage buffer or push constant block
// STRUCTURED-SAME: no host can bind a tensor to it
// STRUCTURED-NOT: OpCapability TensorsARM
[numthreads(1, 1, 1)] void main() { }
#endif

#ifdef STAGE_IO
#include <vk/arm/tensors.h>
struct Varyings {
  float4 position : SV_Position;
  vk::arm::Tensor<float, 2> tensor : TENSOR;
};
// STAGE_IO: error: a tensor (vk::arm::Tensor) cannot be used as stage input or output
// STAGE_IO-SAME: which has no varying encoding
// STAGE_IO-NOT: OpCapability TensorsARM
Varyings main() {
  Varyings v;
  v.position = 0;
  return v;
}
#endif
