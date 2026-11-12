// RUN: not %dxc -T cs_6_4 -E main -enable-16bit-types -fcgl -fspv-extension=SPV_VALVE_mixed_float_dot_product %s -spirv 2>&1 | FileCheck %s

// HLSL Change - SPV_VALVE_mixed_float_dot_product, gate G11/L4 (reachability of
// the non-FP16 variants).
//
// SPV_VALVE_mixed_float_dot_product also defines a bfloat16 form
// (DotProductBFloat16AccVALVE, 6914) and an FP8 form
// (DotProductFloat8AccFloat32VALVE, 6915, whose grammar dependency is the
// Float8EXT capability of SPV_EXT_float8). Neither is reachable from HLSL
// today, and this test pins the reason for bfloat16: HLSL declares a single
// dot2add overload,
//     float dot2add(in float16_t<2> a, in $type1 b, in float c);
//     (utils/hct/gen_intrin_main.txt)
// so there is no `bfloat16_t2` overload to resolve against, and bfloat16_t is
// not implicitly convertible to half. Producing OpFDot2MixAcc32VALVE with
// bfloat16 operands would therefore need a new intrinsic surface -- a
// `bfloat16_t2` overload of dot2add (which DXIL does not have either) plus the
// DotProductBFloat16AccVALVE capability -- and converting explicitly to half2
// instead would silently change the encoding (bfloat16 has 8 mantissa bits and
// fp16 has 10, with different exponent ranges).
//
// The FP8 variant needs the whole SPV_EXT_float8 type system (OpTypeFloat 8 with
// a Float8E4M3/Float8E5M2 encoding, the Float8EXT capability) and an
// OpFDot4MixAcc32VALVE (6918) surface with 4-component input vectors; none of
// that exists in this tree, so it is not faked here.
//
// CHECK: error: cannot initialize a parameter of type 'vector<half, 2>' with an lvalue of type 'vector<bfloat16_t, 2>'
// CHECK: outBuf[0] = dot2add(a, b, acc);
RWStructuredBuffer<float> outBuf;

[numthreads(1, 1, 1)]
void main() {
  bfloat16_t2 a = bfloat16_t2(1.5, 2.5);
  bfloat16_t2 b = bfloat16_t2(3.5, 4.5);
  float acc = 0.25;
  outBuf[0] = dot2add(a, b, acc);
}
