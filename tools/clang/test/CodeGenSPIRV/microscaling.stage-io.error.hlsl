// RUN: not %dxc -T ps_6_0 -E mainIn -spirv -HV 2021 -fcgl %s 2>&1 | FileCheck %s --check-prefix=IN
// RUN: not %dxc -T ps_6_0 -E mainOut -spirv -HV 2021 -fcgl %s 2>&1 | FileCheck %s --check-prefix=OUT
//
// SPV_EXT_ocp_microscaling_types does not allow any of its encodings in the
// Input or Output storage class (VUID-StandaloneSpirv-OpVariable-10823), so a
// micro-scaled value must be rejected in a shader stage interface - including
// inside a struct, a vector or an array - instead of emitting SPIR-V the
// validator would reject.
//
// The way to get micro-scaled data into a shader is a packed integer input,
// decoded with vk::mx::bitcast_extract; see
// microscaling.bitcast-extract.hlsl.
//
// IN: error: float4_e2m1_t, float6_e3m2_t, float6_e2m3_t and float8_e8m0_t are not supported in shader stage input/output: SPV_EXT_ocp_microscaling_types does not allow a micro-scaled OpTypeFloat encoding in the Input or Output storage class
struct PSIn {
  float4_e2m1_t val : TEXCOORD0;
};

float4 mainIn(PSIn input) : SV_Target {
  return 1.0;
}

// OUT: error: float4_e2m1_t, float6_e3m2_t, float6_e2m3_t and float8_e8m0_t are not supported in shader stage input/output: SPV_EXT_ocp_microscaling_types does not allow a micro-scaled OpTypeFloat encoding in the Input or Output storage class
struct PSOut {
  float6_e3m2_t2x2 val : TEXCOORD0;
  float8_e8m0_t scale : TEXCOORD1;
};

PSOut mainOut(float4 pos : SV_Position) : SV_Target {
  PSOut o;
  o.val._11 = float6_e3m2_t(1.0);
  o.val._12 = float6_e3m2_t(1.0);
  o.val._21 = float6_e3m2_t(1.0);
  o.val._22 = float6_e3m2_t(1.0);
  o.scale = float8_e8m0_t(1.0);
  return o;
}
