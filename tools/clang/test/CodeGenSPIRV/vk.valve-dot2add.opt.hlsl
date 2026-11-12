// RUN: %dxc -T cs_6_4 -E main -enable-16bit-types -fspv-extension=SPV_VALVE_mixed_float_dot_product %s -spirv | FileCheck %s

// HLSL Change - SPV_VALVE_mixed_float_dot_product, gate G11/L6 (optimizer
// survival).
//
// No -fcgl: the module goes through legalization, spirv-opt and capability
// trimming before it is validated and printed, so this is the only test that
// shows the fused instruction is not dropped by DCE or by load widening and
// that the DotProductFloat16AccFloat32VALVE capability survives trimming
// together with the Float16 capability the VALVE capability depends on
// (DotProductFloat16AccFloat32VALVE carries `opcaps: Float16` in
// spirv.core.grammar.json).
//
// The inputs come from buffers so that nothing is constant folded away.
//
// L1 (post-optimization): the capability and the extension are both present, and
// exactly once.
// CHECK:      OpCapability Shader
// CHECK:      OpCapability Float16
// CHECK:      OpCapability DotProductFloat16AccFloat32VALVE
// CHECK-NOT:  OpCapability DotProductFloat16AccFloat32VALVE
// CHECK:      OpExtension "SPV_VALVE_mixed_float_dot_product"
// CHECK-NOT:  OpExtension "SPV_VALVE_mixed_float_dot_product"
// CHECK:      OpMemoryModel Logical GLSL450
// CHECK:      OpEntryPoint GLCompute %main "main"
// CHECK:      OpExecutionMode %main LocalSize 1 1 1
StructuredBuffer<float2> aBuf;
StructuredBuffer<float2> bBuf;
RWStructuredBuffer<float> outBuf;

[numthreads(1, 1, 1)]
void main() {
  half2 a = half2(aBuf[0]);
  half2 b = half2(bBuf[0]);
  // L2 (post-optimization): still one fused instruction, with the accumulator as
  // the third operand and the accumulator's type as the result type.
  // CHECK:      [[a:%[0-9]+]] = OpFConvert %v2half
  // CHECK:      [[b:%[0-9]+]] = OpFConvert %v2half
  // CHECK:      [[acc:%[0-9]+]] = OpLoad %float
  // CHECK-NOT:  OpFMul %v2half
  // CHECK-NOT:  OpFConvert %v2float
  // CHECK-NEXT: [[res:%[0-9]+]] = OpFDot2MixAcc32VALVE %float [[a]] [[b]] [[acc]]
  // CHECK-NEXT: [[ptr:%[0-9]+]] = OpAccessChain %_ptr_Uniform_float %outBuf
  // CHECK-NEXT: OpStore [[ptr]] [[res]]
  outBuf[0] = dot2add(a, b, outBuf[1]);
}
