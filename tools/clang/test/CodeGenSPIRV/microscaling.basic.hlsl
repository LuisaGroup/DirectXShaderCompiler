// RUN: %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl %s | FileCheck %s
//
// Lowering of the four SPV_EXT_ocp_microscaling_types formats and of the one
// instruction the extension adds.
//
// One module uses all four formats on purpose: a single OpTypeFloat 4 cannot
// distinguish a correct encoding from one that always selects E2M1, and a
// single OpTypeFloat 6 cannot distinguish E3M2 from E2M3. The capability block
// is what a mixed-format shader has to get right - there is no per-format
// float4 or float6 capability, so Float4EXT and Float6EXT are two separate
// lines.
//
// The capability order below is the emitter's type-discovery order, which is
// why the E8M0 type (introduced by a constant) comes first.
// CHECK: OpCapability Float8UnsignedE8M0EXT
// CHECK-NOT: OpCapability Float8UnsignedE8M0EXT
// CHECK: OpCapability Float4EXT
// CHECK-NOT: OpCapability Float4EXT
// CHECK: OpCapability Float6EXT
// CHECK-NOT: OpCapability Float6EXT
// CHECK: OpCapability BitcastExtractEXT
// CHECK-NOT: OpCapability BitcastExtractEXT
// Near misses: the float8 capability this extension builds on, an integer 8-bit
// capability (these are floats, not 8-bit integers) and MXInt8EXT, which this
// landing does not implement.
// CHECK-NOT: OpCapability Float8EXT
// CHECK-NOT: OpCapability MXInt8EXT
// CHECK-NOT: OpCapability Int8
// CHECK-NOT: OpCapability StorageBuffer8BitAccess
// CHECK: OpExtension "SPV_EXT_ocp_microscaling_types"
// CHECK-NOT: OpExtension "SPV_EXT_ocp_microscaling_types"
// CHECK-NOT: OpExtension "SPV_EXT_float8"
// CHECK-NOT: OpExtension "SPV_KHR_16bit_storage"
// CHECK: OpMemoryModel
//
// Each format is OpTypeFloat with its own FP encoding; a plain (unencoded) 4-,
// 6- or 8-bit float must not be generated.
// CHECK: %fp8e8m0 = OpTypeFloat 8 Float8UnsignedE8M0EXT
// The E8M0 constant for the literal 0.5: 0.5 is 2^(126-127), so the exponent
// field is 126 (0x7e) and the disassembler prints the value back as 0x1p-1.
// CHECK: %fp8e8m0_0x1pn1 = OpConstant %fp8e8m0 0x1p-1
// CHECK: %fp4e2m1 = OpTypeFloat 4 Float4E2M1EXT
// CHECK: %fp6e3m2 = OpTypeFloat 6 Float6E3M2EXT
// CHECK: %fp6e2m3 = OpTypeFloat 6 Float6E2M3EXT
// CHECK-NOT: OpTypeFloat 4{{$}}
// CHECK-NOT: OpTypeFloat 6{{$}}
// CHECK-NOT: OpTypeFloat 8{{$}}
//
// Vectors of the sub-byte types are legal (OpTypeVector of a 4- or 6-bit
// float), which is the form a multi-lane extract produces.
// CHECK: %v2fp4e2m1 = OpTypeVector %fp4e2m1 2
// CHECK: %v4fp6e3m2 = OpTypeVector %fp6e3m2 4
#include <vk/ext/ocp_microscaling.h>

[numthreads(1, 1, 1)]
void main() {
  uint w = 0x12345678;

  // A 4- or 6-bit type has no addressable storage of its own, but SPIR-V does
  // allow it in Function and Private storage, so a local of one is legal and is
  // what an extracted value is stored into.
  // CHECK: %a = OpVariable %_ptr_Function_fp4e2m1 Function
  float4_e2m1_t a = vk::mx::bitcast_extract_e2m1(w, 0);
  // CHECK: %b = OpVariable %_ptr_Function_fp6e3m2 Function
  float6_e3m2_t b = vk::mx::bitcast_extract_e3m2(w, 4);
  // CHECK: %c = OpVariable %_ptr_Function_fp6e2m3 Function
  float6_e2m3_t c = vk::mx::bitcast_extract_e2m3(w, 10);
  // CHECK: %d = OpVariable %_ptr_Function_fp8e8m0 Function
  float8_e8m0_t d = float8_e8m0_t(0.5);
  // CHECK: %v2 = OpVariable %_ptr_Function_v2fp4e2m1 Function
  float4_e2m1_t2 v2 = vk::mx::bitcast_extract_e2m1(uint2(w, w), 0);
  // CHECK: %v4 = OpVariable %_ptr_Function_v4fp6e3m2 Function
  float6_e3m2_t4 v4 = vk::mx::bitcast_extract_e3m2(uint4(w, w, w, w), 4);

  // The bit offset is the operand the ABI defines: the field starts at the
  // stated bit offset of the base word, so four E2M1 lanes of one word are
  // extracted at 0, 4, 8 and 12, and five E3M2 lanes at 0, 6, 12, 18 and 24.
  // CHECK: [[w0:%[0-9]+]] = OpLoad %uint %w
  // CHECK-NEXT: OpBitcastExtractEXT %fp4e2m1 [[w0]] %uint_0
  // CHECK: [[w1:%[0-9]+]] = OpLoad %uint %w
  // CHECK-NEXT: OpBitcastExtractEXT %fp6e3m2 [[w1]] %uint_4
  // CHECK: [[w2:%[0-9]+]] = OpLoad %uint %w
  // CHECK-NEXT: OpBitcastExtractEXT %fp6e2m3 [[w2]] %uint_10
  // The literal folds to a constant, no conversion instruction.
  // CHECK: OpStore %d %fp8e8m0_0x1pn1
  // CHECK: [[v2src:%[0-9]+]] = OpCompositeConstruct %v2uint
  // CHECK-NEXT: OpBitcastExtractEXT %v2fp4e2m1 [[v2src]] %uint_0
  // CHECK: [[v4src:%[0-9]+]] = OpCompositeConstruct %v4uint
  // CHECK-NEXT: OpBitcastExtractEXT %v4fp6e3m2 [[v4src]] %uint_4

  // The values are consumed through a conversion, which is the only way a
  // micro-scaled value can take part in a computation.
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  // CHECK: OpFConvert %float
  float o = float(a) + float(b) + float(c) + float(d) + float(v2.x) +
            float(v4.w);
}
