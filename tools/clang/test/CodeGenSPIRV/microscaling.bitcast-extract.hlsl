// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl %s | FileCheck %s
//
// OpBitcastExtractEXT (4195) gated by BitcastExtractEXT (4232): the packed
// extraction that makes the 4- and 6-bit formats usable at all.
//
// The operand order is what this file pins. From the grammar:
//   OpBitcastExtractEXT  (IdResultType, IdResult, IdRef Base, IdRef Offset)
// so the instruction is
//   %r = OpBitcastExtractEXT %result-type %base %offset
// Result Type is the micro-scaled value, Base is the integer word (or vector of
// words) holding the packed fields and Offset is a *scalar* integer bit offset.
// The bit offset is the ABI's, not the compiler's: an E2M1 lane of a packed word
// starts at 0, 4, 8, 12, ... and an E3M2/E2M3 lane at 0, 6, 12, 18, 24, so the
// offset reaches the instruction unchanged as an OpConstant - there is no
// arithmetic for the compiler to fold, and a wrong offset would still validate.
//
// SPV_EXT_ocp_microscaling_types is explicitly not block scaling. Nothing here
// multiplies by a scale: the scale, when the caller wants MX semantics, is a
// separate float8_e8m0_t value the shader has to apply itself.
// CHECK-NOT: OpFMul
//
// CHECK: OpCapability Float4EXT
// CHECK: OpCapability Float6EXT
// CHECK: OpCapability BitcastExtractEXT
// CHECK-NOT: OpCapability MXInt8EXT
// CHECK: OpExtension "SPV_EXT_ocp_microscaling_types"
// CHECK: OpMemoryModel
// CHECK: %fp4e2m1 = OpTypeFloat 4 Float4E2M1EXT
// CHECK: %fp6e3m2 = OpTypeFloat 6 Float6E3M2EXT
// CHECK: %fp6e2m3 = OpTypeFloat 6 Float6E2M3EXT
#include <vk/ext/ocp_microscaling.h>

[numthreads(1, 1, 1)]
void main() {
  // One 32-bit word holds eight E2M1 lanes. Lane 3 therefore starts at bit 12.
  uint word4 = 0x12345678;
  // CHECK: [[w4:%[0-9]+]] = OpLoad %uint
  // CHECK-NEXT: OpBitcastExtractEXT %fp4e2m1 [[w4]] %uint_12
  float4_e2m1_t lane3 = vk::mx::bitcast_extract_e2m1(word4, 12);
  // Lane 7 of the same packing starts at bit 28, the last field of the word.
  // CHECK: OpBitcastExtractEXT %fp4e2m1 {{%[0-9]+}} %uint_28
  float4_e2m1_t lane7 = vk::mx::bitcast_extract_e2m1(word4, 28);

  // A 32-bit word holds five E3M2 lanes plus two unused bits, so the last lane
  // starts at bit 24 and an offset of 30 would be past the end of the word.
  uint word6 = 0xABCDEF01;
  // CHECK: OpBitcastExtractEXT %fp6e3m2 {{%[0-9]+}} %uint_0
  float6_e3m2_t e3m2_lane0 = vk::mx::bitcast_extract_e3m2(word6, 0);
  // CHECK: OpBitcastExtractEXT %fp6e3m2 {{%[0-9]+}} %uint_24
  float6_e3m2_t e3m2_lane4 = vk::mx::bitcast_extract_e3m2(word6, 24);
  // The other 6-bit split is a different type with the same packing, which is
  // what makes the format a parameter rather than a constant.
  // CHECK: OpBitcastExtractEXT %fp6e2m3 {{%[0-9]+}} %uint_18
  float6_e2m3_t e2m3_lane3 = vk::mx::bitcast_extract_e2m3(word6, 18);

  // Offset is a scalar even for a vector Base: the same bit offset is taken
  // from each word. The vector size of Base has to match the result's.
  // CHECK: [[b4:%[0-9]+]] = OpCompositeConstruct %v2uint
  // CHECK-NEXT: OpBitcastExtractEXT %v2fp4e2m1 [[b4]] %uint_4
  float4_e2m1_t2 lanes4 =
      vk::mx::bitcast_extract_e2m1(uint2(word4, word4), 4);
  // CHECK: [[b6:%[0-9]+]] = OpCompositeConstruct %v4uint
  // CHECK-NEXT: OpBitcastExtractEXT %v4fp6e3m2 [[b6]] %uint_6
  float6_e3m2_t4 lanes6 =
      vk::mx::bitcast_extract_e3m2(uint4(word6, word6, word6, word6), 6);

  // Result Type is the micro-scaled type, and the value is only usable through
  // a conversion - no arithmetic, and no scale multiply.
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  float acc = float(lane3) + float(lane7) + float(e3m2_lane0) +
              float(e3m2_lane4) + float(e2m3_lane3) + float(lanes4.x) +
              float(lanes6.w);
}
