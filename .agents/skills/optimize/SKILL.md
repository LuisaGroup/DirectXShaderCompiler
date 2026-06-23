---
name: optimize
description: DXC optimization strategy reference. Use when asked about optimization levels (O0/O1/O2/O3), pass pipelines, DXIL/SPIR-V backend optimizations, performance tuning, optconfig flags, aggressive fixed-point optimization, or when debugging misoptimized shaders.
---

# DXC Optimization Strategy

DXC has **two independent optimization pipelines**: the **DXIL backend** (LLVM-based, for DirectX 12) and the **SPIR-V backend** (SPIRV-Tools based, for Vulkan). Both are driven by the compiler's `-O` flag and share the same frontend optimization-level routing but diverge completely after AST emission.

---

## Decision Tree

| User asks about... | Jump to |
|---|---|
| How do optimization levels map to passes? | [Optimization Level Routing](#optimization-level-routing) |
| What passes run in the DXIL pipeline? | [DXIL Optimization Pipeline](#dxil-optimization-pipeline) |
| What passes run in the SPIR-V pipeline? | [SPIR-V Optimization Pipeline](#spirv-optimization-pipeline) |
| How do I tune / disable specific passes? | [Optimization Toggles](#optimization-toggles) |
| What is the aggressive fixed-point optimizer? | [Aggressive Fixed-Point Optimization](#aggressive-fixed-point-optimization) |
| How can I run arbitrary passes on a DXIL blob? | [dxopt Tool & IDxcOptimizer](#dxopt-tool--idxcoptimizer) |
| Where is the pass pipeline constructed? | [Pipeline Construction](#pipeline-construction) |
| How does SPIR-V legalization work? | [SPIR-V Legalization](#spirv-legalization) |
| Where are the DXC-specific analysis passes? | [DXIL Analysis Passes](#dxil-analysis-passes) |
| Where are the DXC-specific transform passes? | [DXIL Transform Passes](#dxil-transform-passes) |
| How to debug a misoptimization? | [Debugging Optimizations](#debugging-optimizations) |

---

## Optimization Level Routing

The `-O` flag controls optimization for **both** backends. The frontend maps levels in `BackendUtil.cpp:CreatePasses()`:

| Flag | `OptLevel` | Behavior |
|------|-----------|----------|
| `-O0` | 0 | Minimal passes; preserves intermediate values; no aggressive opts |
| `-O1` | 1 | Basic cleanup + HLSL lowering; inlining; scalar replacement |
| `-O2` | 2 | Standard LLVM optimization + Aggressive Dxil Opt (`EnableDxilAggressiveOptimize = true`) |
| `-O3` | 3 | Max LLVM optimization + Aggressive Dxil Opt + extra loop unrolling |
| `-Od` | — | Same as `-O0` (disables optimization) |

**Key routing code** (`BackendUtil.cpp:320-371`):
- `CodeGenOpts.DisableLLVMOpts` or `CodeGenOpts.HLSLHighLevel` forces `OptLevel = 0`
- HLSL always-enables inlining (except for high-level mode)
- `PMBuilder.EnableDxilAggressiveOptimize = (OptLevel > 1)` enables the fixed-point optimizer at O2+

**SPIR-V path** (`SpirvEmitter.cpp:994`):
```cpp
if (theCompilerInstance.getCodeGenOpts().OptimizationLevel > 0) {
    spirvToolsOptimize(&m, &messages);
}
```
SPIR-V optimization is **binary on/off**: `-O0` skips it entirely; `-O1`+ runs the full SPIRV-Tools performance pass suite.

---

## DXIL Optimization Pipeline

### Pipeline Order (for `OptLevel > 0`)

The pass pipeline is constructed in `PassManagerBuilder::populateModulePassManager()` (`lib/Transforms/IPO/PassManagerBuilder.cpp:334`).

#### Phase 1 — HLSL Pre-Lowering (`addHLSLPasses()`, line 211)
These DXC-specific passes run **inside** the standard LLVM pass pipeline, interleaved:

| Order | Pass | File | Role |
|-------|------|------|------|
| 1 | `DxilCleanupAddrSpaceCastPass` | `lib/HLSL/` | Clean up address space casts |
| 2 | `HLPreprocessPass` | `lib/HLSL/HLPreprocess.cpp` | Early HLSL IR normalization |
| 3 | `HLDeadFunctionEliminationPass` | `lib/HLSL/HLDeadFunctionElimination.cpp` | Remove dead functions (skip at O0) |
| 4 | `LowerStaticGlobalIntoAlloca` | `lib/HLSL/` | Move static globals to allocas for SROA |
| 5 | `HLExpandStoreIntrinsicsPass` | `lib/HLSL/HLExpandStoreIntrinsics.cpp` | Expand buffer store intrinsics |
| 6 | `SROA_Parameter_HLSL` | `lib/HLSL/` | ScalarReplacement for parameters |
| 7 | `HLMatrixLowerPass` | `lib/HLSL/HLMatrixLowerPass.cpp` | Lower HLSL matrices → LLVM vectors |
| 8 | `DCE` + `GlobalDCE` | LLVM core | Cleanup after matrix lowering |
| 9 | `DynamicIndexingVectorToArrayPass` | `lib/HLSL/` | Replace dynamically indexed vectors with arrays |
| 10 | `LoopRotate` | LLVM core | Prepare loops for mem2reg |
| 11 | `DxilConditionalMem2RegPass` | `lib/Transforms/Scalar/` | mem2reg skipping precise markers |
| 12 | `CleanupDxBreakPass` | `lib/HLSL/` | Remove unused dx.break conditionals |
| 13 | `DxilConvergentMarkPass` | `lib/HLSL/DxilConvergent.cpp` | Mark convergent operations (skip at O0) |
| 14 | `DxilPromoteLocalResources` | `lib/HLSL/DxilPromoteResourcePasses.cpp` | Promote local resources |
| 15 | `DxilPromoteStaticResources` | `lib/HLSL/DxilPromoteResourcePasses.cpp` | Promote static global resources |
| 16 | `InvalidateUndefResourcesPass` | `lib/HLSL/DxilPreparePasses.cpp` | Replace undef resources |
| 17 | **`DxilGenerationPass`** | `lib/HLSL/DxilGenerationPass.cpp` | **The bridge pass** — HLModule → DxilModule; replaces HL intrinsics with `dx.op.*` |
| 18 | `DxilPrecisePropagatePass` | `lib/HLSL/DxilPrecisePropagatePass.cpp` | Propagate `precise` attribute |
| 19 | `ScalarizerPass` | `lib/HLSL/` | Scalarize vector operations |
| 20 | `DxilEliminateVectorPass` | `lib/Transforms/Scalar/DxilEliminateVector.cpp` | Remove remaining vector instructions |
| 21 | `DxilLoopUnrollPass` | `lib/Transforms/Scalar/DxilLoopUnroll.cpp` | Unroll `[unroll]` loops |
| 22 | `LoopUnrollPass` (O3 only) | `lib/Transforms/Scalar/LoopUnrollPass.cpp` | Default loop unrolling |
| 23 | `DxilFixConstArrayInitializerPass` | `lib/Transforms/Scalar/DxilFixConstArrayInitializer.cpp` | Fix const array initializers (O1+) |

#### Phase 2 — Standard LLVM Optimization (lines 417-685)

After HLSL lowering, the pipeline runs standard LLVM optimization passes:

- **Interprocedural**: `IPSCCP`, `GlobalOptimizer`, `DeadArgElimination`, `PruneEH`, `Inliner`, `FunctionAttrs`
- **Scalar**: `SROA`, `CorrelatedValuePropagation`, `CFGSimplification`, `InstCombine`, `Reassociate`, `LoopRotate`, `IndVarSimplify`, `LoopDeletion`, `SimpleLoopUnroll`
- **Memory**: `MergedLoadStoreMotion` (O2+), `GVN` (O2+, configurable), `DxilSimpleGVNHoist` (O2+)
- **Aggressive reassociation** (if enabled): Re-runs `Reassociate` + `GVN` after GVN
- **Region elimination**: `DxilSimpleGVNEliminateRegionPass`
- **Late scalar**: `SCCP`, `BitTrackingDCE`, `InstCombine`, `CorrelatedValuePropagation`, `DSE`, `HoistConstantArrayPass`, `AggressiveDCE`, `CFGSimplification`
- **Loop post-opt**: `LoopRotate`, `LoopUnroll`, `DxilLoopDeletionPass`
- **Global cleanup**: `StripDeadPrototypes`, `GlobalDCE`, `ConstantMerge` (O2+)

#### Phase 3 — Dxil Aggressive Optimization (lines 690-705, O2+)

See [Aggressive Fixed-Point Optimization](#aggressive-fixed-point-optimization).

#### Phase 4 — DXIL Finalization (lines 708-734)

Final mandatory passes to produce valid DXIL:

| Order | Pass | Role |
|-------|------|------|
| 1 | `DxilEraseDeadRegionPass` | Erase dead regions |
| 2 | `DxilConvergentClearPass` | Clear convergent annotations |
| 3 | DCE + GlobalDCE | Cleanup after convergence clear |
| 4 | `MultiDimArrayToOneDimArrayPass` | Flatten multidimensional arrays |
| 5 | `DxilRemoveDeadBlocksPass` | Remove dead blocks |
| 6 | `DxilMutateResourceToHandlePass` | Convert resources to handles |
| 7 | `DxilCleanupDynamicResourceHandlePass` | Clean up dynamic handles |
| 8 | `DxilLowerCreateHandleForLibPass` | Lower CreateHandle for libraries |
| 9 | `DxilTranslateRawBuffer` | Translate raw buffer operations |
| 10 | `DxilLegalizeSampleOffsetPass` | Legalize sample offsets |
| 11 | `DxilFinalizeModulePass` | Finalize the module |
| 12 | `ComputeViewIdStatePass` | Compute view-ID state |
| 13 | `DxilDeadFunctionEliminationPass` | Final dead function elimination |
| 14 | `DxilValidateWaveSensitivityPass` | Validate wave sensitivity |
| 15 | `DxilEmitMetadataPass` | Emit DXIL metadata |

### O0 Path (line 338-400)

At O0, a **reduced pipeline** runs: metadata rehydration, debug output arg rewriting, inlining, HLSL passes, finalization. In `addHLSLPasses` at O0:
- Skips dead function elimination
- Skips convergent marking
- Does not run SimplifyInst/CFGSimplification
- Runs `DxilNoOptSimplifyInstructionsPass` and `DxilNoOptLegalizePass` instead of optimization variants
- Always legalizes sample offsets (loop unrolling not guaranteed)

---

## SPIR-V Optimization Pipeline

### Architecture

The SPIR-V backend uses **SPIRV-Tools** (`external/SPIRV-Tools/`) for optimization and legalization. DXC emits raw SPIR-V, then calls `spirvToolsLegalize()` and `spirvToolsOptimize()` in sequence.

**Entry point** (`SpirvEmitter.cpp:960-1045`):
```
1. If needsLegalization → spirvToolsLegalize()
2. If OptLevel > 0     → spirvToolsOptimize()
3. If debugInfoRich     → spirvToolsFixupOpExtInst()
4. Always                → spirvToolsTrimCapabilities()
```

### SpirvToolsOptimize (`SpirvEmitter.cpp:16789`)

Two modes based on `spirvOptions.optConfig`:

**Default mode** (no custom config):
- `RegisterPerformancePasses()` — the standard SPIRV-Tools `-O` performance pass suite:
  - WrapOpKill, DeadBranchElimination, MergeReturn, InlineExhaustive, AggressiveDCE, PrivateToLocal, LocalSingleBlockLoadStoreElim, LocalSingleStoreElim, LocalMultiStoreElim, LocalAccessChainConvert, LocalLoadElim, LocalCopyProp, LocalRedundancyElimination, LocalDeadInsertElim, CCP, RedundancyElimination, DeadBranchElimination, BlockMerge, IfConversion, SimplifiedCFG, SSARewrite, AggressiveDCE, CompactIds, FreezeSpecConst
- `SpreadVolatileSemantics`
- `CompactIds`

**Custom mode** (`-Oconfig="..."`):
- Parses pass flags directly via `RegisterPassesFromFlags()` — full access to all SPIRV-Tools passes

**Fixed-point iteration** (both modes): Runs up to `kSpirvOptMaxIterations` (5) times until binary size stabilizes. This is the same convergence concept as the DXIL aggressive optimizer.

### SpirvToolsLegalize (`SpirvEmitter.cpp:16849`)

Runs when the emitted SPIR-V requires normalization before optimization:

1. **Interface variable SROA** (if `signaturePacking`)
2. **Legalization passes** (`RegisterLegalizationPasses()`)
3. **Resource array flattening** (if `flattenResourceArrays`):
   - `ReplaceDescArrayAccessUsingVarIndex`
   - `AggressiveDCE`
   - `DescriptorArrayScalarReplacement`
   - `AggressiveDCE`
4. **Composite resource flattening** (if needed):
   - `DescriptorCompositeScalarReplacement`
   - `AggressiveDCE`
5. **Sampled image combining** (if needed):
   - `ConvertToSampledImagePass`
   - `AggressiveDCE`
6. **Reduce load size** (if `reduceLoadSize`):
   - `ReduceLoadSizePass`
   - `AggressiveDCE`
7. `CompactIds`, `SpreadVolatileSemantics`
8. `FixFuncCallArgumentsPass` (if `fixFuncCallArguments`)

### When is Legalization Needed?

Legalization is triggered (`needsLegalization = true`) when:
- `declIdMapper.requiresLegalization()` — opaque types, complex resource patterns
- `flattenResourceArrays` is set
- `reduceLoadSize` is set
- `requiresFlatteningCompositeResources()` is true
- Non-empty `dsetbindingsToCombineImageSampler`
- `signaturePacking` is enabled

---

## Aggressive Fixed-Point Optimization

**File**: `lib/HLSL/DxilAggressiveOptimize.cpp`

This is a DXC-invented pass that runs at **O2+** on the DXIL backend. Inspired by the SPIR-V backend's fixed-point loop, it repeatedly runs a curated set of LLVM passes until the IR size (function count + instruction count) stabilizes.

### Default Pass Set

Each iteration runs:
- **Pass Set A (transformative)**:
  - `SROA` — Scalar Replacement of Aggregates
  - `GlobalOptimizer` — Global variable optimization
  - `IPSCCP` — Interprocedural Sparse Conditional Constant Propagation
  - `CorrelatedValuePropagation` — Value range propagation
  - `Reassociate` (run repeatedly) — Expression reassociation
  - `GVN` — Global Value Numbering (with loads)
- **Pass Set B (cleanup)**:
  - `CFGSimplification` — Merge blocks, remove unreachable
  - `InstCombine` — Instruction simplification
  - `DCE` — Dead Code Elimination
  - `AggressiveDCE` — Aggressive DCE

### Custom Pass Sets

Via `-Oconfig_dxil <pass1,pass2,...>`, users can specify an arbitrary comma-separated list of LLVM pass names to run instead of the default set.

### Configuration Options

| Flag | Option | Default | Description |
|------|--------|---------|-------------|
| `-Oconfig_dxil` | `DxilOptConfig` | empty | Custom comma-separated pass list |
| `-dxil_opt_max_iterations` | `DxilOptMaxIterations` | 5 | Max fixed-point iterations |
| `-dxil_opt_print_each` | `DxilOptPrintEach` | false | Print IR after each iteration |
| `-dxil_opt_validate_each` | `DxilOptValidateEach` | false | Validate module at each iteration |

---

## Optimization Toggles

**File**: `include/dxc/Support/HLSLOptions.h:239`

The `-opt_enable`, `-opt_disable`, and `-opt_select` flags control individual pass toggles:

| Toggle | Control | Default |
|--------|---------|---------|
| `TOGGLE_GVN` | Enables/disables GVN | ON |
| `TOGGLE_SINK` | Enables/disables instruction sinking | ON |
| `TOGGLE_STRUCTURIZE_LOOP_EXITS_FOR_UNROLL` | Structurize loop exits before unrolling | OFF |
| `TOGGLE_DEBUG_NOPS` | Insert debug NOPs for preservation | OFF |
| `TOGGLE_LIFETIME_MARKERS` | Insert lifetime intrinsics | OFF |
| `TOGGLE_PARTIAL_LIFETIME_MARKERS` | Partial lifetime markers | OFF |
| `TOGGLE_ENABLE_AGGRESSIVE_REASSOCIATION` | Extra reassociate+GVN pass after GVN | OFF |

---

## DXIL Analysis Passes

DXC extends LLVM's analysis framework with shader-specific analyses:

| Pass | File | Purpose |
|------|------|---------|
| `DxilValueCache` | `lib/Analysis/DxilValueCache.cpp` | Constant-value cache for DXIL instructions; tracks reachable blocks and constant conditions |
| `DxilSimplify` | `lib/Analysis/DxilSimplify.cpp` | DXIL-aware instruction simplification |
| `DxilConstantFolding` | `lib/Analysis/DxilConstantFolding.cpp` | Folds constant expressions with DXIL intrinsics |
| `ReducibilityAnalysis` | `lib/Analysis/ReducibilityAnalysis.cpp` | Checks CFG reducibility (required for DXIL) |
| `DxilValueCache` (pass) | Used by `DxilEliminateVector`, `DxilConditionalMem2Reg`, etc. | Provides fast constant-value lookups |

---

## DXIL Transform Passes

Custom transforms not in the standard LLVM pipeline:

| Pass | File | Purpose |
|------|------|---------|
| `StructurizeCFG` | `lib/Transforms/Scalar/StructurizeCFG.cpp` | Converts unstructured CFG to structured (required for DXIL) |
| `DxilEliminateVector` | `lib/Transforms/Scalar/DxilEliminateVector.cpp` | Eliminates vector ops; required since DXIL forbids certain vectors |
| `DxilLoopUnroll` | `lib/Transforms/Scalar/DxilLoopUnroll.cpp` | Unrolls `[unroll]` attributed loops before resource lowering |
| `DxilConditionalMem2Reg` | `lib/Transforms/Scalar/DxilConditionalMem2Reg.cpp` | mem2reg that respects `precise` markers |
| `DxilEraseDeadRegion` | `lib/Transforms/Scalar/DxilEraseDeadRegion.cpp` | Erase dead regions from convergence/divergence |
| `DxilRemoveUnstructuredLoopExits` | `lib/Transforms/Scalar/DxilRemoveUnstructuredLoopExits.cpp` | Prepare loops for structurization |
| `DxilRemoveDeadBlocks` | `lib/Transforms/Scalar/DxilRemoveDeadBlocks.cpp` | Remove unreachable blocks |
| `DxilFixConstArrayInitializer` | `lib/Transforms/Scalar/DxilFixConstArrayInitializer.cpp` | Fix constant array initializer issues |
| `DxilLoopDeletion` | `lib/HLSL/DxilLoopDeletion.cpp` | DXIL-aware loop deletion |
| `DxilSimpleGVNHoist` | `lib/HLSL/DxilSimpleGVNHoist.cpp` | GVN-based hoisting for DXIL |
| `DxilLegalizeSampleOffsetPass` | `lib/HLSL/DxilLegalizeSampleOffsetPass.cpp` | Legalize sample offsets |
| `DxilNoOptLegalize` | `lib/HLSL/DxilNoOptLegalize.cpp` | Legalization for -O0 path |
| `DxilScalarizeVectorIntrinsics` | `lib/HLSL/DxilScalarizeVectorIntrinsics.cpp` | Scalarize DXIL vector intrinsics |

---

## SPIR-V Capability Trimming

**File**: `SpirvEmitter.cpp:16776` — `spirvToolsTrimCapabilities()`

After optimization, DXC runs capability trimming **always** (even at O0). This removes unused capabilities that may have been emitted unconditionally. Some optimization passes like DCE can make capabilities unused, so this pass cleans them up.

---

## dxopt Tool & IDxcOptimizer

**Tool**: `tools/clang/tools/dxopt/dxopt.cpp`
**Implementation**: `lib/HLSL/DxcOptimizer.cpp`

The `dxopt` tool and `IDxcOptimizer` COM interface allow running arbitrary LLVM passes on a DXIL blob (full container or raw bitcode).

Usage:
```
dxopt input.dxil -pass1 -pass2,arg=value -S -o output.dxil
```

Key features:
- Enumerates all registered LLVM passes via `PassRegistry`
- Supports pass arguments (`-pass,arg=value`)
- Can output assembly (`-S`) or bitcode
- Reads from DXIL containers (including debug modules)
- Restores container metadata (RDAT, RTS0, PSV0, STAT)

---

## Pipeline Construction

### Where Passes are Built

| File | Role |
|------|------|
| `tools/clang/lib/CodeGen/BackendUtil.cpp` | Orchestrates pass creation; maps `OptLevel` → PassManagerBuilder |
| `lib/Transforms/IPO/PassManagerBuilder.cpp` | Populates the module pass pipeline (`populateModulePassManager`) |
| `lib/Transforms/IPO/PassManagerBuilder.cpp:211` | `addHLSLPasses()` — DXC-specific pass injection |
| `lib/HLSL/DxilAggressiveOptimize.cpp` | Aggressive fixed-point optimization pass |

### High-Level vs. Low-Level Mode

When `CodeGenOpts.HLSLHighLevel` is true (the `-fcgl` flag):
- `OptLevel` is forced to 0
- HLSL passes stop after `HLEmitMetadataPass`
- No DXIL lowering, no resource promotion, no finalization
- Used for HLSL → high-level IR preview/debugging

---

## Debugging Optimizations

### Dump Pass Pipeline
- `-opt_dump` — Prints the optimizer pass pipeline configuration
- `-print_before_all` / `-print_before=<pass>` — Print IR before each/all passes
- `-print_after_all` / `-print_after=<pass>` — Print IR after each/all passes

### Debug Aggressive Optimization
- `-dxil_opt_print_each` — Print module IR at each iteration
- `-dxil_opt_validate_each` — Validate module at each iteration
- `-dxil_opt_max_iterations N` — Limit iterations

### SPIR-V Debug
- `-fspv-print-all` — Dump SPIR-V binary before each pass and after the last
- SPIRV-Tools messages are captured and reported as warnings/errors

### Key Diagnostics
- `HLSLNoSink` — Controls instruction sinking (off for DXIL by default)
- `HLSLResMayAlias` — Controls whether resources may alias (disables GVN hoisting when false)
- `ScanLimit` — Controls DSE scan limit (`-memdep_block_scan_limit`)

### Common Misoptimization Patterns

| Symptom | Likely Cause | Debug |
|---------|-------------|-------|
| Missing resource access | Aggressive DCE removing live resource handles | Try `-opt_disable gvn` or `-O0` |
| Wave operation issues | Convergence annotations stripped too early | Check `DxilConvergentClearPass` / `DxilConvergentMarkPass` |
| Loop unrolling failures | Loop exits not structurized | Try `-opt_enable structurize_loop_exits_for_unroll` |
| Vector ops in DXIL | Vector elimination didn't run | Check `DxilEliminateVectorPass` / `ScalarizerPass` |
| SPIR-V validation failure | Legalization skipped or insufficient | Check `needsLegalization` flags; try `-fcgl` to inspect pre-legalization |
| Binary too large | Optimization didn't converge | Increase `-dxil_opt_max_iterations`; check if custom passes cause oscillation |

---

## Key Files Reference

| Area | Files |
|------|-------|
| Pass pipeline construction | `tools/clang/lib/CodeGen/BackendUtil.cpp`, `lib/Transforms/IPO/PassManagerBuilder.cpp` |
| DXIL aggressive optimizer | `lib/HLSL/DxilAggressiveOptimize.cpp`, `include/dxc/HLSL/DxilAggressiveOptimize.h` |
| IDxcOptimizer | `lib/HLSL/DxcOptimizer.cpp`, `tools/clang/tools/dxopt/dxopt.cpp` |
| SPIR-V optimization | `tools/clang/lib/SPIRV/SpirvEmitter.cpp` (lines ~960-1045, ~16730-16919) |
| SPIR-V options | `include/dxc/Support/SPIRVOptions.h` |
| HLSL options & toggles | `include/dxc/Support/HLSLOptions.h` |
| DxilGenerationPass | `lib/HLSL/DxilGenerationPass.cpp`, `include/dxc/HLSL/DxilGenerationPass.h` |
| HLSL lowering passes | `lib/HLSL/HLMatrixLowerPass.cpp`, `lib/HLSL/HLOperationLower.cpp`, `lib/HLSL/HLSignatureLower.cpp` |
| DXIL analysis passes | `lib/Analysis/DxilValueCache.cpp`, `lib/Analysis/DxilSimplify.cpp`, `lib/Analysis/DxilConstantFolding.cpp` |
| DXIL transform passes | `lib/Transforms/Scalar/Dxil*.cpp`, `lib/HLSL/Dxil*.cpp` |
| StructurizeCFG | `lib/Transforms/Scalar/StructurizeCFG.cpp` |
| SPIRV-Tools linking | `external/SPIRV-Tools/` |
