// REQUIRES: dxil-1-9
// RUN: %dxc -T ps_6_9 -E main -enable-16bit-types -O0 %s | FileCheck %s

cbuffer Foo {
  int8_t a;
  uint8_t b;
}

// CHECK-LABEL: define void @main()
int8_t main() : SV_Target {
  // CHECK: call %dx.types.CBufRet.i8 @dx.op.cbufferLoadLegacy.i8
  // CHECK: extractvalue %dx.types.CBufRet.i8 %{{.*}}, 0
  // CHECK: extractvalue %dx.types.CBufRet.i8 %{{.*}}, 1
  // CHECK: add i8
  return a + b;
}
