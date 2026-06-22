// RUN: not %dxc -T ps_6_0 -E main -spirv -HV 2016 %s 2>&1 | FileCheck %s

// CHECK: unknown type name 'int8_t'
// CHECK: unknown type name 'int8_t'
// CHECK: unknown type name 'int8_t'

void main() {
    int8_t a = 5;
    int8_t2 b;
    int8_t2x3 c;
}
