// RUN: %dxc -T ps_6_0 -E main -fcgl -HV 2021 %s -spirv | FileCheck %s

// G30/L5 gate: with no tile shading in the shader and no
// -fspv-extension=SPV_QCOM_tile_shading on the command line, the module must be
// exactly what it was before the feature existed.
//
// SPV_QCOM_tile_shading is registered as an extension that is not enabled by
// default (FeatureManager::enabledByDefault), and the capability is inferred from
// what the shader contains (CapabilityVisitor: a TileAttachmentQCOM variable, one
// of the two execution modes, or one of the three tile built-ins), so a shader
// that uses none of them cannot acquire TileShadingQCOM by accident. This file is
// the guard against an inference that starts declaring the capability wherever
// <vk/qcom/tile_shading.h> is included or a storage image is declared.
//
// The ordinary storage image in this file is the near miss: it is the same
// OpTypeImage (2D, Sampled = 2) the tile attachment in qcom.tile-shading.hlsl
// uses, in the storage class it must keep.
//
// The positive halves are qcom.tile-shading.hlsl (fragment) and
// qcom.tile-shading.rate.hlsl (compute); the diagnostic half of this gate - using
// the surface without the flag is an error, not a silent fallback - is
// qcom.tile-shading.extension.error.hlsl.

// The capability and the extension would sit in the header between
// OpCapability Shader and OpMemoryModel, so the CHECK-NOT runs are anchored there.
// CHECK:      OpCapability Shader
// CHECK-NOT:  OpCapability TileShadingQCOM
// CHECK:      OpMemoryModel Logical GLSL450
// CHECK-NOT:  OpExtension "SPV_QCOM_tile_shading"

// No tile shading storage class, no tile built-in and no tile shading execution
// mode anywhere in the module.
// CHECK-NOT:  TileAttachmentQCOM
// CHECK-NOT:  TileOffsetQCOM
// CHECK-NOT:  TileDimensionQCOM
// CHECK-NOT:  TileApronSizeQCOM
// CHECK-NOT:  TileShadingRateQCOM
// CHECK-NOT:  NonCoherentTileAttachmentReadQCOM
// CHECK-NOT:  LocalSize

// The storage image keeps the storage class it always had.
// CHECK:      %[[PTR:[0-9a-zA-Z_]+]] = OpTypePointer UniformConstant %type_2d_image
// CHECK:      %image = OpVariable %[[PTR]] UniformConstant

RWTexture2D<float4> image;

float4 main(float4 pos : SV_Position) : SV_Target {
  uint2 at = uint2(pos.xy);
  return image[at] + image[at];
}
