// RUN: %dxc -T ps_6_8 -E main -DORDER=0 %s | FileCheck %s --check-prefix=HAS
// RUN: %dxc -T ps_6_8 -E main -DORDER=1 %s | FileCheck %s --check-prefix=HAS
// RUN: %dxc -T ps_6_8 -E main -DORDER=2 %s | FileCheck %s --check-prefix=HAS
// RUN: %dxc -T ps_6_8 -E main -DORDER=3 %s | FileCheck %s --check-prefix=HAS
// RUN: %dxc -T ps_6_8 -E main -DORDER=4 %s | FileCheck %s --check-prefix=NONE

// The SampleCmpGradientOrBias shader flag is set whenever SampleCmpBias or
// SampleCmpGrad is used, no matter which sample instruction happens to come
// last in the function.  CollectShaderFlags used to assign the flag instead of
// accumulating it, so a trailing Sample/SampleBias/SampleCmp/SampleGrad
// silently cleared it.
//
// HAS: Note: shader requires additional functionality:
// HAS-NEXT: SampleCmp with gradient or bias
//
// NONE-NOT: SampleCmp with gradient or bias

Texture2D<float> depth : register(t0);
SamplerComparisonState less : register(s0);
SamplerState linearSampler : register(s1);

float4 main(float2 uv : TEXCOORD0) : SV_Target {
#if ORDER == 0
  // SampleCmpBias first, SampleCmp last: the flag used to be dropped here.
  return depth.SampleCmpBias(less, uv, 0.5, 1.0) + depth.SampleCmp(less, uv, 0.25);
#elif ORDER == 1
  // SampleCmp first, SampleCmpBias last.
  return depth.SampleCmp(less, uv, 0.25) + depth.SampleCmpBias(less, uv, 0.5, 1.0);
#elif ORDER == 2
  // SampleCmpGrad first, SampleGrad last: same assignment bug.
  return depth.SampleCmpGrad(less, uv, 0.5, float2(1, 0), float2(0, 1)) +
         depth.SampleGrad(linearSampler, uv, float2(1, 0), float2(0, 1));
#elif ORDER == 3
  // SampleGrad first, SampleCmpGrad last.
  return depth.SampleGrad(linearSampler, uv, float2(1, 0), float2(0, 1)) +
         depth.SampleCmpGrad(less, uv, 0.5, float2(1, 0), float2(0, 1));
#else
  // No comparison-with-gradient-or-bias operation: the flag must stay clear.
  return depth.Sample(linearSampler, uv) + depth.SampleBias(linearSampler, uv, 1.0);
#endif
}
