// RUN: %dxc -T ps_6_0 -E main -fcgl  %s -spirv | FileCheck %s

// G31/L2: VK_KHR_maintenance8 rule 1, negative control - a *constant* offset
// still produces the ConstOffset image operand (0x0008) and never the dynamic
// Offset (0x0010). This is the half that keeps the rule from degenerating into
// "always use Offset": DXC only takes the dynamic path when the HLSL offset is
// not a compile-time constant (SpirvEmitter::handleOffsetInMethodCall tries
// constEvaluator::tryToEvaluateAsConst first), and every constant-offset shader
// in existence relies on that.
//
// Each CHECK ends its operand list with {{$}} so the assertion is on the exact
// mask word, and the anchored CHECK-NOT at the end proves no bare Offset was
// emitted anywhere in the entry point. Because "Offset" is a substring of
// "ConstOffset", an unanchored CHECK-NOT: Offset would be useless here; the
// {{$}} anchors and the ConstOffset spellings carry the assertion.
//
// The file also pins the capability side of the rule: ConstOffset needs no
// ImageGatherExtended (the grammar requires it only for the Offset and
// ConstOffsets enumerants), so a constant-offset module must not acquire it.
// maintenance8.dynamic-offset.hlsl is the other half of this pair.
//
// OpImageFetch is covered here too: .Load() only ever accepts an immediate
// offset, so ConstOffset is the only mask it can carry.

SamplerState gSampler : register(s5);
Texture2D<float4> t : register(t1);

float4 main() : SV_Target {
  // CHECK: OpCapability Shader
  // CHECK-NOT: OpCapability ImageGatherExtended
  // CHECK: OpMemoryModel Logical GLSL450

  // CHECK: OpImageSampleImplicitLod %v4float {{%[0-9]+}} {{%[0-9]+}} ConstOffset {{%[0-9]+$}}
  float4 a = t.Sample(gSampler, float2(0.1, 0.2), int2(1, 2));

  // CHECK: OpImageSampleExplicitLod %v4float {{%[0-9]+}} {{%[0-9]+}} Lod|ConstOffset %float_0 {{%[0-9]+$}}
  float4 b = t.SampleLevel(gSampler, float2(0.1, 0.2), 0.0, int2(1, 2));

  // The mip level of .Load() is split out of the location vector, and the offset
  // becomes ConstOffset with the Lod bit.
  // CHECK: OpImageFetch %v4float {{%[0-9]+}} {{%[0-9]+}} Lod|ConstOffset {{%[0-9]+}} {{%[0-9]+$}}
  float4 c = t.Load(int3(0, 0, 0), int2(1, 2));

  // CHECK: OpImageGather %v4float {{%[0-9]+}} {{%[0-9]+}} %int_0 ConstOffset {{%[0-9]+$}}
  float4 d = t.Gather(gSampler, float2(0.1, 0.2), int2(1, 2));

  return a + b + c + d;
}

// Anchored negative: the region from the store that consumes the last image
// instruction to the OpFunctionEnd of the entry point must not contain a dynamic
// operand, and no other image instruction may appear in it either.
// CHECK: OpStore %d
// CHECK-NOT: OpImageSampleImplicitLod %v4float {{%[0-9]+}} {{%[0-9]+}} Offset
// CHECK-NOT: OpImageSampleExplicitLod %v4float {{%[0-9]+}} {{%[0-9]+}} Lod|Offset
// CHECK-NOT: OpImageFetch %v4float {{%[0-9]+}} {{%[0-9]+}} Lod|Offset
// CHECK-NOT: OpImageGather %v4float {{%[0-9]+}} {{%[0-9]+}} %int_0 Offset
// CHECK: OpFunctionEnd
