// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_vector -DCONSTANT_OPERAND %s -spirv 2>&1 | FileCheck %s --check-prefix=CONSTANT
// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_vector -DCOMPONENT_TYPE %s -spirv 2>&1 | FileCheck %s --check-prefix=COMPONENT
// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_vector -DSTORAGE_CLASS %s -spirv 2>&1 | FileCheck %s --check-prefix=STORAGE
// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_vector -DSCALAR_ARGUMENT %s -spirv 2>&1 | FileCheck %s --check-prefix=ARRAY

// L4 gates for the restrictions SPV_NV_cooperative_vector places on a shader
// that uses <vk/nv/cooperative_vector.h>. Each RUN line compiles the same file
// with one -D switch, so one behaviour is pinned per check prefix.
//
// CONSTANT_OPERAND - a run-time memory layout. SPV_NV_cooperative_vector requires
// InputInterpretation, MatrixInterpretation, BiasInterpretation, M, K,
// MemoryLayout and Transpose to name a *constant instruction* ("<op> <operand>
// <id> is not a constant instruction" in SPIRV-Tools). The entry points in the
// header take them as ordinary parameters - one parameter per SPIR-V operand is
// the only shape a declaration-only [[vk::ext_instruction]] can have - so the
// requirement is enforced by SPIR-V CodeGen rather than by the type system. A
// layout that is read from a buffer is the "runtime layout conversion" the
// extension cannot encode, and that is what this RUN line asks for.
//
// COMPONENT_TYPE - a double component. SPIRV-Tools only accepts a 32-bit integer
// or a 16/32-bit float component of a cooperative vector, so the type is
// rejected before it can reach the module. This is also the diagnostic that
// covers a cooperative vector that is only declared and never used, because it
// comes from the type (CapabilityVisitor::addCapabilityForType) and not from an
// instruction. A wrong component type in a *call* is additionally caught by the
// header's ComponentTypeIsSupported<> default template argument, which reports
// "no matching function" instead.
//
// STORAGE_CLASS - a groupshared cooperative vector. SPV_NV_cooperative_vector
// allows the type in Function or Private storage and as a function parameter,
// and nowhere else; SPIRV-Tools rejects the module with "Cooperative vector types
// (or types containing them) can only be allocated in Function or Private storage
// classes or as function parameters". The matrix, bias and accumulator operands
// of the instructions are ordinary arrays in Workgroup memory - that is what the
// pointer operands address - but the vector itself may not live there.
//
// SCALAR_ARGUMENT - a pointer operand that addresses a single component instead
// of an array. The instruction requires a pointer to an array, so the header's
// PointerMustPointToArray<> diagnostic stops this before any SPIR-V is produced.
// This is the one diagnostic in this file that comes from the front end: HLSL has
// no static_assert before -HV 202x, so the headers in this tree report an
// unsupported combination by instantiating an undefined class template.
//
// Not covered here, by design: a *device* that does not implement the component
// type / layout combinations the shader names. Those are reported by
// vkGetPhysicalDeviceCooperativeVectorPropertiesNV at pipeline creation and are
// invisible to the compiler (docs/SPIR-V.rst).
#include <vk/nv/cooperative_vector.h>

groupshared uint g_matrix[64];
groupshared uint g_vector[16];
groupshared double g_dvector[16];
RWStructuredBuffer<uint> g_out : register(u0);

#if defined(STORAGE_CLASS)
// A cooperative vector may not be allocated in Workgroup storage.
groupshared vk::nv::CooperativeVector<float, 4> g_coopvec;
#endif

[numthreads(1, 1, 1)] void main(uint3 tid : SV_DispatchThreadID) {
#if defined(CONSTANT_OPERAND)
  vk::nv::CooperativeVector<uint, 4> v = vk::nv::Load<uint, 4>(g_vector, 0);
  // CONSTANT: error: the interpretation, M, K, MemoryLayout and Transpose operands of OpCooperativeVectorMatrixMulNV
  // CONSTANT-SAME: must be compile-time constants
  vk::nv::CooperativeVector<uint, 4> r = vk::nv::MatrixMul<uint, 4, 4>(
      v, vk::CooperativeVectorComponentTypeUnsignedInt32NV, g_matrix, 0,
      vk::CooperativeVectorComponentTypeUnsignedInt32NV, 4, 4,
      (vk::CooperativeVectorMatrixLayout)g_out[1], false, 16);
#endif

#if defined(COMPONENT_TYPE)
  // COMPONENT: error: the component type of a cooperative vector
  // COMPONENT-SAME: must be a 32-bit integer or a 16/32-bit float
  vk::nv::CooperativeVector<double, 4> bad;
#endif

#if defined(SCALAR_ARGUMENT)
  // ARRAY: error: no matching function for call to 'Load'
  // ARRAY: implicit instantiation of undefined template 'vk::nv::detail::PointerMustPointToArray<false>'
  vk::nv::CooperativeVector<uint, 4> v = vk::nv::Load<uint, 4>(g_vector[0], 0);
#endif

#if defined(STORAGE_CLASS)
  // STORAGE: error: a cooperative vector (vk::nv::CooperativeVector) can only be allocated in Function or Private storage
  g_coopvec = g_coopvec;
#endif

#if !defined(CONSTANT_OPERAND) && !defined(COMPONENT_TYPE) && !defined(SCALAR_ARGUMENT)
  // Nothing to do for the storage-class case: declaring the groupshared variable
  // above is the error.
#endif
  g_out[0] = tid.x;
}
