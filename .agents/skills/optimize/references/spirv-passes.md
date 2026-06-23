# SPIR-V Optimization Pipeline — Detailed Reference

> **Audience:** Contributors modifying or debugging the SPIR-V optimization pipeline.
> **Last Updated:** Auto-generated from DXC source analysis.

---

## Architecture

The SPIR-V backend uses **SPIRV-Tools** (`external/SPIRV-Tools/`) as its optimizer. DXC does **not** use LLVM's optimization pipeline for SPIR-V. Instead:

1. DXC emits raw SPIR-V from the AST
2. Optionally runs **legalization** (if needed)
3. If `OptLevel > 0`, runs **optimization**
4. Runs post-processing (capability trimming, debug fixup)

**Source**: `tools/clang/lib/SPIRV/SpirvEmitter.cpp`, method `SpirvEmitter::HandleTranslationUnit()` (~line 960-1045) and methods `spirvToolsOptimize()`, `spirvToolsLegalize()` (~line 16746-16919).

---

## Pipeline Sequence

```
Emit Raw SPIR-V
    │
    ▼
[if codeGenHighLevel] ──► skip all Tools calls, emit directly
    │
    ▼
[if needsLegalization] ──► spirvToolsLegalize()
    │
    ▼
[if OptLevel > 0] ──► spirvToolsOptimize()   (fixed-point, up to 5 iterations)
    │
    ▼
[if debugInfoRich] ──► spirvToolsFixupOpExtInst()
    │
    ▼
Always ──► spirvToolsTrimCapabilities()
    │
    ▼
[optional] spirvToolsUpgradeToVulkanMemoryModel()
    │
    ▼
[if !disableValidation] ──► spirvToolsValidate()
    │
    ▼
Final SPIR-V Binary
```

---

## spirvToolsOptimize() — Performance Passes

**Location**: `SpirvEmitter.cpp:16789`

### Default Performance Pass Suite

When `spirvOptions.optConfig` is empty, `RegisterPerformancePasses()` is called with `preserveInterface`. This registers the standard SPIRV-Tools `-O` suite:

| Category | Passes |
|----------|--------|
| **Dead code** | `WrapOpKill`, `DeadBranchElimination`, `AggressiveDCE` |
| **CFG** | `MergeReturn`, `BlockMerge`, `IfConversion`, `SimplifiedCFG` |
| **Inlining** | `InlineExhaustive`, `InlineOpaque` |
| **Local opts** | `LocalSingleBlockLoadStoreElim`, `LocalSingleStoreElim`, `LocalMultiStoreElim`, `LocalAccessChainConvert`, `LocalLoadElim`, `LocalCopyProp`, `LocalRedundancyElimination`, `LocalDeadInsertElim` |
| **Global opts** | `PrivateToLocal`, `CCP`, `RedundancyElimination` |
| **SSA** | `SSARewrite` |
| **Cleanup** | `CompactIds`, `FreezeSpecConst` |

Additional passes always appended:
- `SpreadVolatileSemantics` — Spreads volatile semantics
- `CompactIds` — Compacts SPIR-V result IDs

### Custom Optimization Config

If `-Oconfig` is specified (sets `spirvOptions.optConfig`), the flags are passed directly to `optimizer.RegisterPassesFromFlags()`, giving full control over which SPIRV-Tools passes run. Example:
```
dxc -spirv -Oconfig="--eliminate-local-single-block,--eliminate-local-single-store" ...
```

### Fixed-Point Iteration

The optimizer runs in a loop up to `kSpirvOptMaxIterations` (5) times:

```cpp
for (unsigned iter = 0; iter < kSpirvOptMaxIterations; ++iter) {
    optimizer.Run(mod->data(), mod->size(), &optimized, options);
    if (optimized.size() == mod->size())
        break;  // Converged
    mod->swap(optimized);
}
```

Convergence is detected when the **binary size** (in 32-bit words) stops changing between iterations.

---

## spirvToolsLegalize() — Legalization Passes

**Location**: `SpirvEmitter.cpp:16849`

Legalization runs **before** optimization and transforms the raw SPIR-V into a form that is both valid and optimizable. It runs when `needsLegalization` is true.

### Pass Sequence

| Order | Pass | Condition |
|-------|------|-----------|
| 1 | `InterfaceVariableScalarReplacement` | If `signaturePacking` |
| 2 | `RegisterLegalizationPasses()` | Always |
| 3 | `ReplaceDescArrayAccessUsingVarIndex` | If `flattenResourceArrays` |
| 4 | `AggressiveDCE` | After resource array flattening |
| 5 | `DescriptorArrayScalarReplacement` | After resource array DCE |
| 6 | `AggressiveDCE` | After descriptor SROA |
| 7 | `DescriptorCompositeScalarReplacement` | If `requiresFlatteningCompositeResources()` |
| 8 | `AggressiveDCE` | After composite flattening |
| 9 | `ConvertToSampledImagePass` | If combining samplers+textures |
| 10 | `AggressiveDCE` | After sampled image conversion |
| 11 | `ReduceLoadSizePass` (threshold 1.1) | If `reduceLoadSize` |
| 12 | `AggressiveDCE` | After load size reduction |
| 13 | `CompactIds` | Always |
| 14 | `SpreadVolatileSemantics` | Always |
| 15 | `FixFuncCallArgumentsPass` | If `fixFuncCallArguments` |

### When Legalization is Needed

`needsLegalization` is set to `true` when any of:

1. **`declIdMapper.requiresLegalization()`** — Detected during resource/type declaration processing. Returns true when:
   - Opaque types (textures, samplers, etc.) are used in structs
   - Counter variables associated with UAVs
   - Complex resource array patterns
   - Non-memory-object declarations that need lowering

2. **`flattenResourceArrays`** — User requested `-fspv-flatten-resource-arrays`

3. **`reduceLoadSize`** — User requested `-fspv-reduce-load-size`

4. **`requiresFlatteningCompositeResources()`** — Composite resources with opaque types

5. **Non-empty `dsetbindingsToCombineImageSampler`** — Samplers and textures need combining

6. **`signaturePacking`** — Signature packing enabled

---

## Post-Optimization Passes

### spirvToolsTrimCapabilities() (Always)

Removes unused capabilities from the SPIR-V module. This runs even at O0 because DXC emits some capabilities unconditionally (to avoid duplicating the detection logic). If optimization removes instructions that require a capability, this pass removes the capability.

### spirvToolsFixupOpExtInst() (Debug)

When rich debug info is enabled, changes `OpExtInst` opcodes to `OpExtInstWithForwardRefsKHR` where needed. This ensures debug instructions with forward references are correctly encoded.

### spirvToolsUpgradeToVulkanMemoryModel() (Optional)

When `-fspv-use-vulkan-memory-model` is set, upgrades the module from GLSL450 memory model to Vulkan memory model.

---

## Key Configuration Flags

| DXC Flag | Option Field | Effect |
|----------|-------------|--------|
| `-O0` | `OptLevel = 0` | Skips `spirvToolsOptimize()` entirely |
| `-O1`/`-O2`/`-O3` | `OptLevel > 0` | Runs optimization |
| `-fcgl` | `codeGenHighLevel` | Skips ALL SPIRV-Tools processing |
| `-fspv-preserve-bindings` | `preserveBindings` | Preserves all bindings during optimization |
| `-fspv-preserve-interface` | `preserveInterface` | Preserves interface variables |
| `-fspv-flatten-resource-arrays` | `flattenResourceArrays` | Triggers resource array legalization |
| `-fspv-reduce-load-size` | `reduceLoadSize` | Triggers load size reduction |
| `-fspv-use-legacy-buffer-layout` | `useLegacyBufferLayout` | Affects layout rules |
| `-Oconfig=<flags>` | `optConfig` | Custom SPIRV-Tools pass configuration |
| `-fspv-print-all` | `printAll` | Dumps module before/after each pass |
| `-Vd` | `disableValidation` | Skips final validation |
| `-fspv-target-env=<env>` | `targetEnv` | Target environment (spv1.0, spv1.1, etc.) |
| `-fspv-preserve-bindings` | `preserveBindings` | Preserve binding numbers |
| `-fspv-max-id=<N>` | `maxId` | Maximum SPIR-V ID bound |

---

## SPIRV-Tools Integration

DXC links against SPIRV-Tools libraries from `external/SPIRV-Tools/`:

- `source/opt/` — Optimizer classes and pass implementations
- `source/opt/optimizer.cpp` — `spvtools::Optimizer` class
- `source/opt/optimizer.hpp` — Public optimizer header

Key API calls:
- `optimizer.RegisterPerformancePasses()` — Standard `-O` passes
- `optimizer.RegisterLegalizationPasses()` — Legalization passes
- `optimizer.RegisterPassesFromFlags()` — Custom flag-based passes
- `optimizer.RegisterPass()` — Single pass registration
- `optimizer.Run()` — Execute passes

The `SpirvEmitter` wraps these in helper methods:
- `spirvToolsRunPass()` — Run a single pass token
- `spirvToolsOptimize()` — Performance optimization with fixed-point
- `spirvToolsLegalize()` — Full legalization sequence
- `spirvToolsFixupOpExtInst()` — Debug instruction fixup
- `spirvToolsTrimCapabilities()` — Capability trimming
- `spirvToolsUpgradeToVulkanMemoryModel()` — Memory model upgrade
- `spirvToolsValidate()` — Final validation
