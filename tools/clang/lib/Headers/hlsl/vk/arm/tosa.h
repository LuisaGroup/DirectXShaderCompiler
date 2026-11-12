// Copyright (c) 2026 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// TOSA tensor operations: the TOSA.001000.1 extended instruction set.
//
// TOSA (Tensor Operator Set Architecture) is Arm's operator set for the tensor
// graphs of the ARM data-graph ecosystem: an application hands a whole graph of
// tensor operations to a runtime, which compiles or interprets it for whatever
// accelerator is present. The operations are named by an *extended instruction
// set* rather than by an extension, so this is not a Vulkan extension and there
// is no VK_* feature bit to enable:
//
//   %1 = OpExtInstImport "TOSA.001000.1"
//   %r = OpExtInst %tensor %1 ADD %a %b
//
// TOSA.001000.1 is TOSA version 1.0 revision 1 (TOSAVersion 1000001,
// TOSARevision 1, in the vendored
// external/SPIRV-Headers/include/spirv/unified1/TOSA.001000.1.h). It defines 66
// operations; the ones declared below are the subset a shader can feed without
// inventing convolution-kernel or FFT operand conventions, plus the shape and
// reduction operations needed to make the values useful.
//
//   #include <vk/arm/tosa.h>
//
//   using namespace vk::arm::tosa;
//   Tensor<float> a = ...;
//   Tensor<float> b = ...;
//   Tensor<float> sum = Add(a, b);                        // ADD
//   Tensor<float> mag = Abs(sum);                         // ABS
//   Tensor<float> big = Maximum(NanModeIgnore, mag, b);   // MAXIMUM, nan_mode 1
//
// ## The operand type
//
// Every TOSA operation is defined over *tensors*, not over scalars or vectors,
// and the SPIR-V encoding says so: the operand and result type of each OpExtInst
// is a tensor type. SPV_ARM_tensors provides that type as OpTypeTensorARM (4163),
// which HLSL has no spelling for, so it is built out of the ordinary vk:: type
// machinery (vk::SpirvOpaqueType):
//
//   Tensor<float>  ->  %t = OpTypeTensorARM %float
//
// OpTypeTensorARM's two optional operands are the tensor *Rank* and *Shape*. Rank
// is expressible - it is the id of an integer constant, which is what
// vk::integral_constant<uint, N> provides:
//
//   vk::SpirvOpaqueType</* OpTypeTensorARM */ 4163, float,
//                       vk::integral_constant<uint, 2> >
//     ->  %t = OpTypeTensorARM %float %uint_2
//
// Shape is not: it is the id of an OpConstantComposite of an integer array whose
// length equals Rank, and the vk:: template-argument machinery can carry types
// and integer constants but not a composite constant. The Tensor alias below
// therefore carries neither, which leaves the rank and shape of a tensor
// unspecified in the type. SPIRV-Tools accepts that (ValidateTypeTensorARM
// returns success once it runs out of operands), but an operation that needs to
// know a tensor's shape has nothing to read from the type: the consumer of such a
// module has to take the shapes from the graph that produces the tensors, which
// is where they live in the data-graph model anyway.
//
// The rank-carrying spelling above is expressible, and <vk/arm/tosa.h>'s
// operations deliberately do *not* use it: they are declared over the unranked
// Tensor so that one declaration serves every tensor a caller has, and so that the
// result type of an operation that changes the element type (Cast) or that
// produces a predicate (Equal, ReduceAll, ...) is spelled the same way as the
// result of one that does not. Mixing the two spellings would make
// Add-of-a-ranked-tensor return a ranked tensor while Equal-of-a-ranked-tensor
// returned an unranked one, which is a worse contract than "the header is
// unranked, and a ranked tensor is something you declare yourself". The latter is
// two lines and is pinned in tosa.ranked-tensor.hlsl.
//
// Tensor is templated on the *element* type rather than being a fixed alias so
// that one declaration serves every element type TOSA has an encoding for, in the
// same way vk::ext::LongVector and vk::nv::CooperativeVector are templated.
// SPIRV-Tools requires the element type to be a scalar ("OpTypeTensorARM Element
// Type <id> is not a scalar type"), so Tensor<float4> is rejected here, at
// compile time, instead of producing a module the validator refuses.
//
// ## What this header adds to the module
//
// OpTypeTensorARM is in SPV_ARM_tensors, so the *type* requires
// OpCapability TensorsARM (4174) and OpExtension "SPV_ARM_tensors". Both are
// attached to every declaration below with [[vk::ext_extension]] and
// [[vk::ext_capability]] rather than inferred, because:
//
//  * TOSA has no capability and no extension string of its own - the grammar
//    (external/SPIRV-Headers/include/spirv/unified1/
//     extinst.tosa.001000.1.grammar.json) names neither, and SPIRV-Tools
//    recognizes the set purely by the import string (spvExtInstImportTypeGet).
//  * FeatureManager has no SPIR-V-side entry for SPV_ARM_tensors - naming it on
//    the command line is "error: unknown SPIR-V extension 'SPV_ARM_tensors'" - so
//    CodeGen has nothing to infer the capability from. [[vk::ext_capability]]
//    writes it directly, which means -fspv-extension cannot select or refuse it.
//    That is the intended contract for this header: TOSA is a graph instruction
//    set that only makes sense in a module that already committed to the Arm
//    tensor model, so the capability is unconditional and the deviation is
//    recorded rather than papered over (tosa.identifiers.error.hlsl pins the
//    "unknown SPIR-V extension" diagnostic).
//
// The OpExtInstImport is emitted lazily, by the first TOSA call in the module
// (SpirvBuilder::getExtInstSet); including the header and using nothing from it
// adds nothing to the module.
//
// ## The shapes of the operations
//
// TOSA reads some of its information as *attributes*, not as operands: the
// nan_mode of Maximum, the axis of ReduceSum, the shape of Reshape. In the SPIR-V
// encoding those attributes are operands too - the grammar spells every operand
// as IdRef - so each one is a parameter below. They are ordinary HLSL integers,
// integer vectors and enumerators, which the front end materializes as
// OpConstant when the call site passes a constant:
//
//   Add(a, b)                    // ADD %a %b
//   Maximum(NanModeIgnore, a, b) // MAXIMUM %int_1 %a %b
//   Mul(a, b, 0)                 // MUL %a %b %int_0
//   MatMul(a, b, 0, 0)           // MATMUL %a %b %int_0 %int_0
//   ReduceSum(0, x)              // REDUCE_SUM %int_0 %x
//   Reshape(x, int2(4, 4))       // RESHAPE %x %shape (an OpConstantComposite)
//
// TOSA requires every one of these to be a compile-time constant, and this header
// cannot enforce it: an HLSL parameter is an ordinary value, so a call site can
// pass one that was computed at run time, and the result is an OpLoad where TOSA
// wants an OpConstant. Such a module still validates - the validator only checks
// the arity - but it is not a valid TOSA graph. Pass a literal.
//
// ## What this header cannot express
//
//  * A shaped tensor type. See above: Rank is expressible, Shape is not.
//  * A data-graph entry point. OpGraphARM, OpGraphEntryPointARM and the rest of
//    the OpGraph*ARM family (SPV_ARM_graph, OpCapability GraphARM) are what make
//    a module a *graph* rather than a kernel; nothing in DXC emits them yet, so a
//    module that uses these operations is a compute shader that happens to
//    contain TOSA instructions. A runtime that requires them inside a graph will
//    reject it. That is a front-end feature (a new kind of entry point), not a
//    header one.
//  * A constant tensor. OpConstantComposite over OpTypeTensorARM is how TOSA
//    constants are encoded, and it requires the Shape operand the type cannot
//    carry.
//  * A tensor as a shader-visible resource. SPV_ARM_tensors treats
//    OpTypeTensorARM as a descriptor type - SPIRV-Tools' ValidateMemory lists it
//    among the types a UniformConstant variable may have, next to OpTypeImage -
//    but HLSL has no resource-object spelling for it: a global of an opaque type
//    lands in $Globals, and an RWStructuredBuffer of one embeds the opaque type
//    in a StructBlock, which is not a descriptor. In practice a tensor value can
//    only be produced by another TOSA operation, or be an uninitialized local,
//    until a data-graph entry point supplies one.
//  * The convolution, pooling, FFT, resize, gather/scatter, table and rescale
//    operations. Their operand lists are pad/kernel/stride coefficient lists that
//    TOSA defines per rank and dtype; declaring them here would be a numeric
//    contract with no way to check it. They are reachable through
//    [[vk::ext_instruction(<opcode>, "TOSA.001000.1")]] directly.
//
// ## What the host has to do
//
// The compiler cannot check any of this, and no CI driver implements TOSA:
//
//  * TOSA is a *profile and level* specification. Which of the 66 operations a
//    device implements, at which levels (8K, 16K, FP), and in which of TOSA's
//    extensions (int16, fp8, bf16, control flow, ...) is discovered at runtime
//    from the implementation - not from the SPIR-V module. A module that uses
//    ADD says nothing about whether the device can execute ADD.
//  * The set name pins the TOSA version: a module that imports "TOSA.001000.1"
//    is TOSA 1.0 rev 1 and nothing else. A different version is a different
//    import string and a different opcode table.
//  * Creating the pipeline, or the graph, requires a device and driver that
//    support the Arm data-graph model which consumes these instructions.
//  * Numeric conformance is the implementation's: TOSA specifies behaviour but
//    no CI in this repository executes a single one of these operations, so the
//    tests pin the encoding, not the arithmetic.

#ifndef _HLSL_VK_ARM_TOSA_H_
#define _HLSL_VK_ARM_TOSA_H_

namespace vk {
namespace arm {
namespace tosa {

namespace detail {

// The element types OpTypeTensorARM accepts. SPIRV-Tools validates the Element
// Type of a tensor type ("OpTypeTensorARM Element Type <id> is not a scalar
// type"), so a vector or matrix element type is refused below rather than being
// lowered into a module the validator rejects. TOSA defines operations over
// 32-bit integers, 8/16/32/48-bit integers and 16/32-bit floats; HLSL cannot
// spell a 48-bit integer, and the 8- and 16-bit forms need -enable-16bit-types
// and the capabilities that go with it, so the list is the scalar types an
// ordinary HLSL shader has.
template <typename ElementType> struct IsScalarElement {
  static const bool value = false;
};
template <> struct IsScalarElement<bool> {
  static const bool value = true;
};
template <> struct IsScalarElement<int> {
  static const bool value = true;
};
template <> struct IsScalarElement<uint> {
  static const bool value = true;
};
template <> struct IsScalarElement<half> {
  static const bool value = true;
};
template <> struct IsScalarElement<min16float> {
  static const bool value = true;
};
template <> struct IsScalarElement<float> {
  static const bool value = true;
};
template <> struct IsScalarElement<double> {
  static const bool value = true;
};

// The diagnostic types. Each has a definition for `true` only, so instantiating
// one with `false` is the error, and the note names the use the author wrote:
//   error: implicit instantiation of undefined template
//          'vk::arm::tosa::detail::ElementTypeIsScalar<false>'
template <bool supported> struct ElementTypeIsScalar;
template <> struct ElementTypeIsScalar<true> {
  using ok = int;
};

// A non-deduced context: `typename Identity<T>::type` is a parameter type that
// template argument deduction does not look at. TOSA CLAMP takes its two bound
// attributes before the data operand, and a bound is of the tensor's element
// type, so without this an argument list of (0.0, 1.0, mode, tensor) would
// deduce ElementType twice - from the float literal (HLSL types a literal
// `0.0` as literal float) and from the tensor - and fail. With it, ElementType
// comes from the tensor alone and the bounds convert to it.
template <typename T> struct Identity {
  using type = T;
};

} // namespace detail

// A TOSA tensor: OpTypeTensorARM over ElementType.
//
//   %t = OpTypeTensorARM %ElementType
//
// Rank and Shape are omitted; see the file header for why Shape cannot be
// expressed and for the spelling to use when a rank is required.
template <typename ElementType,
          typename ElementCheck = typename detail::ElementTypeIsScalar<
              detail::IsScalarElement<ElementType>::value>::ok>
using Tensor = vk::SpirvOpaqueType</* OpTypeTensorARM */ 4163, ElementType>;

// The nan_mode attribute of MAXIMUM, MINIMUM, REDUCE_MAX, REDUCE_MIN and CLAMP.
// TOSA spells it PROPAGATE (0) and IGNORE (1): PROPAGATE makes a NaN in either
// operand produce a NaN, IGNORE returns the other operand instead. The operand is
// the id of a 32-bit integer constant in the SPIR-V encoding, which is what an
// enumerator argument lowers to, so SPIR-V sees the number and nothing else - the
// two values are the ones the TOSA specification assigns and the compiler cannot
// check that a consumer agrees with them.
enum NanMode {
  NanModePropagate = 0,
  NanModeIgnore = 1,
};

// Every declaration below is an [[vk::ext_instruction]] with the TOSA set name,
// so the call lowers to OpExtInst and nothing else:
//
//   %r = OpExtInst %result-type %tosa-import <MNEMONIC> <operands...>
//
// The capability and the extension are per-declaration because both belong to the
// operand type (OpTypeTensorARM) and SPV_ARM_tensors is not a FeatureManager
// allow-list entry, so nothing infers them. They are written through a macro so
// that a declaration which forgets one is impossible: a TOSA instruction whose
// result type is a tensor, in a module without TensorsARM, is an invalid module
// that SPIRV-Tools rejects.
#define VK_ARM_TOSA_OP(opcode)                     \
  [[vk::ext_extension("SPV_ARM_tensors")]]         \
  [[vk::ext_capability(/* TensorsARM */ 4174)]]    \
  [[vk::ext_instruction(opcode, "TOSA.001000.1")]]

// Elementwise binary arithmetic. TOSA ADD / SUB / POW: (input1, input2).
template <typename ElementType>
VK_ARM_TOSA_OP(/* ADD */ 14)
Tensor<ElementType> Add(Tensor<ElementType> input1,
                        Tensor<ElementType> input2);

template <typename ElementType>
VK_ARM_TOSA_OP(/* SUB */ 29)
Tensor<ElementType> Sub(Tensor<ElementType> input1,
                        Tensor<ElementType> input2);

template <typename ElementType>
VK_ARM_TOSA_OP(/* POW */ 28)
Tensor<ElementType> Pow(Tensor<ElementType> input1,
                        Tensor<ElementType> input2);

// Multiplies two tensors elementwise. TOSA MUL: (input1, input2, shift). The
// third operand is the *shift* that makes the integer form an exact scaled
// multiply; TOSA requires it for the floating-point form too, where it is unused
// and conventionally 0. Note that it comes last, after both data operands.
template <typename ElementType>
VK_ARM_TOSA_OP(/* MUL */ 27)
Tensor<ElementType> Mul(Tensor<ElementType> input1, Tensor<ElementType> input2,
                        int shift);

// Elementwise maximum / minimum. TOSA MAXIMUM / MINIMUM: (nan_mode, input1,
// input2). nan_mode is *first* in the operand list, which is not the order the
// mnemonic suggests.
template <typename ElementType>
VK_ARM_TOSA_OP(/* MAXIMUM */ 25)
Tensor<ElementType> Maximum(NanMode nanMode, Tensor<ElementType> input1,
                            Tensor<ElementType> input2);

template <typename ElementType>
VK_ARM_TOSA_OP(/* MINIMUM */ 26)
Tensor<ElementType> Minimum(NanMode nanMode, Tensor<ElementType> input1,
                            Tensor<ElementType> input2);

// Integer division, truncated towards zero. TOSA INTDIV: (input1, input2).
template <typename ElementType>
VK_ARM_TOSA_OP(/* INTDIV */ 19)
Tensor<ElementType> IntDiv(Tensor<ElementType> input1,
                           Tensor<ElementType> input2);

// Bitwise binary operations. TOSA BITWISE_AND / OR / XOR: (input1, input2).
template <typename ElementType>
VK_ARM_TOSA_OP(/* BITWISE_AND */ 16)
Tensor<ElementType> BitwiseAnd(Tensor<ElementType> input1,
                               Tensor<ElementType> input2);

template <typename ElementType>
VK_ARM_TOSA_OP(/* BITWISE_OR */ 17)
Tensor<ElementType> BitwiseOr(Tensor<ElementType> input1,
                              Tensor<ElementType> input2);

template <typename ElementType>
VK_ARM_TOSA_OP(/* BITWISE_XOR */ 18)
Tensor<ElementType> BitwiseXor(Tensor<ElementType> input1,
                               Tensor<ElementType> input2);

// Unary elementwise operations. Each of these TOSA operations is (input1) and
// has the same shape and element type as its operand:
//
//   %r = OpExtInst %tensor %tosa ABS %x
template <typename ElementType>
VK_ARM_TOSA_OP(/* ABS */ 31)
Tensor<ElementType> Abs(Tensor<ElementType> input1);

// Negation. TOSA NEGATE: (input1, input1_zp, output_zp). The two zero points are
// TOSA attributes that the instruction carries as operands; they only matter for
// the integer form, so pass 0 for floating point:
//
//   Negate(x, 0, 0)  ->  NEGATE %x %int_0 %int_0
template <typename ElementType>
VK_ARM_TOSA_OP(/* NEGATE */ 40)
Tensor<ElementType> Negate(Tensor<ElementType> input1, int input1_zp,
                           int output_zp);

template <typename ElementType>
VK_ARM_TOSA_OP(/* EXP */ 36)
Tensor<ElementType> Exp(Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* LOG */ 38)
Tensor<ElementType> Log(Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* SIGMOID */ 12)
Tensor<ElementType> Sigmoid(Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* TANH */ 13)
Tensor<ElementType> Tanh(Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* ERF */ 11)
Tensor<ElementType> Erf(Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* CEIL */ 33)
Tensor<ElementType> Ceil(Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* FLOOR */ 37)
Tensor<ElementType> Floor(Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* RECIPROCAL */ 41)
Tensor<ElementType> Reciprocal(Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* RSQRT */ 42)
Tensor<ElementType> Rsqrt(Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* SIN */ 43)
Tensor<ElementType> Sin(Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* COS */ 35)
Tensor<ElementType> Cos(Tensor<ElementType> input1);

// Count of leading zero bits. TOSA CLZ: (input1).
template <typename ElementType>
VK_ARM_TOSA_OP(/* CLZ */ 34)
Tensor<ElementType> Clz(Tensor<ElementType> input1);

// Bitwise complement. TOSA BITWISE_NOT: (input1).
template <typename ElementType>
VK_ARM_TOSA_OP(/* BITWISE_NOT */ 32)
Tensor<ElementType> BitwiseNot(Tensor<ElementType> input1);

// Logical (boolean) operations. TOSA LOGICAL_AND / OR / XOR: (input1, input2);
// LOGICAL_NOT: (input1). The result element type is bool, which is what makes
// these composable with Select below.
template <typename ElementType>
VK_ARM_TOSA_OP(/* LOGICAL_AND */ 20)
Tensor<bool> LogicalAnd(Tensor<ElementType> input1,
                        Tensor<ElementType> input2);

template <typename ElementType>
VK_ARM_TOSA_OP(/* LOGICAL_OR */ 23)
Tensor<bool> LogicalOr(Tensor<ElementType> input1, Tensor<ElementType> input2);

template <typename ElementType>
VK_ARM_TOSA_OP(/* LOGICAL_XOR */ 24)
Tensor<bool> LogicalXor(Tensor<ElementType> input1,
                        Tensor<ElementType> input2);

template <typename ElementType>
VK_ARM_TOSA_OP(/* LOGICAL_NOT */ 39)
Tensor<bool> LogicalNot(Tensor<ElementType> input1);

// Comparisons. TOSA EQUAL / GREATER / GREATER_EQUAL: (input1, input2). The result
// is a tensor of bool, so a comparison feeds Select directly:
//
//   Tensor<float> m = Select(Greater(a, b), a, b);
template <typename ElementType>
VK_ARM_TOSA_OP(/* EQUAL */ 45)
Tensor<bool> Equal(Tensor<ElementType> input1, Tensor<ElementType> input2);

template <typename ElementType>
VK_ARM_TOSA_OP(/* GREATER */ 46)
Tensor<bool> Greater(Tensor<ElementType> input1, Tensor<ElementType> input2);

template <typename ElementType>
VK_ARM_TOSA_OP(/* GREATER_EQUAL */ 47)
Tensor<bool> GreaterEqual(Tensor<ElementType> input1,
                          Tensor<ElementType> input2);

// Selects elementwise: input1 is the predicate tensor, input2 is taken where it
// is true and input3 where it is false. TOSA SELECT: (input1, input2, input3).
template <typename ElementType>
VK_ARM_TOSA_OP(/* SELECT */ 44)
Tensor<ElementType> Select(Tensor<bool> input1, Tensor<ElementType> input2,
                           Tensor<ElementType> input3);

// Clamps to [minVal, maxVal]. TOSA CLAMP: (min_val, max_val, nan_mode, input).
// min_val and max_val are TOSA *attributes*, passed here as the tensor's element
// type so that a literal lowers to an OpConstant of that type:
//
//   Clamp(0.0, 1.0, NanModePropagate, x)
//     ->  CLAMP %float_0 %float_1 %int_0 %x
template <typename ElementType>
VK_ARM_TOSA_OP(/* CLAMP */ 10)
Tensor<ElementType> Clamp(typename detail::Identity<ElementType>::type minVal,
                          typename detail::Identity<ElementType>::type maxVal,
                          NanMode nanMode, Tensor<ElementType> input1);

// Reductions. TOSA REDUCE_SUM / REDUCE_PRODUCT / REDUCE_ALL / REDUCE_ANY:
// (axis, input); TOSA REDUCE_MAX / REDUCE_MIN: (axis, nan_mode, input). The axis
// is an <id> of a constant integer tensor in TOSA; the encoding below passes the
// id of a scalar integer constant, which is the smallest form the validator
// accepts. The axis comes *before* the data operand:
//
//   ReduceSum(0, x)  ->  REDUCE_SUM %int_0 %x
//
// REDUCE_ALL / REDUCE_ANY produce a tensor of bool from a tensor of bool.
template <typename ElementType>
VK_ARM_TOSA_OP(/* REDUCE_SUM */ 53)
Tensor<ElementType> ReduceSum(int axis, Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* REDUCE_PRODUCT */ 52)
Tensor<ElementType> ReduceProduct(int axis, Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* REDUCE_MAX */ 50)
Tensor<ElementType> ReduceMax(int axis, NanMode nanMode,
                              Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* REDUCE_MIN */ 51)
Tensor<ElementType> ReduceMin(int axis, NanMode nanMode,
                              Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* REDUCE_ALL */ 48)
Tensor<bool> ReduceAll(int axis, Tensor<ElementType> input1);

template <typename ElementType>
VK_ARM_TOSA_OP(/* REDUCE_ANY */ 49)
Tensor<bool> ReduceAny(int axis, Tensor<ElementType> input1);

// Shape operations. Each takes the shape/permutation/extent vector that TOSA
// defines as the id of a constant integer tensor, and takes it as an HLSL integer
// vector instead, so that a literal lowers to OpConstantComposite:
//
//   Reshape(x, int2(4, 4))  ->  RESHAPE %x %int_4_4
//
// The *length* of that vector is the tensor's rank and is whatever the author
// passes; nothing here checks it against the tensors. Note the operand order of
// each: TOSA puts the coefficient operand first for TRANSPOSE and last for the
// rest.

// TOSA RESHAPE: (input1, shape).
template <typename ElementType, typename ShapeType>
VK_ARM_TOSA_OP(/* RESHAPE */ 56)
Tensor<ElementType> Reshape(Tensor<ElementType> input1, ShapeType shape);

// TOSA TRANSPOSE: (perms, input1). The permutation comes *first*, the opposite of
// the reading order.
template <typename ElementType, typename PermsType>
VK_ARM_TOSA_OP(/* TRANSPOSE */ 60)
Tensor<ElementType> Transpose(PermsType perms, Tensor<ElementType> input1);

// TOSA SLICE: (input1, start, size).
template <typename ElementType, typename IndexType>
VK_ARM_TOSA_OP(/* SLICE */ 58)
Tensor<ElementType> Slice(Tensor<ElementType> input1, IndexType start,
                          IndexType size);

// TOSA TILE: (input1, multiples).
template <typename ElementType, typename MultipleType>
VK_ARM_TOSA_OP(/* TILE */ 59)
Tensor<ElementType> Tile(Tensor<ElementType> input1, MultipleType multiples);

// Concatenates two tensors along an axis. TOSA CONCAT: (axis, input1*), where
// input1 carries the * quantifier - the operand list is variable length and every
// concatenated tensor after the axis precedes the next. The two-tensor form is
// declared here; for more, declare the instruction directly. The axis comes
// first:
//
//   Concat(0, a, b)  ->  CONCAT %int_0 %a %b
template <typename ElementType>
VK_ARM_TOSA_OP(/* CONCAT */ 54)
Tensor<ElementType> Concat(int axis, Tensor<ElementType> input1,
                           Tensor<ElementType> input2);

// Matrix multiplication. TOSA MATMUL: (A, B, A_zp, B_zp). The two zero points are
// TOSA attributes that the instruction carries as operands; they only matter for
// the integer form, so pass 0 for floating point. They come last:
//
//   MatMul(a, b, 0, 0)  ->  MATMUL %a %b %int_0 %int_0
template <typename ElementType>
VK_ARM_TOSA_OP(/* MATMUL */ 6)
Tensor<ElementType> MatMul(Tensor<ElementType> A, Tensor<ElementType> B, int A_zp,
                           int B_zp);

// Converts the elements to another type. TOSA CAST: (input). The result element
// type is a template parameter because it is not derivable from the operand:
//
//   Cast<float>(x)   // Tensor<int> -> Tensor<float>
template <typename ResultElement, typename ElementType>
VK_ARM_TOSA_OP(/* CAST */ 64)
Tensor<ResultElement> Cast(Tensor<ElementType> input1);

#undef VK_ARM_TOSA_OP

} // namespace tosa
} // namespace arm
} // namespace vk

#endif // _HLSL_VK_ARM_TOSA_H_
