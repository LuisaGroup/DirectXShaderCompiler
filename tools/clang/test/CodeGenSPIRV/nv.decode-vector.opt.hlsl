// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_matrix_decode_vector -fspv-extension=SPV_NV_cooperative_matrix2 -fspv-extension=SPV_NV_tensor_addressing -fspv-extension=SPV_KHR_physical_storage_buffer %s | FileCheck %s
//
// G19/L6: no -fcgl, so this module goes through legalization, the performance
// pass list and the capability trimmer before it is validated
// (SpirvEmitter::HandleTranslationUnit). Two things can go wrong only here, and
// only this test catches them:
//   * the optimizer rewrites or drops the load - a decode function whose body is
//     OpReturnValue OpUndef is exactly the kind of callee a call-DCE pass likes,
//     and the load is the only thing that keeps the two functions alive;
//   * capability trimming removes CooperativeMatrixDecodeVectorNV or
//     CooperativeMatrixBlockLoadsNV, because nothing looks like it uses them.
// The shader therefore deliberately differs from nv.decode-vector.hlsl in two
// ways: the tensor layout is passed as a call result instead of a variable (so
// the TensorLayout operand is the OpCreateTensorLayoutNV value with no OpLoad in
// between), and the matrix is stored through the Workgroup pointer once so that
// the load cannot be dead code.

#include <vk/nv/cooperative_matrix_decode_vector.h>

using Mat = vk::khr::CooperativeMatrixA<float, vk::ScopeWorkgroup, 16, 16>;

groupshared float g_data[256];

[numthreads(1, 1, 1)]
void main() {
  Mat source;
  Mat m = vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV<4>(
      g_data, source,
      vk::nv::CreateTensorLayout<2, vk::nv::TensorClampModeClampToEdge>());
  m.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(
      vk::GetGroupSharedAddress(g_data[0]), 16);
}

// Both capabilities survive the pass list and the trimmer.
// CHECK:      OpCapability CooperativeMatrixBlockLoadsNV
// CHECK:      OpCapability CooperativeMatrixDecodeVectorNV
// CHECK:      OpExtension "SPV_NV_cooperative_matrix_decode_vector"
// The two decode functions and their signatures survive too, and so does the
// tensor layout type.
// CHECK:      [[vectype:%[0-9a-zA-Z_]+]] = OpTypeFunction %v4float
// CHECK:      [[sctype:%[0-9a-zA-Z_]+]] = OpTypeFunction %float
// CHECK:      OpTypeTensorLayoutNV %uint_2 %uint_2
// CHECK:      [[vector:%[0-9a-zA-Z_]+]] = OpFunction %v4float None [[vectype]]
// CHECK:      [[scalar:%[0-9a-zA-Z_]+]] = OpFunction %float None [[sctype]]
// The load itself, with the mask and both function ids intact.
// CHECK:      {{%[0-9a-zA-Z_]+}} = OpCooperativeMatrixLoadTensorNV {{%[^ ]+}} {{%[^ ]+}} {{%[^ ]+}} {{%[^ ]+}} None DecodeFunc|DecodeVectorFunc [[scalar]] [[vector]]
