// RUN: %dxc -T ps_6_2 -HV 2018 -E main -spirv %s | FileCheck %s

// CHECK: OpCapability Int8

void main() {
    int8_t2 a = int8_t2(1, 2);
    int8_t2 b = int8_t2(3, 4);
    uint8_t2 c = uint8_t2(5, 6);
    uint8_t2 d = uint8_t2(7, 8);

    // Arithmetic on signed int8 vectors
    int8_t2 r1 = a + b;
    int8_t2 r2 = a - b;
    int8_t2 r3 = a * b;
    int8_t2 r4 = a / b;
    int8_t2 r5 = a % b;

    // Arithmetic on unsigned int8 vectors
    uint8_t2 r6 = c + d;
    uint8_t2 r7 = c - d;
    uint8_t2 r8 = c * d;
    uint8_t2 r9 = c / d;
    uint8_t2 r10 = c % d;

    // Bitwise on unsigned int8 vectors
    uint8_t2 r11 = c & d;
    uint8_t2 r12 = c | d;
    uint8_t2 r13 = c ^ d;
    uint8_t2 r14 = c << d;
    uint8_t2 r15 = c >> d;

    // Comparisons
    bool2 r16 = (a == b);
    bool2 r17 = (a != b);
    bool2 r18 = (a < b);
    bool2 r19 = (a <= b);
    bool2 r20 = (a > b);
    bool2 r21 = (a >= b);

    // Mixed signedness operations
    int8_t2 r22 = a + int8_t2(c);
    uint8_t2 r23 = c + uint8_t2(a);

    // Compound assignments
    a += b;
    a -= b;
    a *= b;
    a /= b;
    a %= b;

    c &= d;
    c |= d;
    c ^= d;
}
