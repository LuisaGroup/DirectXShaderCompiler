// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_matrix_decode_vector -fspv-extension=SPV_NV_cooperative_matrix2 -fspv-extension=SPV_NV_tensor_addressing -fspv-extension=SPV_KHR_physical_storage_buffer %s | FileCheck %s
//
// G19/L1.decode + G19/L2.decode + G19/L2.callback: the whole surface of
// SPV_NV_cooperative_matrix_decode_vector in one module - the capability and its
// prerequisites, the extension string, the tensor layout the block is read
// through, and the DecodeFunc|DecodeVectorFunc operands with the two synthesized
// functions they name.
//
// Every extension this module needs has to be listed, because an explicit
// -fspv-extension list replaces the defaults (FeatureManager::FeatureManager):
//   SPV_NV_cooperative_matrix_decode_vector  CooperativeMatrixDecodeVectorNV
//   SPV_NV_cooperative_matrix2               CooperativeMatrixTensorAddressingNV,
//                                            CooperativeMatrixBlockLoadsNV and the
//                                            tensor load itself
//   SPV_NV_tensor_addressing                 TensorAddressingNV, OpTypeTensorLayoutNV
//   SPV_KHR_physical_storage_buffer          the decode functions' first parameter
//                                            is a PhysicalStorageBuffer pointer
// The last three are prerequisites rather than options, so CodeGen attaches them
// to the instruction (SpirvEmitter::processCooperativeMatrixLoadTensorNV); only
// the decode-vector extension goes through FeatureManager, which is what
// nv.decode-vector.extension.error.hlsl pins.
//
// A cooperative matrix type requires SPIR-V 1.6 (<vk/khr/cooperative_matrix.h>
// raises #error below that) and VulkanMemoryModel, and a PhysicalStorageBuffer
// pointer promotes the addressing model, so the memory model is
// "PhysicalStorageBuffer64 Vulkan" and not "Logical Vulkan" - see
// SpirvBuilder::takeModule.

#include <vk/nv/cooperative_matrix_decode_vector.h>

using Mat = vk::khr::CooperativeMatrixA<float, vk::ScopeWorkgroup, 16, 16>;
using Layout = vk::nv::TensorLayout<2, vk::nv::TensorClampModeClampToEdge>;

groupshared float g_data[256];

[numthreads(1, 1, 1)]
void main() {
  Layout layout =
      vk::nv::CreateTensorLayout<2, vk::nv::TensorClampModeClampToEdge>();
  Mat source;
  Mat m = vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV<4>(
      g_data, source, layout);
  m.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(
      vk::GetGroupSharedAddress(g_data[0]), 16);
}

// L1: the capability set, each exactly once and in this order. The trailing
// CHECK-NEXT chain is what proves "exactly once": a second
// OpCapability CooperativeMatrixDecodeVectorNV would have to appear after
// OpExtension "SPV_KHR_cooperative_matrix" to stay inside the block, and the
// chain forbids any instruction in between.
// CHECK:      OpCapability PhysicalStorageBufferAddresses
// CHECK-NEXT: OpCapability TensorAddressingNV
// CHECK-NEXT: OpCapability VariablePointers
// CHECK-NEXT: OpCapability CooperativeMatrixTensorAddressingNV
// CHECK-NEXT: OpCapability CooperativeMatrixBlockLoadsNV
// CHECK-NEXT: OpCapability CooperativeMatrixDecodeVectorNV
// CHECK-NEXT: OpExtension "SPV_KHR_cooperative_matrix"
// CHECK:      OpExtension "SPV_KHR_physical_storage_buffer"
// CHECK-NEXT: OpExtension "SPV_NV_tensor_addressing"
// CHECK-NEXT: OpExtension "SPV_NV_cooperative_matrix2"
// CHECK-NEXT: OpExtension "SPV_NV_cooperative_matrix_decode_vector"
// CHECK-NEXT: OpMemoryModel PhysicalStorageBuffer64 Vulkan

// L2.callback: the first parameter of both decode functions is a
// PhysicalStorageBuffer pointer ("first parameter must be pointer to
// PhysicalStorageBuffer"). The pointee is not constrained by the extension, so
// it is the matrix component type.
// CHECK: [[psb:%[0-9a-zA-Z_]+]] = OpTypePointer PhysicalStorageBuffer %float
// The second and third parameters: arrays of 32-bit integers whose length is the
// Dim of the tensor layout.
// CHECK: [[coords:%[0-9a-zA-Z_]+]] = OpTypeArray %uint %uint_2
// The two function types. DecodeFunc returns the matrix component type,
// DecodeVectorFunc a 4-component vector of it (the
// __builtin_spv_CooperativeMatrixLoadTensorNV<4> template argument).
// (The vector function is emitted first, because the two functions are added to
// the front of the module's function list as they are created.)
// CHECK:      [[vectype:%[0-9a-zA-Z_]+]] = OpTypeFunction %v4float [[psb]] [[coords]] [[coords]]
// CHECK:      [[sctype:%[0-9a-zA-Z_]+]] = OpTypeFunction %float [[psb]] [[coords]] [[coords]]
// L2: the tensor layout. Both operands are <id>s of 32-bit integer constants -
// the grammar spells them IdRef, and SPIRV-Tools dereferences both - so Dim is
// the OpConstant %uint_2 the vk::nv::TensorLayout<2, ...> template argument
// produces and ClampMode is TensorClampModeClampToEdge (2), not a literal.
// CHECK: [[layout:%[0-9a-zA-Z_]+]] = OpTypeTensorLayoutNV %uint_2 %uint_2
// The tensor memory the block is read from: the groupshared array's own
// OpVariable, in the Workgroup storage class SPIRV-Tools requires.
// CHECK:      [[data:%[0-9a-zA-Z_]+]] = OpVariable {{%[^ ]+}} Workgroup
// The two functions the DecodeFunc and DecodeVectorFunc operands name, in the
// order the operands list them.
// CHECK:      [[vector:%[0-9a-zA-Z_]+]] = OpFunction %v4float None [[vectype]]
// CHECK:      [[scalar:%[0-9a-zA-Z_]+]] = OpFunction %float None [[sctype]]
// L2: the load itself, with every operand position captured:
//   OpCooperativeMatrixLoadTensorNV Result Type, Result, Pointer, Object,
//                                   TensorLayout, MemoryAccess,
//                                   TensorAddressingOperands
// The TensorLayout operand is the OpCreateTensorLayoutNV value and not the
// variable that holds it, and the mask is the literal DecodeFunc|DecodeVectorFunc
// followed by the two function ids in that order.
// The layout is held in a variable here, so the operand is the OpLoad of it and
// not the OpCreateTensorLayoutNV result: a variable's type is a pointer to the
// layout type, which SPIRV-Tools rejects in that operand position.
// CHECK:      [[tlvar:%[0-9a-zA-Z_]+]] = OpVariable {{%[^ ]+}} Function
// CHECK:      [[tlval0:%[0-9a-zA-Z_]+]] = OpCreateTensorLayoutNV [[layout]]
// CHECK:      OpStore [[tlvar]] [[tlval0]]
// CHECK:      [[tlval:%[0-9a-zA-Z_]+]] = OpLoad {{%[^ ]+}} [[tlvar]]
// CHECK:      {{%[0-9a-zA-Z_]+}} = OpCooperativeMatrixLoadTensorNV {{%[^ ]+}} [[data]] {{%[^ ]+}} [[tlval]] None DecodeFunc|DecodeVectorFunc [[scalar]] [[vector]]
