// RUN: %dxc -T cs_6_0 -E main -fcgl -spirv -fspv-target-env=vulkan1.3 -fspv-extension=SPV_QCOM_image_processing3 %s | FileCheck %s

// SPV_QCOM_image_processing3, linear (Gather4x1QCOM) mode: the entry point, its
// capability and its extension, and the encoding of OpImageGatherQCOM
// (G28/L0, G28/L1, G28/L2 linear).
//
// L3 is implicit: dxc validates every module it emits unless -Vd is given, so
// this file compiling at all is the validity gate. It has teeth here: SPIRV-Tools
// rejects OpImageGatherQCOM with "Opcode ImageGatherQCOM requires one of these
// capabilities: ImageGatherLinearQCOM ImageGatherExtendedModesQCOM" when the
// capability is missing, and rejects the Mode operand of Gather4x1QCOM
// ("Mode GatherModesGather4x1QCOM (== 0) requires capability
// ImageGatherLinearQCOM") when the wrong one is declared. It also rejects a
// non-constant Component in a Vulkan environment, which is why the component is a
// template argument of the header's entry points instead of a parameter.
//
// Gather4x1QCOM is the one mode that needs ImageGatherLinearQCOM (4543); the
// three extended modes need ImageGatherExtendedModesQCOM (4544) and are covered
// by qcom.image-processing3.{d,h2,v2}.hlsl, one file per mode so that a
// hard-coded mode operand cannot pass. The capability is selected per call shape
// from the Mode operand of the instruction (CapabilityVisitor), not once for the
// extension, so this file must not declare the extended-modes capability.
//
// Included twice on purpose: the header has to be guarded, and including it must
// not add anything to the module by itself (no capability, no extension, no
// constants - see the off-path test).
#include <vk/qcom/image_processing3.h>
#include <vk/qcom/image_processing3.h>

vk::SampledTexture2D<float4> Tex : register(t0);
vk::SampledTexture2DArray<int4> TexArray : register(t1);
RWStructuredBuffer<float4> Out : register(u0);

// The entry points are declarations, so SPIR-V CodeGen emits the instruction
// where the call is: a gather in a helper stays in the helper, with the component
// the template argument selected baked in as a constant.
float4 helper(float2 uv) { return vk::qcom::ImageGather4x1<1>(Tex, uv); }

[numThreads(1, 1, 1)]
void main() {
  // Component 0 (the default) of the four horizontally adjacent texels.
  Out[0] = vk::qcom::ImageGather4x1(Tex, float2(0.5, 0.5));
  Out[1] = helper(float2(0.25, 0.75));
  // Arrayed image: two coordinate components plus the array layer, integer
  // texels, so the result is an int4.
  Out[2] =
      float4(vk::qcom::ImageGather4x1Array(TexArray, float3(0.5, 0.5, 2.0)));
}

// L1: exactly the capability of the 4x1 mode, the extension, and nothing else.
// The capability block is contiguous, so a duplicate (or the other capability of
// the same extension) would be right here.
// CHECK: OpCapability Shader
// CHECK-NOT: OpCapability ImageGatherExtendedModesQCOM
// CHECK: OpCapability ImageGatherLinearQCOM
// CHECK: OpExtension "SPV_QCOM_image_processing3"
// CHECK-NOT: OpExtension "SPV_QCOM_image_processing3"
// CHECK: OpMemoryModel Logical GLSL450
// L2: the operand types, captured once. Component and Mode are 32-bit signed
// integers in this lowering (the instruction only asks for a 32-bit integer
// scalar).
// CHECK-DAG: [[INT:%[0-9A-Za-z_]+]] = OpTypeInt 32 1
// CHECK-DAG: [[INT0:%[0-9A-Za-z_]+]] = OpConstant [[INT]] 0
// CHECK-DAG: [[INT1:%[0-9A-Za-z_]+]] = OpConstant [[INT]] 1
// CHECK-DAG: [[FLOAT:%[0-9A-Za-z_]+]] = OpTypeFloat 32
// CHECK-DAG: [[V2FLOAT:%[0-9A-Za-z_]+]] = OpTypeVector [[FLOAT]] 2
// CHECK-DAG: [[V3FLOAT:%[0-9A-Za-z_]+]] = OpTypeVector [[FLOAT]] 3
// CHECK-DAG: [[V4FLOAT:%[0-9A-Za-z_]+]] = OpTypeVector [[FLOAT]] 4
// CHECK-DAG: [[V4INT:%[0-9A-Za-z_]+]] = OpTypeVector [[INT]] 4
// CHECK-DAG: [[SAMPLED:%[0-9A-Za-z_]+]] = OpTypeSampledImage
// CHECK-DAG: [[SAMPLEDARRAY:%[0-9A-Za-z_]+]] = OpTypeSampledImage
// The coordinates the calls pass, so the coordinate operand is identifiable.
// CHECK-DAG: [[COORD:%[0-9A-Za-z_]+]] = OpConstantComposite [[V2FLOAT]] {{%[A-Za-z0-9_]+}} {{%[A-Za-z0-9_]+}}
// CHECK-DAG: [[COORD3:%[0-9A-Za-z_]+]] = OpConstantComposite [[V3FLOAT]] {{%[A-Za-z0-9_]+}} {{%[A-Za-z0-9_]+}} {{%[A-Za-z0-9_]+}}
// L2: the instruction is (IdResultType, IdResult, Sampled Image, Coordinate,
// Component, Mode). The Sampled Image operand is the id the OpLoad of the
// vk::SampledTexture2D produced - not an OpSampledImage, and not the image of a
// separately declared sampler - and Component and Mode are the two constants, in
// that order. Component 0 of the 4x1 footprint is the default, so both trailing
// operands are %int_0 here; the helper below pins down which is which.
// CHECK: [[IMG:%[0-9A-Za-z_]+]] = OpLoad [[SAMPLED]] %Tex
// CHECK-NEXT: OpImageGatherQCOM [[V4FLOAT]] [[IMG]] [[COORD]] [[INT0]] [[INT0]]
// L2: the arrayed form takes the sampled image of the arrayed type and a
// three-component coordinate, and its result type follows the sampled type of the
// image (int4 here).
// CHECK: [[IMGA:%[0-9A-Za-z_]+]] = OpLoad [[SAMPLEDARRAY]] %TexArray
// CHECK-NEXT: OpImageGatherQCOM [[V4INT]] [[IMGA]] [[COORD3]] [[INT0]] [[INT0]]
// L2: the helper's gather, where component 1 and mode 0 differ: a lowering that
// swapped the last two operands cannot pass both this line and the one above.
// CHECK: %helper = OpFunction
// CHECK: [[IMGH:%[0-9A-Za-z_]+]] = OpLoad [[SAMPLED]] %Tex
// CHECK-NEXT: [[COORDH:%[0-9A-Za-z_]+]] = OpLoad [[V2FLOAT]] %uv
// CHECK-NEXT: OpImageGatherQCOM [[V4FLOAT]] [[IMGH]] [[COORDH]] [[INT1]] [[INT0]]
