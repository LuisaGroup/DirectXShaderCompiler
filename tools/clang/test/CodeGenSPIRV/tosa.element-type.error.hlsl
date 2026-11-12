// RUN: not %dxc -T cs_6_0 -E main -fcgl -DVECTOR %s -spirv 2>&1 | FileCheck %s --check-prefix=VECTOR
// RUN: not %dxc -T cs_6_0 -E main -fcgl -DMATRIX %s -spirv 2>&1 | FileCheck %s --check-prefix=MATRIX
// RUN: not %dxc -T cs_6_0 -E main -fcgl -DSTRUCT %s -spirv 2>&1 | FileCheck %s --check-prefix=STRUCT

// L4 diagnostic gate: the element type of a TOSA tensor must be a scalar.
//
// OpTypeTensorARM's Element Type must be a scalar type. SPIRV-Tools says so
// (ValidateTypeTensorARM: "OpTypeTensorARM Element Type <id> is not a scalar
// type"), and it is the one restriction on the TOSA surface that the compiler can
// check *before* it emits the module rather than after:
//
//   fatal error: generated SPIR-V is invalid: OpTypeTensorARM Element Type <id>
//   '[%v4float]' is not a scalar type.
//
// That is a backend crash message with an internal id in it, raised after codegen
// has finished, and it is not something a shader author can act on. <vk/arm/tosa.h>
// therefore rejects a non-scalar element type while the Tensor alias is being
// formed, which is what produces the diagnostics below.
//
// The mechanism is the one <vk/nv/cooperative_vector.h> uses: HLSL has no
// static_assert, so a class template with a definition for `true` only is
// instantiated in a default template argument of the alias. `false` makes the
// instantiation ill-formed, and the note that follows the error names the line the
// author wrote.
//
// What this does *not* catch: a scalar element type that TOSA has no encoding for.
// TOSA's element types are 8/16/32/48-bit integers and 16/32-bit floats (plus the
// formats its extensions add), none of which a plain HLSL scalar distinguishes
// beyond its width; the header accepts the HLSL scalars it can spell and leaves the
// width/format question to whoever consumes the graph. A tensor of `bool` is
// accepted because the TOSA comparison and logical operations produce one.

#include <vk/arm/tosa.h>

using namespace vk::arm::tosa;

#ifdef VECTOR
// The element type a TOSA tensor is *most* likely to be given by mistake: TOSA
// operations are elementwise over tensors, and HLSL's elementwise operations are
// written over vectors, so `Tensor<float4>` is the natural spelling of the wrong
// idea. A TOSA tensor of floats is Tensor<float>, and its width is its shape.
//
// VECTOR: error: implicit instantiation of undefined template 'vk::arm::tosa::detail::ElementTypeIsScalar<false>'
// VECTOR: note: in instantiation of default argument for 'Tensor<vector<float, 4> >' required here
// VECTOR: Tensor<float4> bad;
[numthreads(1, 1, 1)] void main() { Tensor<float4> bad; }
#endif

#ifdef MATRIX
// A matrix type is also not a scalar, and a TOSA matrix is a rank-2 tensor rather
// than an HLSL matrix: TOSA MATMUL operates on two tensors and has no notion of a
// row-major or column-major matrix type.
//
// MATRIX: error: implicit instantiation of undefined template 'vk::arm::tosa::detail::ElementTypeIsScalar<false>'
// MATRIX: note: in instantiation of default argument for 'Tensor<matrix<float, 4, 4> >' required here
// MATRIX: Tensor<float4x4> bad;
[numthreads(1, 1, 1)] void main() { Tensor<float4x4> bad; }
#endif

#ifdef STRUCT
// A struct element type, for the same reason: a tensor holds one scalar per
// element and its dimensionality lives in the shape.
//
// STRUCT: error: implicit instantiation of undefined template 'vk::arm::tosa::detail::ElementTypeIsScalar<false>'
// STRUCT: note: in instantiation of default argument for 'Tensor<S>' required here
// STRUCT: Tensor<S> bad;
struct S {
  float x;
};
[numthreads(1, 1, 1)] void main() { Tensor<S> bad; }
#endif
