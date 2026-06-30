// REQUIRES: dxil-1-9
// RUN: %dxc -T ps_6_9 -E main -enable-16bit-types %s | FileCheck %s

Buffer<int8_t> srv : register(t0);
RWBuffer<int8_t> uav : register(u0);

// CHECK-LABEL: define void @main()
int8_t main() : SV_Target {
  // CHECK: call %dx.types.ResRet.i8 @dx.op.bufferLoad.i8
  // CHECK: call void @dx.op.bufferStore.i8
  uav[0] = srv[0];
  return uav[0];
}
