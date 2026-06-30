// RUN: %dxc -T ps_6_9 -E main -enable-16bit-types %s
// RUN: not %dxc -T ps_6_8 -E main -enable-16bit-types %s 2>&1 | FileCheck %s --check-prefix=ERR

int8_t main(uint8_t a : A) : SV_Target { return (int8_t)a; }

// ERR: int8_t is only allowed for HLSL 6.9 and above.
// ERR: uint8_t is only allowed for HLSL 6.9 and above.
