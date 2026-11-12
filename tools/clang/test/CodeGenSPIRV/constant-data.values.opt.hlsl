// RUN: %dxc -T cs_6_0 -E main -spirv -fspv-constant-data -fspv-extension=SPV_KHR_constant_data %s | FileCheck %s

// L6: this file is the only constant-data gate that does not pass -fcgl, so it
// runs legalization, spirv-opt and capability trimming.
//
// Nothing may drop the instruction or the capability that guards it: the packed
// constant is still an OpConstantDataKHR with the source values after the
// optimizer has removed the per-element OpConstant instructions that nothing
// references any more, the module still declares ConstantDataKHR, and the
// runtime index still reads the table through OpAccessChain + OpLoad.
// A validation failure (for example a wrong word count) is fatal for this
// compile, so this file is also the L3 gate.

// CHECK:      OpCapability Shader
// CHECK-NEXT: OpCapability ConstantDataKHR
// CHECK-NEXT: OpExtension "SPV_KHR_constant_data"

// CHECK: OpEntryPoint GLCompute %main "main" %gl_GlobalInvocationID

// CHECK: [[ARRTY:%_arr_uint_uint_8]] = OpTypeArray %uint %uint_8
// CHECK: [[DATA:%[0-9]+]] = OpConstantDataKHR [[ARRTY]] 11 22 33 44 55 66 77 88
// CHECK: OpStore %table [[DATA]]

// CHECK: [[IDX:%[0-9]+]] = OpUMod %uint {{%[0-9]+}} %uint_8
// CHECK: [[PTR:%[0-9]+]] = OpAccessChain %_ptr_Function_uint %table [[IDX]]
// CHECK: OpLoad %uint [[PTR]]

static const uint table[8] = {
  11, 22, 33, 44, 55, 66, 77, 88
};

RWStructuredBuffer<uint> outBuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  outBuf[0] = table[tid.x % 8];
}
