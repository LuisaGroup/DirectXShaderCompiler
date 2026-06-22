// RUN: %dxc -T ps_6_2 -HV 2018 -E main -spirv -enable-16bit-types %s | FileCheck %s

// CHECK: OpCapability Int8

void main() {
  // Scalar casts
  int8_t a = 5;
  uint8_t b = 255;
  
  int16_t c = (int16_t)a;
  int32_t d = (int32_t)a;
  int64_t e = (int64_t)a;
  
  uint16_t f = (uint16_t)b;
  uint32_t g = (uint32_t)b;
  uint64_t h = (uint64_t)b;

  // Vector casts (same-size vectors)
  int8_t2  v8a = int8_t2(1, -2);
  uint8_t4 v8b = uint8_t4(255, 128, 64, 32);

  int16_t2  v16a = int16_t2(v8a);
  int32_t2  v32a = int32_t2(v8a);
  int64_t2  v64a = int64_t2(v8a);

  uint16_t4 v16b = uint16_t4(v8b);
  uint32_t4 v32b = uint32_t4(v8b);
  uint64_t4 v64b = uint64_t4(v8b);

  // Cross-type vector casts
  int8_t4  v8c = int8_t4(v8b);
  uint8_t2 v8d = uint8_t2(v8a);
}
