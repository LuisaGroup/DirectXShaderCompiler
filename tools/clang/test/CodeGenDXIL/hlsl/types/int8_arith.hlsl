// REQUIRES: dxil-1-9
// RUN: %dxc -T ps_6_9 -E main -enable-16bit-types -O0 %s | FileCheck %s

// CHECK-LABEL: define void @main()
int8_t main(int8_t a : A, int8_t b : B) : SV_Target {
  // CHECK: add{{.*}}i8
  // CHECK: sub{{.*}}i8
  // CHECK: mul{{.*}}i8
  // CHECK: sdiv i8
  // CHECK: srem i8
  // CHECK: shl i8
  // CHECK: ashr i8
  // CHECK: and i8
  // CHECK: or i8
  // CHECK: xor i8
  // CHECK: icmp slt i8
  int8_t c = a + b;
  c = c - a;
  c = c * b;
  c = c / a;
  c = c % a;
  c = c << 1;
  c = c >> 1;
  c = c & a;
  c = c | a;
  c = c ^ a;
  c = (c < a) ? 1 : 0;
  return c;
}
