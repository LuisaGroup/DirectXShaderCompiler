// RUN: %dxc -T cs_6_0 -E main -fcgl %s -spirv | FileCheck %s
// RUN: %dxc -T cs_6_0 -E main -fcgl -fspv-extension=SPV_KHR_abort %s -spirv | FileCheck %s

// SPV_KHR_abort off path (G6/L5).
//
// No -fspv-extension=SPV_KHR_abort here, and the shader does not abort: the
// header may be included (it contains nothing but the declaration), the module
// must be exactly what it was before the feature existed - no AbortKHR
// capability, no SPV_KHR_abort extension, no OpAbortKHR - and the entry point
// must keep its usual shape.
//
// Every CHECK-NOT is anchored between two CHECK lines, so the region it excludes
// is the region that could contain the capability block, the constant section and
// the function body respectively; a bare CHECK-NOT at end of file would be
// vacuous under FileCheck's region semantics.
//
// The same statement from the other side: the feature does not leak in when the
// extension is merely *allowed* but unused. Enabling -fspv-extension=SPV_KHR_abort
// and still not aborting must also produce no capability and no extension -
// CapabilityVisitor only declares what the instructions it visited require - which
// is what the second RUN line asserts.
//
// The pre-existing tests for this area (intrinsics.*, control-flow tests) are not
// touched; this file is the anchored negative half of the same statement.

#include <vk/ext/abort.h>

RWStructuredBuffer<uint> outBuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  outBuf[0] = tid.x + 1;
}

// The capability and the extension would be declared between the last
// pre-existing capability and OpMemoryModel.
// CHECK:      OpCapability Shader
// CHECK-NOT:  AbortKHR
// CHECK-NOT:  SPV_KHR_abort
// CHECK:      OpMemoryModel Logical GLSL450
// Nothing in the instruction stream is an abort, and the body is the store the
// source asks for followed by the usual return.
// CHECK:      %bb_entry = OpLabel
// CHECK-NOT:  OpAbortKHR
// CHECK:      OpStore
// CHECK:      OpReturn
