// RUN: %dxc -T cs_6_0 -E main -fcgl %s -spirv | FileCheck %s

// L0/L1/L2 gates for the TOSA.001000.1 extended instruction set.
//
// TOSA is not a Vulkan extension: it is an extended instruction *set*, named by
// the string in OpExtInstImport, so the whole feature is reachable through
// [[vk::ext_instruction(<opcode>, "TOSA.001000.1")]] with no backend change. The
// surface is <vk/arm/tosa.h>, which declares 47 of the set's 66 operations.
//
// L0 (surface reachability): every entry point of the header is called by name
// below, once, so a declaration that does not compile or does not dispatch is a
// failure. The list is not the whole header by accident: tosa.entry-points.hlsl
// pins the closure rule, and this file pins the behaviour of the calls.
//
// L1 (capability and extension): TOSA has no capability and no extension string of
// its own. What the module does declare is the pair that its *operand type*
// requires - OpTypeTensorARM (4163) is in SPV_ARM_tensors, so every TOSA operation
// needs OpCapability TensorsARM (4174) and OpExtension "SPV_ARM_tensors". The
// header attaches both with [[vk::ext_capability]] / [[vk::ext_extension]] because
// FeatureManager has no SPIR-V-side entry for SPV_ARM_tensors to infer them from;
// they therefore appear exactly once each, and only when a TOSA operation is
// actually used (tosa.off.hlsl is the other half of that assertion).
//
// L2 (instruction encoding): each OpExtInst is asserted with its result type and
// with every operand position captured. The operand order is the order
// extinst.tosa.001000.1.grammar.json gives, which is not always the order the
// mnemonic suggests - MAXIMUM and MINIMUM put nan_mode first, TRANSPOSE puts the
// permutation first, MUL and NEGATE and MATMUL put their attribute operands last.
// A permuted operand list is the expensive mistake here: SPIRV-Tools only checks
// the *count* against the grammar, so a swap of two same-typed tensor operands
// validates and is silently wrong.
//
// L3 (module validity) is implicit: the RUN line does not pass -Vd, so dxc
// validates the module (SpirvEmitter::spirvToolsValidate). Note that the validator
// is what rejects an unknown opcode number and a wrong operand count, so those two
// mistakes cannot reach a passing test either.
//
// What this file cannot prove: numeric semantics. Nothing in CI implements TOSA,
// so this pins the encoding, not the arithmetic - the values are all uninitialized
// opaque tensors, and no operation is executed.

#include <vk/arm/tosa.h>

using namespace vk::arm::tosa;

// L1: exactly one OpCapability TensorsARM and exactly one
// OpExtension "SPV_ARM_tensors". Both CHECK-NOTs are anchored: the first runs from
// OpCapability Shader (which every module has) to TensorsARM itself, the second
// over the rest of the capability block, and the third over the rest of the
// extension block.
// CHECK: OpCapability Shader
// CHECK: OpCapability TensorsARM
// CHECK-NOT: OpCapability TensorsARM
// CHECK: OpExtension "SPV_ARM_tensors"
// CHECK-NOT: OpExtension "SPV_ARM_tensors"

// L1: the exact import string, once. It is the entire contract with the consumer:
// a different string is a different instruction set with a different opcode table,
// and tosa.identifiers.error.hlsl pins that the module is refused for one.
// CHECK: %[[TOSA:[0-9]+]] = OpExtInstImport "TOSA.001000.1"
// CHECK-NOT: OpExtInstImport

// The three tensor types this file materialises: OpTypeTensorARM (4163) over
// float, over int and over bool. The Rank and Shape operands are absent - HLSL
// can express Rank but not Shape, and a type that carries a Rank and no Shape is
// only half-specified, so the header emits neither. See tosa.ranked-tensor.hlsl
// for the spelling that does carry a rank.
// CHECK: %[[TENSOR_F:[A-Za-z0-9_]+]] = OpTypeTensorARM %float
// CHECK: %[[TENSOR_I:[A-Za-z0-9_]+]] = OpTypeTensorARM %int
// CHECK: %[[TENSOR_B:[A-Za-z0-9_]+]] = OpTypeTensorARM %bool

RWStructuredBuffer<float> g_out : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // Uninitialized opaque tensors: a TOSA value can only be produced by another
  // TOSA operation until a data-graph entry point supplies one, and nothing in
  // this test executes.
  Tensor<float> a;
  Tensor<float> b;
  Tensor<int> i;
  Tensor<int> j;
  Tensor<bool> p;
  Tensor<float> r;
  Tensor<int> s;
  Tensor<bool> q;

  // --- elementwise binary arithmetic: (input1, input2) ---
  // CHECK: %[[V1:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] ADD %{{[0-9]+}} %{{[0-9]+}}
  r = Add(a, b);
  // CHECK: %[[V2:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] SUB %{{[0-9]+}} %{{[0-9]+}}
  r = Sub(r, b);
  // CHECK: %[[V3:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] POW %{{[0-9]+}} %{{[0-9]+}}
  r = Pow(r, a);
  // MUL carries a third operand, the shift, *after* both data operands:
  // (input1, input2, shift). TOSA requires it for the floating-point form too.
  // CHECK: %[[V4:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] MUL %{{[0-9]+}} %{{[0-9]+}} %int_0
  r = Mul(r, a, 0);
  // MAXIMUM / MINIMUM carry nan_mode *first*: (nan_mode, input1, input2). The
  // enumerator is materialized as an OpConstant int, which is the id TOSA wants.
  // CHECK: %[[V5:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] MAXIMUM %int_1 %{{[0-9]+}} %{{[0-9]+}}
  r = Maximum(NanModeIgnore, r, a);
  // CHECK: %[[V6:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] MINIMUM %int_0 %{{[0-9]+}} %{{[0-9]+}}
  r = Minimum(NanModePropagate, r, a);

  // --- elementwise unary: (input1) ---
  // CHECK: %[[V7:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] ABS %{{[0-9]+}}
  r = Abs(r);
  // NEGATE is not unary in the encoding: (input1, input1_zp, output_zp).
  // CHECK: %[[V8:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] NEGATE %{{[0-9]+}} %int_0 %int_0
  r = Negate(r, 0, 0);
  // CHECK: %[[V9:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] EXP %{{[0-9]+}}
  r = Exp(r);
  // CHECK: %[[V10:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] LOG %{{[0-9]+}}
  r = Log(r);
  // CHECK: %[[V11:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] SIGMOID %{{[0-9]+}}
  r = Sigmoid(r);
  // CHECK: %[[V12:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] TANH %{{[0-9]+}}
  r = Tanh(r);
  // CHECK: %[[V13:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] ERF %{{[0-9]+}}
  r = Erf(r);
  // CHECK: %[[V14:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] CEIL %{{[0-9]+}}
  r = Ceil(r);
  // CHECK: %[[V15:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] FLOOR %{{[0-9]+}}
  r = Floor(r);
  // CHECK: %[[V16:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] RECIPROCAL %{{[0-9]+}}
  r = Reciprocal(r);
  // CHECK: %[[V17:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] RSQRT %{{[0-9]+}}
  r = Rsqrt(r);
  // CHECK: %[[V18:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] SIN %{{[0-9]+}}
  r = Sin(r);
  // CHECK: %[[V19:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] COS %{{[0-9]+}}
  r = Cos(r);

  // CLAMP has four operands: (min_val, max_val, nan_mode, input). The two bounds
  // are TOSA attributes that the instruction carries as operands, and they are of
  // the tensor's *element* type, so a float literal lowers to an OpConstant float.
  // CHECK: %[[V20:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] CLAMP %float_0 %float_1 %int_0 %{{[0-9]+}}
  r = Clamp(0.0, 1.0, NanModePropagate, r);

  // --- reductions: (axis, input) and (axis, nan_mode, input) ---
  // The axis comes before the data operand.
  // CHECK: %[[V21:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] REDUCE_SUM %int_0 %{{[0-9]+}}
  r = ReduceSum(0, r);
  // CHECK: %[[V22:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] REDUCE_PRODUCT %int_0 %{{[0-9]+}}
  r = ReduceProduct(0, r);
  // CHECK: %[[V23:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] REDUCE_MAX %int_0 %int_1 %{{[0-9]+}}
  r = ReduceMax(0, NanModeIgnore, r);
  // CHECK: %[[V24:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] REDUCE_MIN %int_0 %int_0 %{{[0-9]+}}
  r = ReduceMin(0, NanModePropagate, r);

  // --- shape operations, where the coefficient operand is a constant vector ---
  // RESHAPE: (input1, shape). The shape is an int2 literal, which the front end
  // materializes as an OpConstantComposite - the id form TOSA wants.
  // CHECK: %[[V25:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] RESHAPE %{{[0-9]+}} %{{[0-9]+}}
  r = Reshape(r, int2(4, 4));
  // TRANSPOSE puts the permutation *first*: (perms, input1).
  // CHECK: %[[V26:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] TRANSPOSE %{{[0-9]+}} %{{[0-9]+}}
  r = Transpose(int2(1, 0), r);
  // SLICE: (input1, start, size) - two coefficient vectors after the data.
  // CHECK: %[[V27:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] SLICE %{{[0-9]+}} %{{[0-9]+}} %{{[0-9]+}}
  r = Slice(r, int2(0, 0), int2(2, 2));
  // CHECK: %[[V28:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] TILE %{{[0-9]+}} %{{[0-9]+}}
  r = Tile(r, int2(2, 2));

  // --- variadic and matrix forms ---
  // CONCAT: (axis, input1*) - the axis first, then every concatenated tensor.
  // The header declares the two-tensor form, so three operands.
  // CHECK: %[[V29:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] CONCAT %int_0 %{{[0-9]+}} %{{[0-9]+}}
  r = Concat(0, r, a);
  // MATMUL: (A, B, A_zp, B_zp) - the two zero points last.
  // CHECK: %[[V30:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] MATMUL %{{[0-9]+}} %{{[0-9]+}} %int_0 %int_0
  r = MatMul(r, a, 0, 0);
  // CAST: (input), and the *result* type is the one that changes. Casting an int
  // tensor to a float tensor is the pairing TOSA CAST is for.
  // CHECK: %[[V31:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] CAST %{{[0-9]+}}
  r = Cast<float>(i);

  // --- integer operations ---
  // CHECK: %[[V32:[0-9]+]] = OpExtInst %[[TENSOR_I]] %[[TOSA]] INTDIV %{{[0-9]+}} %{{[0-9]+}}
  s = IntDiv(i, j);
  // CHECK: %[[V33:[0-9]+]] = OpExtInst %[[TENSOR_I]] %[[TOSA]] BITWISE_AND %{{[0-9]+}} %{{[0-9]+}}
  s = BitwiseAnd(i, j);
  // CHECK: %[[V34:[0-9]+]] = OpExtInst %[[TENSOR_I]] %[[TOSA]] BITWISE_OR %{{[0-9]+}} %{{[0-9]+}}
  s = BitwiseOr(s, j);
  // CHECK: %[[V35:[0-9]+]] = OpExtInst %[[TENSOR_I]] %[[TOSA]] BITWISE_XOR %{{[0-9]+}} %{{[0-9]+}}
  s = BitwiseXor(s, j);
  // CHECK: %[[V36:[0-9]+]] = OpExtInst %[[TENSOR_I]] %[[TOSA]] CLZ %{{[0-9]+}}
  s = Clz(s);
  // CHECK: %[[V37:[0-9]+]] = OpExtInst %[[TENSOR_I]] %[[TOSA]] BITWISE_NOT %{{[0-9]+}}
  s = BitwiseNot(s);

  // --- boolean operations, whose result type is a tensor of bool ---
  // CHECK: %[[V38:[0-9]+]] = OpExtInst %[[TENSOR_B]] %[[TOSA]] LOGICAL_AND %{{[0-9]+}} %{{[0-9]+}}
  q = LogicalAnd(i, j);
  // CHECK: %[[V39:[0-9]+]] = OpExtInst %[[TENSOR_B]] %[[TOSA]] LOGICAL_OR %{{[0-9]+}} %{{[0-9]+}}
  q = LogicalOr(q, q);
  // CHECK: %[[V40:[0-9]+]] = OpExtInst %[[TENSOR_B]] %[[TOSA]] LOGICAL_XOR %{{[0-9]+}} %{{[0-9]+}}
  q = LogicalXor(q, q);
  // CHECK: %[[V41:[0-9]+]] = OpExtInst %[[TENSOR_B]] %[[TOSA]] LOGICAL_NOT %{{[0-9]+}}
  q = LogicalNot(q);
  // CHECK: %[[V42:[0-9]+]] = OpExtInst %[[TENSOR_B]] %[[TOSA]] REDUCE_ALL %int_0 %{{[0-9]+}}
  q = ReduceAll(0, q);
  // CHECK: %[[V43:[0-9]+]] = OpExtInst %[[TENSOR_B]] %[[TOSA]] REDUCE_ANY %int_0 %{{[0-9]+}}
  q = ReduceAny(0, q);

  // --- comparisons and select ---
  // CHECK: %[[V44:[0-9]+]] = OpExtInst %[[TENSOR_B]] %[[TOSA]] EQUAL %{{[0-9]+}} %{{[0-9]+}}
  p = Equal(a, b);
  // CHECK: %[[V45:[0-9]+]] = OpExtInst %[[TENSOR_B]] %[[TOSA]] GREATER %{{[0-9]+}} %{{[0-9]+}}
  p = Greater(a, b);
  // CHECK: %[[V46:[0-9]+]] = OpExtInst %[[TENSOR_B]] %[[TOSA]] GREATER_EQUAL %{{[0-9]+}} %{{[0-9]+}}
  p = GreaterEqual(a, b);
  // SELECT: (input1, input2, input3), where input1 is the predicate tensor - the
  // one whose element type is bool, which is what makes Select's first operand
  // type-check - and the result type is the *data* type, not the predicate type.
  // CHECK: %[[V47:[0-9]+]] = OpExtInst %[[TENSOR_F]] %[[TOSA]] SELECT %{{[0-9]+}} %{{[0-9]+}} %{{[0-9]+}}
  r = Select(p, a, b);

  // The results are stored so that none of the calls is dead code at -fcgl.
  g_out[0] = float(tid.x);
}
