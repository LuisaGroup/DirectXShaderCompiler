// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv %s | FileCheck %s

// L5: with the flag absent the module is exactly what it was before
// SPV_EXT_shader_64bit_indexing landed: no execution mode, no capability, no
// OpExtension, no 64-bit index type, and 32-bit element indices.
//
// The CHECK-NOTs are anchored between two CHECK lines that bracket the only
// region that could contain the thing being excluded, so they are not vacuous:
//   * the capability/extension block sits between the first OpCapability and
//     OpMemoryModel (Shader64BitIndexingEXT is emitted *before* OpCapability
//     Shader, so the anchor must start at the first capability);
//   * the execution modes sit between OpEntryPoint and OpSource;
//   * the index operands sit inside the emitted functions.
//
// CHECK: OpCapability MinLod
// CHECK-NOT: OpCapability Shader64BitIndexingEXT
// CHECK-NOT: OpExtension "SPV_EXT_shader_64bit_indexing"
// CHECK: OpMemoryModel Logical GLSL450
// CHECK: OpEntryPoint GLCompute %main "main"
// CHECK: OpExecutionMode %main LocalSize 1 1 1
// CHECK-NOT: OpExecutionMode %main Shader64BitIndexingEXT
// CHECK: OpSource HLSL 600
//
// The module does not even declare a 64-bit integer type: the region between the
// 32-bit integer type and the float type is exactly where a %ulong would be
// emitted.
// CHECK: %uint = OpTypeInt 32 0
// CHECK-NOT: OpTypeInt 64
// CHECK: %float = OpTypeFloat 32

struct S {
  float4 a;
  float b;
};

StructuredBuffer<S> rob;
RWStructuredBuffer<S> rwb;
RWStructuredBuffer<float> fbuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint u = tid.x;
  int i = tid.x;

  // The element index stays a 32-bit value: no convert is inserted between the
  // OpLoad and the OpAccessChain.
  // CHECK: [[u:%[0-9]+]] = OpLoad %uint %u
  // CHECK-NEXT: OpAccessChain %_ptr_Uniform_S %rob %int_0 [[u]]
  S s = rob[u];

  // CHECK: [[lidx:%[0-9]+]] = OpLoad %int %i
  // CHECK-NEXT: OpAccessChain %_ptr_Uniform_S %rob %int_0 [[lidx]]
  S t = rob.Load(i);

  // A literal index is the 32-bit constant it always was.
  // CHECK: OpAccessChain %_ptr_Uniform_float %rob %int_0 %uint_3 %int_1
  float b0 = rob[3].b;

  // CHECK: [[u2:%[0-9]+]] = OpLoad %uint %u
  // CHECK-NEXT: [[sum:%[0-9]+]] = OpIAdd %uint [[u2]] %uint_1
  // CHECK-NEXT: OpAccessChain %_ptr_Uniform_float %fbuf %int_0 [[sum]]
  fbuf[u + 1] = b0 + t.b;

  // CHECK: [[u3:%[0-9]+]] = OpLoad %uint %u
  // CHECK-NEXT: OpAccessChain %_ptr_Uniform_v4float %rwb %int_0 [[u3]] %int_0
  rwb[u].a = s.a;

}
