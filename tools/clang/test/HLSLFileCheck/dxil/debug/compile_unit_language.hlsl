// RUN: %dxc -T cs_6_0 -E main -Zi -Qembed_debug -Od %s | FileCheck %s
// RUN: %dxc -T cs_6_5 -E main -Zi -Qembed_debug %s | FileCheck %s

// HLSL is compiled with C++ language options, but the compile unit must be
// tagged with DW_LANG_HLSL so that debug consumers know what they are looking
// at.  DXC used to emit DW_LANG_C_plus_plus here.
//
// CHECK: !DICompileUnit(language: DW_LANG_HLSL,

RWStructuredBuffer<float> Out : register(u0);

[numthreads(1, 1, 1)]
void main() {
  Out[0] = 1.0;
}
