// RUN: not %dxc -T cs_6_0 -E main -HV 2018 %s 2>&1 | FileCheck %s

// bfloat16_t is not supported by the DXIL backend; it is rejected in Sema
// rather than silently miscompiled.

// CHECK: error: bfloat16_t is only supported with -spirv (Vulkan SPIR-V backend).
[numthreads(1, 1, 1)]
void main() {
  bfloat16_t x;
  x = x;
}
