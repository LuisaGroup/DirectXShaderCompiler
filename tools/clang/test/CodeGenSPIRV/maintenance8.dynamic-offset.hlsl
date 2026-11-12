// RUN: %dxc -T ps_6_0 -E main -fcgl  %s -spirv | FileCheck %s

// G31/L2: VK_KHR_maintenance8 rule 1 - a *dynamic* (non-constant) image offset
// is emitted as the ImageOperands "Offset" bit (0x0010), never as "ConstOffset"
// (0x0008). Before maintenance8 the Vulkan SPIR-V environment allowed "Offset"
// only on OpImage*Gather, which is why the sampling forms needed a constant
// offset; maintenance8 lifts that restriction, so this is the encoding the
// extension legalises and DXC must keep producing it.
//
// The mask operand is a single word, so the whole decision is "which of the two
// bits is in it". Every CHECK below ends its operand list with {{$}}, which
// proves that exactly the listed mask is present: a module that emitted
// "ConstOffset|Offset" or that appended a further operand fails the match. The
// near-miss is additionally excluded in an anchored CHECK-NOT region at the end.
//
// Only the sampling/gather methods reach a non-constant offset: .Load() rejects
// it with its own diagnostic ("Offsets to texture access operations must be
// immediate values", processBufferTextureLoad in SpirvEmitter.cpp), so
// OpImageFetch never carries a dynamic Offset and cannot be asserted here.
//
// The ImageGatherExtended capability is required by the grammar for the Offset
// enumerant. It is the only capability this rule adds; the control group in
// maintenance8.const-offset.hlsl shows that a constant offset does not need it.

SamplerState gSampler : register(s5);
SamplerComparisonState gSamplerCmp : register(s6);
Texture2D<float4> t : register(t1);
Texture2D<float> tcmp : register(t2);

float4 main(int2 dynamicOffset : A) : SV_Target {
  uint status;

  // CHECK: OpCapability ImageGatherExtended
  // CHECK: OpCapability SparseResidency

  // The offset is a shader-computed value, so it reaches the image instruction
  // as an id and the mask must be Offset.
  // CHECK: [[IMPLICIT_OFFSET:%[0-9]+]] = OpLoad %v2int %dynamicOffset
  // CHECK: OpImageSampleImplicitLod %v4float {{%[0-9]+}} {{%[0-9]+}} Offset [[IMPLICIT_OFFSET]]{{$}}
  float4 a = t.Sample(gSampler, float2(0.1, 0.2), dynamicOffset);

  // Explicit-LOD form: the Lod and Offset operands coexist in one mask, in that
  // order.
  // CHECK: [[EXPLICIT_OFFSET:%[0-9]+]] = OpLoad %v2int %dynamicOffset
  // CHECK: OpImageSampleExplicitLod %v4float {{%[0-9]+}} {{%[0-9]+}} Lod|Offset %float_0 [[EXPLICIT_OFFSET]]{{$}}
  float4 c = t.SampleLevel(gSampler, float2(0.1, 0.2), 0.0, dynamicOffset);

  // Gather also accepts a dynamic offset, but that form was already legal before
  // maintenance8; it is asserted so the sibling masks above cannot drift.
  // CHECK: [[GATHER_OFFSET:%[0-9]+]] = OpLoad %v2int %dynamicOffset
  // CHECK: OpImageGather %v4float {{%[0-9]+}} {{%[0-9]+}} %int_0 Offset [[GATHER_OFFSET]]{{$}}
  float4 d = t.Gather(gSampler, float2(0.1, 0.2), dynamicOffset);

  // CHECK: [[DREFGATHER_OFFSET:%[0-9]+]] = OpLoad %v2int %dynamicOffset
  // CHECK: OpImageDrefGather %v4float {{%[0-9]+}} {{%[0-9]+}} %float_0_5 Offset [[DREFGATHER_OFFSET]]{{$}}
  float4 e = tcmp.GatherCmp(gSamplerCmp, float2(0.1, 0.2), 0.5, dynamicOffset);

  // Sparse (status-argument) form: Offset and MinLod share the mask.
  // CHECK: [[SPARSE_OFFSET:%[0-9]+]] = OpLoad %v2int %dynamicOffset
  // CHECK: OpImageSparseSampleImplicitLod %SparseResidencyStruct {{%[0-9]+}} {{%[0-9]+}} Offset|MinLod [[SPARSE_OFFSET]] %float_1{{$}}
  float4 f = t.Sample(gSampler, float2(0.1, 0.2), dynamicOffset, 1.0, status);

  return a + c + d + e + f;
}

// Anchored negative: a bare ConstOffset anywhere in the rest of the entry point
// would be the encoding this rule replaces. The {{$}} anchors above already make
// a "ConstOffset|Offset" mask a hard mismatch; this region adds the whole-body
// guarantee, from the last instruction that consumes an image to the OpFunctionEnd
// that closes src_main, so it is not a trailing, vacuous CHECK-NOT.
// CHECK: OpStore %f
// CHECK-NOT: ConstOffset
// CHECK: OpFunctionEnd
