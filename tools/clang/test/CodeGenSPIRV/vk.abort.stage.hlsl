// RUN: %dxc -T ps_6_0 -E main_ps -fcgl -fspv-extension=SPV_KHR_abort %s -spirv | FileCheck %s --check-prefix=PS
// RUN: %dxc -T vs_6_0 -E main_vs -fcgl -fspv-extension=SPV_KHR_abort %s -spirv | FileCheck %s --check-prefix=VS

// SPV_KHR_abort is available in every shader stage, and it is not `discard`.
//
// SPV_KHR_abort attaches no execution-model restriction to OpAbortKHR: the text
// says only "Ceases all further processing in the invocation that executes it"
// and "This instruction must be the last instruction in a block", and
// SPIRV-Tools registers no RegisterExecutionModelLimitation for it
// (source/val/validate_misc.cpp), unlike OpKill and OpTerminateInvocation which
// are fragment-only. In validate_cfg.cpp the instruction ends a block with no
// successors, exactly like OpUnreachable, which is legal in every stage.
//
// The two runs are the evidence: a fragment and a vertex shader, both validated
// by the shipped SPIRV-Tools before dxc exits. The PS run also carries the
// anti-false-green assertion the gate plan asks for: `discard` and abort are
// different operations - discard demotes the invocation to a helper invocation
// (OpDemoteToHelperInvocationEXT) or kills it (OpKill) but lets the rest of the
// shader run, while abort terminates the invocation with a message - so a
// fragment shader that only aborts must contain neither OpKill nor
// OpDemoteToHelperInvocation. If the abort were wired into doDiscardStmt, or the
// discard path into OpAbortKHR, those CHECK-NOTs fail.
//
// The vertex run pins the other half: the abort in the `if` does not disturb the
// function's return path, so the merge block still returns the output struct.

#include <vk/ext/abort.h>

struct VSOut {
  float4 pos : SV_Position;
  uint code : TEXCOORD0;
};

float4 main_ps(float4 color : COLOR) : SV_Target {
  if (color.x > 0.5) {
    vk::Abort(0x00C0FFEE);
  }
  return color;
}

VSOut main_vs(uint id : SV_VertexID) {
  VSOut o;
  o.pos = float4(0, 0, 0, 1);
  o.code = id;
  if (id > 100) {
    vk::Abort(id);
  }
  return o;
}

// PS:      OpCapability Shader
// PS-NEXT: OpCapability AbortKHR
// PS-NEXT: OpExtension "SPV_KHR_abort"
// PS-NEXT: OpMemoryModel Logical GLSL450
// PS:      OpEntryPoint Fragment
// PS-NOT:  OpKill
// PS-NOT:  OpDemoteToHelperInvocation
// PS-NOT:  OpTerminateInvocation
// PS:      OpAbortKHR %uint %uint_12648430
// The abort is the last instruction of the branch block, and the merge block
// still returns the colour.
// PS-NEXT: OpLabel
// PS:      OpReturnValue
// PS-NEXT: OpFunctionEnd

// VS:      OpCapability Shader
// VS-NEXT: OpCapability AbortKHR
// VS-NEXT: OpExtension "SPV_KHR_abort"
// VS-NEXT: OpMemoryModel Logical GLSL450
// VS:      OpEntryPoint Vertex
// VS-NOT:  OpKill
// VS-NOT:  OpDemoteToHelperInvocation
// VS:      [[ABORT:OpAbortKHR %uint %[0-9A-Za-z_]+]]
// VS-NEXT: OpLabel
// VS:      OpReturnValue
// VS-NEXT: OpFunctionEnd
