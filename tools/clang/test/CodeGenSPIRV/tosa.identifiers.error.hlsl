// RUN: not %dxc -T cs_6_0 -E main -fcgl -DWRONG_VERSION %s -spirv 2>&1 | FileCheck %s --check-prefix=VERSION
// RUN: not %dxc -T cs_6_0 -E main -fcgl -DWRONG_CASE %s -spirv 2>&1 | FileCheck %s --check-prefix=CASE
// RUN: not %dxc -T cs_6_0 -E main -fcgl -DADHOC_OPCODE %s -spirv 2>&1 | FileCheck %s --check-prefix=OPCODE
// RUN: not %dxc -T cs_6_0 -E main -fcgl -DALLOWLIST -fspv-extension=SPV_KHR_8bit_storage %s -spirv 2>&1 | FileCheck %s --check-prefix=ALLOWLIST

// L4 diagnostic gate: the three module-level identifiers a TOSA call depends on -
// the set name, the opcode number and the extension that the operand type needs -
// are pinned, and the compiler refuses each of the three ways of getting one wrong.
//
// TOSA.001000.1 is not a name DXC chose - it is the import string the SPIR-V
// extended-instruction specification fixes for TOSA version 1.0 revision 1, and
// the opcode numbers 0..65 are the ones
// extinst.tosa.001000.1.grammar.json assigns. The string and the numbers are the
// entire contract with whatever consumes the module: a consumer looks up the set
// by the exact string and then decodes each OpExtInst's opcode against that set's
// table. Get either wrong and the consumer is reading a different language.
//
// <vk/arm/tosa.h> pins both, and the pinning is enforced by the SPIRV-Tools
// tables that ship with DXC rather than by a compiler option, which is why these
// are diagnostics and not an -fspv-* flag: there is nothing to configure, only a
// spelling to get right. Each case below is one of the ways to get it wrong.
//
// The first three are *validator* diagnostics, and that is the point: TOSA has no
// extension string and no capability of its own, so there is nothing in
// FeatureManager to register and no -fspv-extension value that could accept or
// refuse the set. Pinning has to happen where the encoding is decoded, and it
// cannot be silenced by a command-line flag.
//
// The fourth case is the other side of that. The one thing a TOSA operation does
// drag in is the extension its operand type lives in, SPV_ARM_tensors, and
// SPV_ARM_tensors is deliberately **not** a FeatureManager entry: naming it is an
// unknown extension, which is what makes the header's [[vk::ext_extension]] the
// only way the string reaches the module and what makes -fspv-extension unable to
// gate it. Registering it would be the alternative design, and it would mean a
// flag that removes a capability the instructions in the shader still need; the
// choice here is an unconditional capability with the deviation documented
// (docs/SPIR-V.rst, "TOSA tensor operations").

#include <vk/arm/tosa.h>

using namespace vk::arm::tosa;

#ifdef WRONG_VERSION
// The plausible mistake: bumping the version, or believing the set is versioned
// like a Vulkan extension (TOSA.1.0, TOSA.001000.2, TOSA_001000_1 are all "the
// TOSA set" to a human). The import is rejected by name, before any opcode is
// decoded, because the spvExtInstImportTypeGet table has an exact-string match:
//
//   Invalid extended instruction import 'TOSA.001000.2'
//
// The diagnostic names the string that was actually emitted, so a module built
// against a future TOSA revision fails here rather than silently decoding every
// opcode as the wrong operation.
//
// VERSION: fatal error: generated SPIR-V is invalid: Invalid extended instruction import 'TOSA.001000.2'
[[vk::ext_extension("SPV_ARM_tensors")]]
[[vk::ext_capability(/* TensorsARM */ 4174)]]
[[vk::ext_instruction(/* ADD */ 14, "TOSA.001000.2")]] Tensor<float> AddWrongVersion(
    Tensor<float> input1, Tensor<float> input2);
[numthreads(1, 1, 1)] void main() {
  Tensor<float> a;
  Tensor<float> r = AddWrongVersion(a, a);
}
#endif

#ifdef WRONG_CASE
// The set names are case-sensitive, and the ones DXC already emits are
// inconsistent enough to mislead: "GLSL.std.450" and "OpenCL.std" are
// mixed-case, "NonSemantic.DebugPrintf" is CamelCase, and TOSA's is upper-case
// throughout. A lower-case TOSA set is a different string and an unknown set.
//
// CASE: fatal error: generated SPIR-V is invalid: Invalid extended instruction import 'tosa.001000.1'
[[vk::ext_extension("SPV_ARM_tensors")]]
[[vk::ext_capability(/* TensorsARM */ 4174)]]
[[vk::ext_instruction(/* ADD */ 14, "tosa.001000.1")]] Tensor<float> AddWrongCase(
    Tensor<float> input1, Tensor<float> input2);
[numthreads(1, 1, 1)] void main() {
  Tensor<float> a;
  Tensor<float> r = AddWrongCase(a, a);
}
#endif

#ifdef ADHOC_OPCODE
// An opcode number outside the set's table. This is the mistake that the header
// exists to prevent - the numbers are not memorable, and 66 of them are spread
// over five ranges - so this test calls the instruction directly, the way a
// hand-written declaration would. 66 is one past TOSAINSTRUCTIONSMAX: the
// vendored TOSA.001000.1.h numbers the operations 0..65, so 66 is the first
// number with no meaning, and the validator rejects it by number rather than
// decoding it as something else:
//
//   Invalid extended instruction number: 66
//
// A number above the set's range is caught here; a *wrong but in-range* number is
// not, because the encoding contains nothing that identifies which operation was
// meant. That is why <vk/arm/tosa.h> spells the opcode in a comment next to every
// declaration, and why tosa.basic.hlsl asserts the mnemonic SPIRV-Tools prints for
// each number.
//
// OPCODE: fatal error: generated SPIR-V is invalid: Invalid extended instruction number: 66
[[vk::ext_extension("SPV_ARM_tensors")]]
[[vk::ext_capability(/* TensorsARM */ 4174)]]
[[vk::ext_instruction(/* not a TOSA opcode */ 66, "TOSA.001000.1")]] Tensor<float> NotATosaOp(
    Tensor<float> input1, Tensor<float> input2);
[numthreads(1, 1, 1)] void main() {
  Tensor<float> a;
  Tensor<float> r = NotATosaOp(a, a);
}
#endif

#ifdef ALLOWLIST
// SPV_ARM_tensors *is* a registered extension (FeatureManager), so -fspv-extension
// can name it, and an explicit -fspv-extension list is an allow-list: a list that
// omits it refuses the tensor type that the TOSA operand type requires. The RUN
// line therefore passes a list without SPV_ARM_tensors, and the diagnostic names
// the extension the module needs instead of the extension that did not exist. The
// three cases above are still validator diagnostics that no flag can silence; this
// one is what a -fspv-extension list can and does refuse.
//
// ALLOWLIST: error: SPIR-V extension 'SPV_ARM_tensors' required for tensor types but not permitted to use
[[vk::ext_extension("SPV_ARM_tensors")]]
[[vk::ext_capability(/* TensorsARM */ 4174)]]
[[vk::ext_instruction(/* ADD */ 14, "TOSA.001000.1")]] Tensor<float> AddAllowlisted(
    Tensor<float> input1, Tensor<float> input2);
[numthreads(1, 1, 1)] void main() {
  Tensor<float> a;
  Tensor<float> r = AddAllowlisted(a, a);
}
#endif
