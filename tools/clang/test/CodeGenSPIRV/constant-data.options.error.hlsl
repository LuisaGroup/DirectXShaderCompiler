// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-constant-data -fspv-extension=SPV_KHR_shader_fma %s -spirv 2>&1 | FileCheck %s --check-prefix=NOEXT
// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-constant-data=0 -fspv-extension=SPV_KHR_constant_data %s -spirv 2>&1 | FileCheck %s --check-prefix=ZERO

// L4: -fspv-constant-data is refused where it cannot be honoured, before any
// code generation runs.
//
// The first RUN line gives an explicit -fspv-extension= allow-list that does not
// contain SPV_KHR_constant_data. Emitting OpConstantDataKHR would produce a
// module that declares an extension the host was never offered, so the option
// itself is refused instead of silently falling back to the composite form (a
// silent fallback would hide the misconfiguration and change the module size
// the user asked for).
//
// The second RUN line shows the threshold is the minimum number of array
// elements: 0 is rejected instead of packing every array, including
// single-element arrays where OpConstantDataKHR is strictly larger than the
// OpConstantComposite it would replace.

// NOEXT: -fspv-constant-data requires -fspv-extension=SPV_KHR_constant_data
// ZERO:  -fspv-constant-data requires a positive threshold; got 0

static const uint table[8] = {
  11, 22, 33, 44, 55, 66, 77, 88
};

RWStructuredBuffer<uint> outBuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  outBuf[0] = table[tid.x % 8];
}
