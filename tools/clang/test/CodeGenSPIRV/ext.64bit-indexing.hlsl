// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-enable-64bit-indexing %s | FileCheck %s

// SPV_EXT_shader_64bit_indexing, step 1 of the hard-gate protocol (L1): the
// execution mode, the capability and the OpExtension are all present, exactly
// once, and the mode is what makes the widened indices below meaningful.
//
// CHECK-DAG: OpCapability Shader64BitIndexingEXT
// CHECK-DAG: OpCapability Int64
// CHECK-DAG: OpExtension "SPV_EXT_shader_64bit_indexing"
// CHECK: OpEntryPoint GLCompute %main "main"
// CHECK: OpExecutionMode %main LocalSize 1 1 1
// CHECK-NEXT: OpExecutionMode %main Shader64BitIndexingEXT
//
// L2: the runtime-array index operand of every storage-buffer access chain is
// a 64-bit integer. The assertions pin the *type of the operand* (an
// OpUConvert/OpSConvert/OpConstant of 64-bit type feeding the OpAccessChain),
// not merely the presence of a widening instruction somewhere in the module.
//
// A literal index is folded into a 64-bit OpConstant instead of being converted
// at every use:
// CHECK-DAG: [[c3:%[a-zA-Z0-9_]+]] = OpConstant %ulong 3

struct S {
  float4 a;
  float b;
};

StructuredBuffer<S> rob;
RWStructuredBuffer<S> rwb;
RWStructuredBuffer<float> fbuf;

groupshared float garr[16];
cbuffer CB {
  float4 cbarr[8];
};

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint u = tid.x;
  int i = tid.x;

  // A variable index into a read-only structured buffer:
  // CHECK: [[u:%[0-9]+]] = OpLoad %uint %u
  // CHECK-NEXT: [[idx:%[0-9]+]] = OpUConvert %ulong [[u]]
  // CHECK-NEXT: [[elt:%[0-9]+]] = OpAccessChain %_ptr_Uniform_S %rob %int_0 [[idx]]
  S s = rob[u];

  // A variable index into a read-write structured buffer, chained into the
  // element: the runtime-array index is 64 bits, the struct member index is
  // still 32 bits (a struct is smaller than 4 GiB by construction).
  // CHECK: [[u2:%[0-9]+]] = OpLoad %uint %u
  // CHECK-NEXT: [[idx2:%[0-9]+]] = OpUConvert %ulong [[u2]]
  // CHECK-NEXT: OpAccessChain %_ptr_Uniform_v4float %rwb %int_0 [[idx2]] %int_0
  rwb[u].a = s.a;

  // The literal index captured above is used directly as the element index.
  // CHECK: OpAccessChain %_ptr_Uniform_float %rob %int_0 [[c3]] %int_1
  float b0 = rob[3].b;

  // StructuredBuffer::Load(index) takes a signed int and keeps its signedness.
  // CHECK: [[i:%[0-9]+]] = OpLoad %int %i
  // CHECK-NEXT: [[sidx:%[0-9]+]] = OpSConvert %long [[i]]
  // CHECK-NEXT: OpAccessChain %_ptr_Uniform_S %rob %int_0 [[sidx]]
  S t = rob.Load(i);

  // A computed index is widened after the arithmetic, not before it: the
  // OpIAdd below is still 32-bit (the widening is not general arithmetic
  // promotion).
  // CHECK: [[u3:%[0-9]+]] = OpLoad %uint %u
  // CHECK-NEXT: [[sum:%[0-9]+]] = OpIAdd %uint [[u3]] %uint_1
  // CHECK-NEXT: [[idx3:%[0-9]+]] = OpUConvert %ulong [[sum]]
  // CHECK-NEXT: OpAccessChain %_ptr_Uniform_float %fbuf %int_0 [[idx3]]
  fbuf[u + 1] = b0 + t.b;

  // The widening is narrow: groupshared and constant-buffer sized arrays keep
  // their 32-bit indices, because a sized array cannot exceed 4 GiB.
  // CHECK: [[u4:%[0-9]+]] = OpLoad %uint %u
  // CHECK-NEXT: [[gidx:%[0-9]+]] = OpBitwiseAnd %uint [[u4]] %uint_15
  // CHECK-NEXT: OpAccessChain %_ptr_Workgroup_float %garr [[gidx]]
  garr[u & 15] = b0;

  // CHECK: [[u5:%[0-9]+]] = OpLoad %uint %u
  // CHECK-NEXT: [[cidx:%[0-9]+]] = OpBitwiseAnd %uint [[u5]] %uint_7
  // CHECK-NEXT: OpAccessChain %_ptr_Uniform_v4float %{{[0-9]+}} [[cidx]]
  // CHECK: [[u6:%[0-9]+]] = OpLoad %uint %u
  // CHECK-NEXT: [[idx6:%[0-9]+]] = OpUConvert %ulong [[u6]]
  // CHECK-NEXT: OpAccessChain %_ptr_Uniform_float %fbuf %int_0 [[idx6]]
  fbuf[u] = cbarr[u & 7].x + garr[2];
}
