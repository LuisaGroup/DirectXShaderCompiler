// REQUIRES: dxil-1-9
// RUN: %dxc -T ps_6_9 -E main -enable-16bit-types %s | FileCheck %s

// CHECK-LABEL: define void @main()
int8_t4_packed main(int8_t4_packed a : A) : SV_Target {
  // CHECK: call i32 @dx.op.loadInput.i32
  // CHECK: call void @dx.op.storeOutput.i32
  return a;
}
