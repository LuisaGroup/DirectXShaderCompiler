// RUN: not %dxc -T cs_6_0 -E main -fcgl -spirv -HV 2021 -fspv-target-env=vulkan1.3 %s 2>&1 | FileCheck %s
// SPV_EXT_cooperative_matrix_maintenance1: a reduce mode that is not a
// compile-time constant (G16/L4).
//
// The CooperativeMatrixReduce operand of OpCooperativeMatrixReduceEXT (5366) is
// a literal bit mask - Row = 1, Column = 2, Row|Column = 3, 2x2 = 4 - and not an
// <id>, so a mode that is only known at run time cannot be encoded at all.
// Emitting the <id> that happens to hold it produces a module SPIRV-Tools
// rejects at the binary-parsing stage with
//   "Invalid cooperative matrix reduce operand: <id> has invalid mask component"
// so Reduce takes the mode as its third template argument and the two-argument
// form below is diagnosed at compile time by instantiating a class template that
// has no definition at all (vk::khr::ReduceModeMustBeAConstant<false>).
//
// The note that follows the error points at the call site below.
// CHECK: error: implicit instantiation of undefined template 'vk::khr::ReduceModeMustBeAConstant<false>'
// CHECK: note: in instantiation of function template specialization
// CHECK-SAME: Reduce<16, 1>
#include <vk/khr/cooperative_matrix.h>

RWStructuredBuffer<int> outbuf;
int stride;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint mode : MODE) {
  using Acc = vk::khr::CooperativeMatrixAccumulator<int, vk::ScopeSubgroup, 16, 16>;
  using AccRow = vk::khr::CooperativeMatrixAccumulator<int, vk::ScopeSubgroup, 16, 1>;

  Acc acc = Acc::Splat(1);
  // A constant mode is spelled Reduce<rows, columns, mode>():
  //   acc.Reduce<16, 1, vk::CooperativeMatrixReduceRow>()
  // Passing it as a run-time argument instead is the mistake this file pins.
  AccRow reduced = acc.Reduce<16, 1>(mode);
  reduced.Store<vk::CooperativeMatrixLayoutRowMajorKHR>(outbuf, 0, stride);
}
