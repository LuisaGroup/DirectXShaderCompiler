// RUN: not %dxc -T cs_6_0 -E main -fcgl -HV 2021 -fspv-extension=SPV_QCOM_tile_shading %s -spirv 2>&1 | FileCheck %s

// G30/L4 gate: the operands TileShadingRateQCOM accepts.
//
// VK_QCOM_tile_shading narrows the mode to three rate operands, and to values
// SPIRV-Tools will accept:
//
//  - "The TileShadingRateQCOM execution mode's x and y values must be powers of
//    2" (z is the number of samples per pixel and has no such rule), and
//  - the mode carries exactly three LiteralInteger operands; a call with two or
//    four would otherwise be emitted as a malformed OpExecutionMode and rejected
//    far from the source.
//
// Both are checked in the compiler, in a compute shader - the only stage the mode
// is legal in - so the shader is diagnosed where the call is. Each error skips
// the offending declaration and codegen continues, which is why both appear in one
// compile. The valid call at the end is what qcom.tile-shading.rate.hlsl asserts
// reaches the module.

#include <vk/qcom/tile_shading.h>

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  // x = 3 is not a power of 2.
  // CHECK: error: the TileShadingRateQCOM execution mode's x and y rates must be powers of 2
  vk::ext_execution_mode(vk::qcom::ExecutionModeTileShadingRateQCOM, 3, 2, 1);
  // y = 6 is not a power of 2.
  // CHECK: error: the TileShadingRateQCOM execution mode's x and y rates must be powers of 2
  vk::ext_execution_mode(vk::qcom::ExecutionModeTileShadingRateQCOM, 2, 6, 1);
  // The z rate has no power-of-2 rule, but all three operands are required.
  // CHECK: error: the TileShadingRateQCOM execution mode requires three rate operands (x, y and z)
  vk::ext_execution_mode(vk::qcom::ExecutionModeTileShadingRateQCOM, 2, 2);
  // The mode takes literal operands, so the Id form has no encoding for it.
  // CHECK: error: TileShadingRateQCOM takes literal operands; declare it with vk::ext_execution_mode instead of vk::ext_execution_mode_id
  int rate = 2;
  vk::ext_execution_mode_id(vk::qcom::ExecutionModeTileShadingRateQCOM, rate,
                            rate, rate);
  // The valid form: y = 4 is a power of 2 and z = 3 is free.
  vk::ext_execution_mode(vk::qcom::ExecutionModeTileShadingRateQCOM, 2, 4, 3);
}
