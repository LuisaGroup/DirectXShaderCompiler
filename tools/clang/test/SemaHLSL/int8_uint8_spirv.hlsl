// RUN: %dxc -T ps_6_7 -E main -spirv -enable-16bit-types %s

int8_t main(int8_t a : A) : SV_Target { return a; }
