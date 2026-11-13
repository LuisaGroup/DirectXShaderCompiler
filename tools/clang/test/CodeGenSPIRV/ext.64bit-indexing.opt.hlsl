// RUN: %dxc -T cs_6_0 -E main -spirv -fspv-enable-64bit-indexing %s | FileCheck %s

// L6: without -fcgl the module goes through HLSL legalization, spirv-opt and the
// capability-trimming pass before it is emitted. This test catches the two
// failure modes that only appear there: the optimizer dropping the widened index
// arithmetic, and capability trimming removing Shader64BitIndexingEXT (which
// takes OpExtension "SPV_EXT_shader_64bit_indexing" with it). The compile itself
// is the L3 gate: dxc validates every module it emits, so a module that loses
// the capability but keeps a 64-bit index fails here with "Invalid SPIR-V"
// instead of a FileCheck error.
//
// CHECK-DAG: OpCapability Shader64BitIndexingEXT
// CHECK-DAG: OpCapability Int64
// CHECK-DAG: OpExtension "SPV_EXT_shader_64bit_indexing"
// CHECK: OpExecutionMode %main Shader64BitIndexingEXT
// CHECK-DAG: [[c3:%[a-zA-Z0-9_]+]] = OpConstant %ulong 3

struct S {
  float4 a;
  float b;
};

StructuredBuffer<S> rob;
RWStructuredBuffer<S> rwb;
RWStructuredBuffer<float> fbuf;

groupshared float garr[16];

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint u = tid.x;
  int i = tid.x;

  // The optimizer keeps the widened element index: an OpUConvert to %ulong that
  // directly feeds the runtime-array slot of the access chain.
  // CHECK: [[idx:%[0-9]+]] = OpUConvert %ulong
  // CHECK-NEXT: OpAccessChain %_ptr_Uniform_S %rob %int_0 [[idx]]
  S s = rob[u];

  // The literal index survives as a 64-bit constant.
  // CHECK: OpAccessChain %_ptr_Uniform_float %rob %int_0 [[c3]] %int_1
  float b0 = rob[3].b;

  // The signed path keeps %long / OpSConvert.
  // CHECK: [[sidx:%[0-9]+]] = OpSConvert %long
  // CHECK-NEXT: OpAccessChain %_ptr_Uniform_S %rob %int_0 [[sidx]]
  S t = rob.Load(i);

  // A write into a read-write structured buffer is widened too. The optimizer
  // CSEs the four widened indices of this shader into the single [[idx]] above;
  // if a pass-pipeline change stops doing that, this line needs updating, which
  // is the point of an L6 gate.
  // CHECK: OpAccessChain %_ptr_Uniform_float %fbuf %int_0 [[idx]]
  fbuf[u] = b0 + s.b + t.b;

  // The groupshared array keeps its 32-bit index even after optimization.
  // CHECK: OpAccessChain %_ptr_Workgroup_float %garr %{{[0-9]+}}
  garr[u & 15] = b0;

  // CHECK: OpAccessChain %_ptr_Uniform_v4float %rwb %int_0 [[idx]] %int_0
  rwb[u].a = s.a;
}
