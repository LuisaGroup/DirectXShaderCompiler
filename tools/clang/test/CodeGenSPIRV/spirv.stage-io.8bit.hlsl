// RUN: %dxc -T vs_6_2 -HV 2018 -E main -spirv %s | FileCheck %s

// CHECK: OpCapability Int8
// CHECK: OpExtension "SPV_KHR_8bit_storage"

struct VSOut {
    int8_t2  outA : A;
    uint8_t4 outB : B;
};

VSOut main(int8_t3 inA : A, uint8_t2 inB : B) {
    VSOut o;
    o.outA = inA.xy;
    o.outB = uint8_t4(inB, inB);
    return o;
}
