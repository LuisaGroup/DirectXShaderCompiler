// RUN: %dxc -T cs_6_0 -E main -fcgl %s -spirv | FileCheck %s

// L5 gate: with no graph declared, nothing changes.
//
// <vk/arm/graph.h> is a header of declaration-only entry points; including it and
// calling nothing from it has to leave the module exactly as it was. That is the
// other half of the L1 gate - the capability and the extension are requested by
// 'vk::arm::GraphBegin' itself, because the graph region is not part of the tree
// CapabilityVisitor walks, so there is nothing else that could add them.
//
// This file deliberately includes every header the feature needs, so that a
// header-level change (an attribute that emits something, a global initializer)
// cannot hide here. The RUN line passes no -fspv-extension: SPV_ARM_graph is
// enabled by default, so an accidental emission would not be masked by a missing
// flag either.

#include <vk/arm/graph.h>
#include <vk/arm/tensors.h>
#include <vk/arm/tosa.h>

// The module's shape is unchanged: one compute entry point, one LocalSize, one
// function, and a body that is just a return.
// CHECK: OpCapability Shader
// CHECK-NOT: GraphARM
// CHECK-NOT: SPV_ARM_graph
// CHECK-NOT: OpTypeGraphARM
// CHECK-NOT: OpGraphARM
// CHECK-NOT: OpGraphEntryPointARM
// CHECK-NOT: OpGraphInputARM
// CHECK-NOT: OpGraphSetOutputARM
// CHECK-NOT: OpGraphEndARM
// CHECK: OpMemoryModel Logical GLSL450
// CHECK: OpEntryPoint GLCompute %[[MAIN:[A-Za-z0-9_]+]] "main"
// CHECK: OpExecutionMode %[[MAIN]] LocalSize 1 1 1
// CHECK: %[[MAIN]] = OpFunction
// CHECK: OpLabel
// CHECK: OpReturn
// CHECK: OpFunctionEnd

// The same exclusions again, from the last function to the end of the file: the
// graph region, if it were emitted, would be here.
// CHECK-NOT: GraphARM
// CHECK-NOT: OpGraphEndARM

[numthreads(1, 1, 1)]
void main() {
  // No 'vk::arm::GraphBegin'. Using the tensor type alone still produces
  // OpTypeTensorARM and TensorsARM (that is SPV_ARM_tensors' own L1 gate), which
  // this file does not exercise either: the point is that the graph header by
  // itself adds nothing.
}
