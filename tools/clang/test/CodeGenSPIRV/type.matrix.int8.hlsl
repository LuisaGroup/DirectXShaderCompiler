// RUN: %dxc -T ps_6_2 -HV 2018 -E main -spirv %s | FileCheck %s

// CHECK: OpCapability Int8

void main() {
    // Matrix declarations
    int8_t2x3 a;
    int8_t4x4 b;
    uint8_t2x3 c;
    uint8_t4x4 d;

    // Additional matrix dimensions
    int8_t3x3 e;
    int8_t2x2 f;
    int8_t3x4 g;
    int8_t4x2 h;

    uint8_t3x3 i;
    uint8_t2x2 j;
    uint8_t3x4 k;
    uint8_t4x2 l;
}
