// REQUIRES: dxil-1-9
// RUN: %dxc -T ps_6_9 -E main -enable-16bit-types -O0 %s | FileCheck %s

// CHECK-LABEL: define void @main()
int8_t4 main(int8_t4 a : A, int8_t4 b : B) : SV_Target {
  // CHECK: call i8 @dx.op.loadInput.i8
  // CHECK: insertelement <4 x i8>
  // CHECK: add <4 x i8>
  // CHECK: call void @dx.op.storeOutput.i8
  return a + b;
}
