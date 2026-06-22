// RUN: %dxc -T ps_6_2 -HV 2018 -E main -spirv %s | FileCheck %s

// CHECK: OpCapability Int8

void main() {
    // Declarations
    int8_t2  a;
    int8_t3  b;
    int8_t4  c;
    uint8_t2 d;
    uint8_t3 e;
    uint8_t4 f;

    // Constants
    int8_t2  g = int8_t2(1, -2);
    uint8_t2 h = uint8_t2(255, 128);

    // Arithmetic
    int8_t2  i = a + g;
    int8_t2  j = a - g;
    int8_t2  k = a * g;
    int8_t2  l = a / g;
    int8_t2  m = a % g;

    // Bitwise
    uint8_t2 n = d & h;
    uint8_t2 o = d | h;
    uint8_t2 p = d ^ h;

    // Comparisons
    bool2 q = (a == g);
    bool2 r = (a != g);
    bool2 s = (a < g);
    bool2 t = (a > g);

    // Swizzles
    int8_t4 u = c.xxyy;
    int8_t2 v = c.wz;

    // Casts
    uint8_t2 w = uint8_t2(a);
    int8_t2 x = int8_t2(w);

    // Compound assign
    a += g;
    a -= g;
    a *= g;
    a /= g;
    a %= g;

    // Unary ops
    int8_t2 y = -a;
    int8_t2 z = +a;
}
