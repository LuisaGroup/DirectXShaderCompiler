// RUN: not %dxc -T cs_6_0 -E main -fcgl %s -spirv 2>&1 | FileCheck %s
// RUN: not %dxc -T cs_6_0 -E main -fcgl -fspv-extension=SPV_KHR_constant_data %s -spirv 2>&1 | FileCheck %s

// SPV_KHR_abort is opt-in (G6/L4.off): FeatureManager::enabledByDefault returns
// false for it, so the entry point is rejected unless
// -fspv-extension=SPV_KHR_abort is given.
//
// The diagnostic replaces two silent alternatives, both of which would be worse:
// emitting OpAbortKHR anyway would produce a module with OpCapability AbortKHR
// and OpExtension "SPV_KHR_abort" that the host never asked for (and an abort is
// not a recoverable operation - VK_KHR_shader_abort makes it lose the device),
// and lowering to something else would silently change what the shader does.
//
// Because the failure is a compile error, no module is produced at all: there is
// nothing that could contain an OpAbortKHR without the extension. The second RUN
// line is the same shader with a *different* extension enabled, which must not
// unlock it either - the check is per extension, not "some extension was given".
//
// Note that this is a backend diagnostic (SpirvEmitter::processAbortKHR), which
// is why the default check prefix asserts its exact wording; the extension
// registration also means -fspv-extension=SPV_KHR_abort is no longer "unknown
// SPIR-V extension" (that message comes from FeatureManager::allowExtension and
// is covered by every other extension's error test).

#include <vk/ext/abort.h>

RWStructuredBuffer<uint> outBuf;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
  outBuf[0] = tid.x;
  // CHECK: error: 'vk::Abort' requires the SPV_KHR_abort extension; pass -fspv-extension=SPV_KHR_abort to enable it
  vk::Abort(1);
}
