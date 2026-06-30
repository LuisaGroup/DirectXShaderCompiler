// REQUIRES: dxil-1-9
// RUN: %dxc -T ps_6_9 -E main -enable-16bit-types %s | FileCheck %s

// CHECK-LABEL: define void @main()
int8_t main(int8_t a : A) : SV_Target {
  // CHECK: call i8 @dx.op.loadInput.i8(i32 4, i32 0, i32 0, i8 0, i32 undef)
  // CHECK: call void @dx.op.storeOutput.i8(i32 5, i32 0, i32 0, i8 0, i8 %{{.*}})
  return a;
}
