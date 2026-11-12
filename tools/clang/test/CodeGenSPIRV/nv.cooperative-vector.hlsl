// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_vector %s -spirv | FileCheck %s
// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-extension=SPV_NV_cooperative_vector %s -spirv | FileCheck %s --check-prefix=VULKAN10
// RUN: %dxc -T cs_6_2 -E half_main -enable-16bit-types -fcgl -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_vector %s -spirv | FileCheck %s --check-prefix=HALF

// L0/L1/L2 gates for VK_NV_cooperative_vector / SPV_NV_cooperative_vector.
//
// The surface is <vk/nv/cooperative_vector.h>: the cooperative vector type and
// the four inferencing operations (load, store, matrix-vector product and the
// accumulating product). The two training operations are pinned separately in
// nv.cooperative-vector.training.hlsl, because their capability is per
// instruction and this file has to prove its absence.
//
// L0 (surface reachability): every entry point is called by name below -
// vk::nv::Load, vk::nv::Store, vk::nv::MatrixMul and vk::nv::MatrixMulAdd, in
// both of the two forms each of them has (with and without the optional
// MemoryAccess / MatrixStride operand).
//
// L1 (capability and extension): the module declares exactly one
// OpCapability CooperativeVectorNV (5394) and exactly one
// OpExtension "SPV_NV_cooperative_vector", and no
// OpCapability CooperativeVectorTrainingNV (5435). Both are added by SPIR-V
// CodeGen - the capability from the OpTypeVectorIdEXT type
// (CapabilityVisitor::addCapabilityForType) and from each instruction
// (CapabilityVisitor::visitInstruction), the extension through the ordinary
// FeatureManager registration - and not by [[vk::ext_capability]] /
// [[vk::ext_extension]] on the header's declarations, which is what lets
// -fspv-extension select and refuse the extension
// (nv.cooperative-vector.extension.error.hlsl).
//
// L2 (instruction encoding): each instruction is asserted with its result type
// and every operand position captured, because a permuted operand list is the
// most expensive mistake here to find later - most permutations still validate.
//
// The second RUN line is the -fspv-target-env= statement for this feature, and
// it is a negative one: the vendored grammar (spirv.core.grammar.json) spells
// "version": "None" for OpTypeVectorIdEXT and for all six OpCooperativeVector*NV
// instructions, so SPV_NV_cooperative_vector carries no SPIR-V version
// requirement and there is nothing to gate. The default target environment
// (vulkan1.0, SPIR-V 1.0) produces the same instructions and the module still
// validates, which is what VULKAN10 checks. That is unlike
// <vk/ext/long_vector.h>, which is specified against SPIR-V 1.3
// (vk.long-vector.env.error.hlsl).
//
// The third RUN line proves where Float16 comes from: the component type of a
// cooperative vector is an *operand* of OpTypeVectorIdEXT, so the generic
// capability handling never sees it. CapabilityVisitor adds the capability of
// the component type explicitly, and a half component therefore emits
// OpCapability Float16 - with -enable-16bit-types, without which HLSL's half is
// a 32-bit float.
//
// What these gates cannot prove: numeric semantics. FileCheck pins the opcode
// and the operand list, not the arithmetic; the operands are asymmetric on
// purpose (%int_9 for the unsigned 32-bit interpretation against %int_1 for the
// float one, and offsets 0, 4, 8, 16 so that a swapped pair is visible), but no
// driver in CI implements the extension, so nothing here executes.
#include <vk/nv/cooperative_vector.h>

// One groupshared array per matrix, vector and accumulator: the pointer operands
// of the instructions have to address an array in the Workgroup storage class.
// The values themselves are opaque - there is no instruction that reads or
// writes a single component of a cooperative vector - so results are moved back
// to memory with vk::nv::Store.
groupshared uint g_matrix[64];
groupshared uint g_vector[16];
groupshared float g_fmatrix[64];
groupshared float g_fvector[16];
groupshared half g_hvector[16];
RWStructuredBuffer<uint> g_out : register(u0);

[numthreads(1, 1, 1)] void main(uint3 tid : SV_DispatchThreadID) {
  // L1: exactly one CooperativeVectorNV, exactly one OpExtension, and no
  // training capability. The CHECK-NOTs are anchored between the two lines that
  // bound the region they apply to.
  // CHECK: OpCapability Shader
  // CHECK: OpCapability CooperativeVectorNV
  // CHECK-NOT: OpCapability CooperativeVectorTrainingNV
  // CHECK-NOT: OpCapability CooperativeVectorNV
  // CHECK: OpExtension "SPV_NV_cooperative_vector"
  // CHECK-NOT: OpExtension "SPV_NV_cooperative_vector"
  // CHECK: OpMemoryModel Logical GLSL450

  // L2, the type: OpTypeVectorIdEXT (5288), whose Component Count is the id of a
  // 32-bit integer constant (%uint_4) and not a literal word. The grammar's alias
  // for the same instruction is OpTypeCooperativeVectorNV; the assembly does not
  // use that spelling, so a module that did would mean a second encoding.
  // CHECK: [[CVU:%[A-Za-z0-9_]+]] = OpTypeVectorIdEXT %uint %uint_4
  // CHECK-NOT: OpTypeCooperativeVectorNV
  // CHECK: [[CVF:%[A-Za-z0-9_]+]] = OpTypeVectorIdEXT %float %uint_4
  vk::nv::CooperativeVector<uint, 4> v = vk::nv::Load<uint, 4>(g_vector, 0);

  // L2, the load: (IdResultType, IdResult, Pointer, Offset, [MemoryAccess]). The
  // pointer stays the groupshared array itself - no OpAccessChain, no copy - and
  // the optional MemoryAccess operand follows the offset.
  // CHECK: OpCooperativeVectorLoadNV [[CVU]] %g_vector %uint_0
  // CHECK: OpCooperativeVectorLoadNV [[CVU]] %g_vector %uint_4 Volatile
  vk::nv::CooperativeVector<uint, 4> vw =
      vk::nv::Load<uint, 4>(g_vector, 4, vk::MemoryAccessVolatileMask);

  // L2, the store: (Pointer, Offset, Object, [MemoryAccess]) - no result type and
  // no result id, and the object comes last.
  // CHECK: OpCooperativeVectorStoreNV %g_vector %uint_0 %{{[A-Za-z0-9_]+}}
  // CHECK: OpCooperativeVectorStoreNV %g_vector %uint_8 %{{[A-Za-z0-9_]+}} Nontemporal
  vk::nv::Store<uint, 4>(g_vector, 0, v);
  vk::nv::Store<uint, 4>(g_vector, 8, vw, vk::MemoryAccessNontemporalMask);
  vk::nv::CooperativeVector<float, 4> fv = vk::nv::Load<float, 4>(g_fvector, 0);

  // L2, the matrix-vector product:
  //   %result = OpCooperativeVectorMatrixMulNV %type %input
  //       %inputInterpretation %matrix %matrixOffset %matrixInterpretation
  //       %M %K %memoryLayout %transpose %matrixStride
  // %int_9 is CooperativeVectorComponentTypeUnsignedInt32NV and %int_0 is
  // CooperativeVectorMatrixLayoutRowMajorNV; the interpretations and the layout
  // are <id>s of constant instructions, not literals, which is why they print as
  // %int_9 and not as 9.
  // CHECK: OpCooperativeVectorMatrixMulNV [[CVU]] %{{[A-Za-z0-9_]+}} %int_9 %g_matrix %uint_0 %int_9 %uint_4 %uint_4 %int_0 %false %uint_16
  vk::nv::CooperativeVector<uint, 4> rowMajor = vk::nv::MatrixMul<uint, 4, 4>(
      v, vk::CooperativeVectorComponentTypeUnsignedInt32NV, g_matrix, 0,
      vk::CooperativeVectorComponentTypeUnsignedInt32NV, 4, 4,
      vk::CooperativeVectorMatrixLayoutRowMajorNV, false, 16);

  // The InferencingOptimalNV layout leaves the stride to the device, so the
  // overload without that parameter has to omit the operand entirely: the line
  // ends after Transpose ({{$}} is the end of the line).
  // CHECK: OpCooperativeVectorMatrixMulNV [[CVU]] %{{[A-Za-z0-9_]+}} %int_9 %g_matrix %uint_0 %int_9 %uint_4 %uint_4 %int_2 %true{{$}}
  vk::nv::CooperativeVector<uint, 4> optimal = vk::nv::MatrixMul<uint, 4, 4>(
      v, vk::CooperativeVectorComponentTypeUnsignedInt32NV, g_matrix, 0,
      vk::CooperativeVectorComponentTypeUnsignedInt32NV, 4, 4,
      vk::CooperativeVectorMatrixLayoutInferencingOptimalNV, true);

  // A float result type and the float interpretation: the result type comes from
  // the template argument, the interpretation from the operand.
  // CHECK: OpCooperativeVectorMatrixMulNV [[CVF]] %{{[A-Za-z0-9_]+}} %int_1 %g_fmatrix %uint_0 %int_1 %uint_4 %uint_4 %int_1 %false %uint_16
  vk::nv::CooperativeVector<float, 4> fmul = vk::nv::MatrixMul<float, 4, 4>(
      fv, vk::CooperativeVectorComponentTypeFloat32NV, g_fmatrix, 0,
      vk::CooperativeVectorComponentTypeFloat32NV, 4, 4,
      vk::CooperativeVectorMatrixLayoutColumnMajorNV, false, 16);

  // L2, the accumulating product: the bias is a pointer plus an offset (and an
  // interpretation) in the middle of the operand list, not a cooperative vector
  // value at the end.
  // CHECK: OpCooperativeVectorMatrixMulAddNV [[CVU]] %{{[A-Za-z0-9_]+}} %int_9 %g_matrix %uint_0 %int_9 %g_matrix %uint_16 %int_9 %uint_4 %uint_4 %int_1 %false %uint_16
  vk::nv::CooperativeVector<uint, 4> accumulation =
      vk::nv::MatrixMulAdd<uint, 4, 4>(
          v, vk::CooperativeVectorComponentTypeUnsignedInt32NV, g_matrix, 0,
          vk::CooperativeVectorComponentTypeUnsignedInt32NV, g_matrix, 16,
          vk::CooperativeVectorComponentTypeUnsignedInt32NV, 4, 4,
          vk::CooperativeVectorMatrixLayoutColumnMajorNV, false, 16);

  // The same instruction with the TrainingOptimalNV layout, i.e. without the
  // MatrixStride operand.
  // CHECK: OpCooperativeVectorMatrixMulAddNV [[CVU]] %{{[A-Za-z0-9_]+}} %int_9 %g_matrix %uint_0 %int_9 %g_matrix %uint_16 %int_9 %uint_4 %uint_4 %int_3 %true{{$}}
  vk::nv::CooperativeVector<uint, 4> training = vk::nv::MatrixMulAdd<uint, 4, 4>(
      v, vk::CooperativeVectorComponentTypeUnsignedInt32NV, g_matrix, 0,
      vk::CooperativeVectorComponentTypeUnsignedInt32NV, g_matrix, 16,
      vk::CooperativeVectorComponentTypeUnsignedInt32NV, 4, 4,
      vk::CooperativeVectorMatrixLayoutTrainingOptimalNV, true);

  // The results are opaque, so the only thing a shader can do with them is write
  // them back to memory. The offsets keep every result distinct so that the
  // operand order of the instructions above can be read off the module.
  vk::nv::Store<uint, 4>(g_vector, 12, rowMajor);
  vk::nv::Store<uint, 4>(g_vector, 16, optimal);
  vk::nv::Store<float, 4>(g_fvector, 4, fmul);
  vk::nv::Store<uint, 4>(g_vector, 20, accumulation);
  vk::nv::Store<uint, 4>(g_vector, 24, training);
  g_out[0] = tid.x;
}

// The VULKAN10 run line compiles at the default target environment, which emits
// SPIR-V 1.0: nothing about the extension changes and the module still
// validates, so there is no target-environment gate to add.
// VULKAN10: ; Version: 1.0
// VULKAN10: OpCapability CooperativeVectorNV
// VULKAN10: OpExtension "SPV_NV_cooperative_vector"
// VULKAN10: OpMemoryModel Logical GLSL450
// VULKAN10: [[CVU:%[A-Za-z0-9_]+]] = OpTypeVectorIdEXT %uint %uint_4
// VULKAN10: OpCooperativeVectorMatrixMulNV [[CVU]] %{{[A-Za-z0-9_]+}} %int_9 %g_matrix %uint_0 %int_9 %uint_4 %uint_4 %int_0 %false %uint_16

// The 16-bit float entry point: a half component adds Float16, because the
// component type of OpTypeVectorIdEXT is an operand of the type and
// CapabilityVisitor has to look at it explicitly.
[numthreads(1, 1, 1)] void half_main(uint3 tid : SV_DispatchThreadID) {
  // HALF: OpCapability Float16
  // HALF: OpCapability CooperativeVectorNV
  // HALF: [[CVH:%[A-Za-z0-9_]+]] = OpTypeVectorIdEXT %half %uint_8
  // HALF: OpCooperativeVectorLoadNV [[CVH]] %g_hvector %uint_0
  // HALF: OpCooperativeVectorStoreNV %g_hvector %uint_8 %{{[A-Za-z0-9_]+}}
  vk::nv::CooperativeVector<half, 8> h = vk::nv::Load<half, 8>(g_hvector, 0);
  vk::nv::Store<half, 8>(g_hvector, 8, h);
  g_out[0] = tid.x;
}
