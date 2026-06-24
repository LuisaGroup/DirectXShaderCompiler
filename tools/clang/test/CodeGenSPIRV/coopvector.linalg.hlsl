// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_0 -E main -spirv -HV 2021 -Vd %s | FileCheck %s

// Integration test for cooperative vector operations using a linalg-style
// wrapper layer. Uses proper #include directives (unlike hlsl_output.hlsl
// which embeds inline copies of headers).

#include <vk/nv/cooperative_vector.h>

// CHECK: OpCapability CooperativeVectorNV
// CHECK: OpExtension "SPV_NV_cooperative_vector"

RWStructuredBuffer<float> data;

namespace linalg {

// CoopMul: cooperative vector matrix multiply
template<typename InType, typename OutType, uint in_dim, uint out_dim>
vk::nv::CooperativeVector<OutType, out_dim> CoopMul(
    RWStructuredBuffer<float> mat_buffer,
    uint mat_offset,
    vk::nv::CooperativeVector<InType, in_dim> input_vec) {

  // Load matrix data from buffer using cooperative vector load
  vk::nv::CooperativeVector<OutType, out_dim> result =
      vk::nv::CooperativeVector<OutType, out_dim>::Load(mat_buffer, mat_offset);

  // Multiply: result = matrix * input_vector
  // The cooperative vector matvecmul is done via the cooperative matrix extension
  // CHECK: OpCooperativeVectorLoadNV
  // CHECK: OpCooperativeVectorMatrixMulNV
  return vk::nv::cooperativeVectorMatrixMul<OutType, InType, out_dim, in_dim>(
      input_vec,
      /* inputInterpretation */ 0,
      mat_buffer, mat_offset,
      /* matrixInterpretation */ 0,
      /* stride */ 16,
      vk::CooperativeVectorMatrixLayoutRowMajorNV,
      /* transpose */ false);
}

// CoopVectorAccumulate: accumulate a vector into buffer
template<typename ElTy, int ElCount>
void CoopVectorAccumulate(
    RWStructuredBuffer<ElTy> buffer,
    uint offset,
    vk::nv::CooperativeVector<ElTy, ElCount> input_vec) {

  // CHECK: OpCooperativeVectorReduceSumAccumulateNV
  vk::nv::cooperativeVectorReduceSumAccumulate(input_vec, buffer, offset);
}

} // namespace linalg

[numthreads(64, 1, 1)]
void main() {
  using Vec4 = vk::nv::CooperativeVector<float, 4>;

  // Load input vector
  // CHECK: OpCooperativeVectorLoadNV
  Vec4 input = Vec4::Load(data, 0);

  // CoopMul: matrix-vector multiply
  // CHECK: OpCooperativeVectorLoadNV
  // CHECK: OpCooperativeVectorMatrixMulNV
  Vec4 result = linalg::CoopMul<float, float, 4, 4>(data, 64, input);

  // Store result
  // CHECK: OpCooperativeVectorStoreNV
  result.Store(data, 128);

  // CoopVectorAccumulate: reduce-sum-accumulate
  // CHECK: OpCooperativeVectorReduceSumAccumulateNV
  linalg::CoopVectorAccumulate<float, 4>(data, 256, result);
}
