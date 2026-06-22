// RUN: not %dxc -T ps_6_2 -HV 2018 -E main %s 2>&1 | FileCheck %s

// CHECK: int8_t is only supported with -spirv
// CHECK: int8_t is only supported with -spirv
// CHECK: int8_t is only supported with -spirv
// CHECK: int8_t is only supported with -spirv

void main() {
    int8_t a = 5;       // existing scalar test
    int8_t2 b;          // vector should also error
    int8_t2x3 c;        // matrix should also error
    uint8_t3 d;         // unsigned vector should also error
}
