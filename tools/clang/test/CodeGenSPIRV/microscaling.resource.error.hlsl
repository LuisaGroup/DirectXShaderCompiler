// RUN: not %dxc -T cs_6_0 -E main -spirv -HV 2021 -fcgl %s 2>&1 | FileCheck %s
//
// A 4- or 6-bit micro-scaled type has no addressable storage. SPIR-V only lets
// a variable containing a Float4EXT or Float6EXT type live in Function or
// Private storage ("Variable" in the specification; SPIRV-Tools rejects the
// buffer storage classes), so a resource whose element type contains one is
// rejected instead of producing an invalid module. The check walks vectors,
// matrices, arrays and struct members, so a struct that contains one is
// rejected as well.
//
// The supported way to read packed micro-scaling data is an integer buffer and
// vk::mx::bitcast_extract, which is what the extraction is for. The byte-sized
// float8_e8m0_t is not affected: it is a legal buffer element, see
// microscaling.basic.opt.hlsl.
//
// DXC stops at the first error, so this file exercises the struct case; the
// direct RWStructuredBuffer<float4_e2m1_t> case produces the same diagnostic.
//
// CHECK: error: a resource of float4_e2m1_t, float6_e3m2_t or float6_e2m3_t is not supported: a 4- or 6-bit micro-scaled type has no addressable storage, so the packed integer word has to be loaded instead and the value extracted with vk::mx::bitcast_extract
struct Block {
  float6_e2m3_t lane;
  float other;
};

StructuredBuffer<Block> Packed6;

[numthreads(1, 1, 1)]
void main() {
  float o = float(Packed6[0].lane);
}
