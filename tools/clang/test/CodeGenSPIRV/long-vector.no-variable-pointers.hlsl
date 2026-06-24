// RUN: %dxc -fspv-target-env=vulkan1.3 -T cs_6_9 -E main -spirv -HV 2021 %s | FileCheck %s

// Test that VariablePointersStorageBuffer capability is NOT added for
// common long vectors (>4 components). Only cooperative vector/matrix
// types should trigger VariablePointersStorageBuffer.

// CHECK-NOT: VariablePointersStorageBuffer
// CHECK: OpCapability Shader

RWStructuredBuffer<float> buf : register(u0);

[numthreads(64, 1, 1)]
void main() {
  // 8-component vector - lowered as array, no cooperative type used
  vector<float, 8> v;
  v[0] = 1.0;
  v[7] = 8.0;
  buf[0] = v[0] + v[7];
}
