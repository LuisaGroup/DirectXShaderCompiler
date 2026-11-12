// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 %s

// A TOSA tensor operation chain: the TOSA.001000.1 extended instruction set.
//
// TOSA (Tensor Operator Set Architecture) is Arm's operator set for the tensor
// graphs of the **ARM data-graph ecosystem**. That is a different kind of thing
// from a Vulkan extension, and the difference matters for everything below:
//
//   * There is no VK_* extension and no device feature bit. TOSA is an extended
//     instruction set, named by the string in OpExtInstImport. A module opts in by
//     importing it, and there is no command-line flag that selects or refuses it.
//   * A TOSA operation is a *graph* operation: an application hands a whole graph
//     of them to a runtime, which compiles or interprets it for whichever
//     accelerator the device has. A single compute shader full of TOSA
//     instructions, which is what this file compiles to, is not yet that graph -
//     see "What is missing" below.
//
// The compiler emits, for the shader below:
//
//   OpCapability TensorsARM
//   OpExtension "SPV_ARM_tensors"
//   %1 = OpExtInstImport "TOSA.001000.1"
//   %tf = OpTypeTensorARM %float
//   %ti = OpTypeTensorARM %int
//   %tb = OpTypeTensorARM %bool
//   %add = OpExtInst %tf %1 ADD %a %b
//   %abs = OpExtInst %tf %1 ABS %add
//   %max = OpExtInst %tf %1 MAXIMUM %int_1 %abs %b        ; nan_mode = IGNORE
//   %shape = OpConstantComposite %v2int %int_4 %int_4    ; int2(4,4)
//   %res = OpExtInst %tf %1 RESHAPE %max %shape
//   %cast = OpExtInst %tf %1 CAST %i
//   %cmp = OpExtInst %tb %1 GREATER %res %cast
//   %sel = OpExtInst %tf %1 SELECT %cmp %res %cast
//   %sum = OpExtInst %tf %1 REDUCE_SUM %int_0 %sel         ; axis 0
//   %mul = OpExtInst %tf %1 MATMUL %sum %cast %int_0 %int_0
//
// (%a, %b, ... above stand for OpLoad results from each temporary's Function-storage
// variable, which is where an opaque value has to live; the ids are elided.)
//
// Two things in that listing are worth reading twice. The first is the capability
// pair: TOSA has no capability of its own, and what the module declares belongs to
// the *operand type*. OpTypeTensorARM is in SPV_ARM_tensors, so every TOSA
// operation drags in OpCapability TensorsARM and OpExtension "SPV_ARM_tensors",
// which <vk/arm/tosa.h> requests with [[vk::ext_capability]] and
// [[vk::ext_extension]]. The second is the operand order, which is the
// instruction's and not the mnemonic's: MAXIMUM takes nan_mode *first*, TRANSPOSE
// takes its permutation first, and MUL, NEGATE and MATMUL take their attribute
// operands *last*.
//
// The type comes from <vk/arm/tosa.h>, because HLSL has no tensor type:
// vk::arm::tosa::Tensor<float> is an inline SPIR-V type, OpTypeTensorARM (4163)
// over %float. That type has two optional operands the alias does not use: the Rank
// is expressible (an id of an integer constant) and the Shape is not (an id of a
// constant composite, which the vk:: template machinery cannot build). So a TOSA
// tensor in this compiler has neither, and a consumer reads the shape from the
// graph that produced it - which is where a data-graph runtime keeps it anyway.
// tosa.ranked-tensor.hlsl in the test suite shows the ranked spelling for a
// declaration you write yourself.
//
// A tensor is opaque: no instruction here reads or writes one of its elements, and
// TOSA's own set has no read-element operation. The values in this shader are
// therefore uninitialized until a data-graph entry point supplies them, which is
// what the `// (no producer yet)` comments below are about. This example compiles
// and validates; it is not a runnable kernel.
//
// What is missing, and why this is a compile-only example:
//
//   * No data-graph entry point. OpGraphARM, OpGraphEntryPointARM and the rest of
//     the OpGraph*ARM family (SPV_ARM_graph, OpCapability GraphARM) are what make a
//     module a *graph* rather than a kernel. Nothing in DXC emits them, so a
//     runtime that requires TOSA operations inside a graph will not accept this
//     module. That is a front-end feature - a new kind of entry point - not
//     something an HLSL header can supply.
//   * No tensor resource. SPV_ARM_tensors makes OpTypeTensorARM a descriptor type,
//     but HLSL has no resource-object spelling for it: a global of an opaque type
//     lands in $Globals, and an RWStructuredBuffer of one embeds the opaque type in
//     a StructBlock, which is not a descriptor. A tensor value can only come from
//     another TOSA operation today.
//   * No constant tensor, for the same reason the Shape operand is missing.
//
// What the host has to do - none of which the compiler can check:
//
//   * Establish that the device supports the Arm data-graph model at all, and that
//     its TOSA implementation provides the operations this module uses, at the
//     profile and level the application targets. TOSA is a profile-and-level
//     specification: which of its 66 operations a device implements, in which of
//     its extensions (int16, fp8, bf16, control flow, ...), is discovered at
//     runtime from the implementation and never from the SPIR-V module. ADD in a
//     module says nothing about whether the device can execute ADD.
//   * Match the *version*. The import string is "TOSA.001000.1" - TOSA 1.0 rev 1 -
//     and a consumer looks the set up by that exact string. A different version is a
//     different string and a different opcode table, and DXC refuses one
//     (tosa.identifiers.error.hlsl pins the diagnostic), because the number alone
//     identifies nothing.
//   * Query implementation quality and any TOSA extension separately; nothing in
//     this module requests them.
//
// Numeric conformance is the implementation's: TOSA specifies behaviour, but no CI
// in this repository executes a single one of these operations, so no test here
// proves that ADD adds.

#include <vk/arm/tosa.h>

using namespace vk::arm::tosa;

RWStructuredBuffer<float> g_out : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // (no producer yet) An elementwise arithmetic chain. Each call is one OpExtInst
  // and nothing else: no library, no inlining, no compiler-generated wrapper.
  Tensor<float> a;
  Tensor<float> b;
  Tensor<float> sum = Add(a, b);   // ADD %a %b
  Tensor<float> mag = Abs(sum);    // ABS %sum
  // nan_mode is the *first* operand of MAXIMUM and MINIMUM, and it is an <id> of a
  // constant in the encoding, which is what the enumerator lowers to. IGNORE (1)
  // returns the other operand instead of propagating a NaN.
  Tensor<float> bounded = Maximum(NanModeIgnore, mag, b); // MAXIMUM %int_1 %mag %b

  // A shape operation. The shape is a constant integer vector, which lowers to an
  // OpConstantComposite - the id form TOSA wants:
  //   %shape = OpConstantComposite %v2int %int_4 %int_4
  // Nothing checks its length against the tensors, because the tensors carry no
  // rank in their type; "2 elements" here matches a rank-2 tensor by convention
  // only, and getting it wrong produces a module that validates and is not a valid
  // TOSA graph.
  Tensor<float> shaped = Reshape(bounded, int2(4, 4)); // RESHAPE %bounded %shape

  // A conversion, whose result element type differs from the operand's. Cast is
  // the one operation whose element type changes, which is what makes it a useful
  // check that the header's result types are spelled correctly.
  Tensor<int> i;
  Tensor<float> asFloat = Cast<float>(i); // CAST %i

  // A predicate and a select. Comparisons produce a Tensor<bool>, which is exactly
  // what Select's first operand has to be, so comparisons compose with Select and
  // with nothing else.
  Tensor<bool> pred = Greater(shaped, asFloat);      // GREATER %shaped %asFloat
  Tensor<float> picked = Select(pred, shaped, asFloat); // SELECT %pred %shaped %asFloat

  // A reduction and a contraction. Both are where the operand order catches people
  // out: the reduction axis comes *before* the data operand, and MATMUL's two zero
  // points come *after* both matrices.
  Tensor<float> reduced = ReduceSum(0, picked);     // REDUCE_SUM %int_0 %picked
  Tensor<float> product = MatMul(reduced, asFloat, 0, 0); // MATMUL %reduced %asFloat %int_0 %int_0

  // The chain's result is dead until a data-graph entry point can consume it; the
  // store keeps the compiler from treating the tail of the chain as unused at -Od.
  g_out[tid.x] = float(tid.x);
}
