// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-enable-64bit-indexing %s 2>&1 | FileCheck %s --check-prefix=WARN
// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-enable-64bit-indexing %s | FileCheck %s --check-prefix=ENC
// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv %s 2>&1 | FileCheck %s --check-prefix=NOWARN

// L4: the index paths that -fspv-enable-64bit-indexing does not widen are
// diagnosed instead of silently keeping their 32-bit arithmetic. Only the
// storage buffer's runtime-sized array can exceed the 4 GiB range the
// VK_EXT_shader_64bit_indexing feature bit removes; a byte address buffer's
// offset and an append/consume counter are 32-bit HLSL values whose SPIR-V
// arithmetic the extension leaves alone, and widening the access-chain operand
// without widening the offset computation would claim a range the module does
// not have.
//
// The warning names the construct and says what stays 32 bits.
// WARN: warning: 64-bit indexing is enabled, but the index arithmetic of {{\(RW\)}}ByteAddressBuffer.Load/Store stays 32 bits wide
// WARN: warning: 64-bit indexing is enabled, but the index arithmetic of AppendStructuredBuffer::Append/ConsumeStructuredBuffer::Consume stays 32 bits wide
//
// No %ulong is needed for these two paths, so the module does not even declare a
// 64-bit integer type (the region between the 32-bit integer type and the float
// type is where one would be emitted).
// ENC: %uint = OpTypeInt 32 0
// ENC-NOT: OpTypeInt 64
// ENC: %float = OpTypeFloat 32
//
// The two paths keep their 32-bit arithmetic even with the flag on: the byte
// offset is still shifted in 32 bits and the counter is still a 32-bit value.
// ENC: [[off:%[0-9]+]] = OpShiftRightLogical %uint
// ENC: OpAccessChain %_ptr_Uniform_uint %rwbab %uint_0 [[off]]
// ENC: OpAccessChain %_ptr_Uniform_int %counter_var_abuf %uint_0
// ENC-NEXT: OpAtomicIAdd %int
//
// Without the flag there is no warning at all. The first CHECK-NOT covers the
// stream head (a shell-merged compile puts diagnostics first) and the last one
// covers the stream tail (a runner that concatenates stdout then stderr), so the
// diagnostic cannot hide at either end.
// NOWARN-NOT: 64-bit indexing is enabled
// NOWARN: OpCapability Shader
// NOWARN: OpEntryPoint GLCompute %main "main"
// NOWARN: OpAccessChain %_ptr_Uniform_uint %rwbab %uint_0
// NOWARN-NOT: 64-bit indexing is enabled

RWByteAddressBuffer rwbab;
AppendStructuredBuffer<float> abuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  uint u = tid.x;

  rwbab.Store(u * 4, u);
  abuf.Append(float(u));
}
