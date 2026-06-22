// RUN: %dxc -T ps_6_2 -HV 2018 -E main -spirv %s | FileCheck %s

// CHECK: OpCapability Int8

StructuredBuffer<int8_t4> buf;

int8_t4 main() : SV_Target {
    return buf[0];
}
