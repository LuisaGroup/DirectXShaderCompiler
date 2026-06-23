# DXIL Optimization Pipeline — Detailed Reference

> **Audience:** Contributors modifying or debugging the DXIL optimization pipeline.
> **Last Updated:** Auto-generated from DXC source analysis.

---

## Complete Pass Pipeline Sequence (O2/O3)

The following is the full linear pass pipeline as constructed by `PassManagerBuilder::populateModulePassManager()` in `lib/Transforms/IPO/PassManagerBuilder.cpp`.

### Phase 1: Setup & Early Legalization

| # | Pass | Trigger | File |
|---|------|---------|------|
| 1 | `HLEnsureMetadataPass` | Always | `lib/HLSL/HLMetadataPasses.cpp` |
| 2 | `DxilRewriteOutputArgDebugInfoPass` | Always | `lib/HLSL/` |
| 3 | `HLLegalizeParameter` | Always | `lib/HLSL/HLLegalizeParameter.cpp` |
| 4 | `Inliner` (early) | If `HLSLEarlyInlining` | LLVM core |

### Phase 2: HLSL Lowering (`addHLSLPasses`)

| # | Pass | O0? | File |
|---|------|-----|------|
| 5 | `DxilCleanupAddrSpaceCastPass` | Yes | `lib/HLSL/` |
| 6 | `HLPreprocessPass` | Yes | `lib/HLSL/HLPreprocess.cpp` |
| 7 | `HLDeadFunctionEliminationPass` | No | `lib/HLSL/HLDeadFunctionElimination.cpp` |
| 8 | `LowerStaticGlobalIntoAlloca` | Yes | `lib/HLSL/` |
| 9 | `HLExpandStoreIntrinsicsPass` | Yes | `lib/HLSL/HLExpandStoreIntrinsics.cpp` |
| 10 | `SROA_Parameter_HLSL` | Yes | `lib/HLSL/` |
| 11 | `HLMatrixLowerPass` | Yes | `lib/HLSL/HLMatrixLowerPass.cpp` |
| 12 | `DCE` | Yes | LLVM core |
| 13 | `GlobalDCE` | Yes | LLVM core |
| 14 | `DxilLegalizeEvalOperationsPass` | O0 only | `lib/HLSL/DxilLegalizeEvalOperations.cpp` |
| 15 | `LowerStaticGlobalIntoAlloca` (2nd) | Yes | `lib/HLSL/` |
| 16 | `DynamicIndexingVectorToArrayPass` | Yes | `lib/HLSL/` |
| 17 | `LoopRotatePass` | Yes | `lib/HLSL/` |
| 18 | `DxilConditionalMem2RegPass` | Yes | `lib/Transforms/Scalar/DxilConditionalMem2Reg.cpp` |
| 19 | `DxilDeleteRedundantDebugValuesPass` | Yes | `lib/HLSL/DxilDeleteRedundantDebugValues.cpp` |
| 20 | `CleanupDxBreakPass` | Yes | `lib/HLSL/` |
| 21 | `DxilConvergentMarkPass` | No | `lib/HLSL/DxilConvergent.cpp` |
| 22 | `SROA` + `SimplifyInst` + `JumpThreading` | If lifetime markers & !partial | LLVM core |
| 23 | `SimplifyInstPass` | No | LLVM core |
| 24 | `CFGSimplificationPass` | No | LLVM core |
| 25 | `DxilPromoteLocalResources` | Yes | `lib/HLSL/DxilPromoteResourcePasses.cpp` |
| 26 | `DxilPromoteStaticResources` | Yes | `lib/HLSL/DxilPromoteResourcePasses.cpp` |
| 27 | `InvalidateUndefResourcesPass` | Yes | `lib/HLSL/DxilPreparePasses.cpp` |
| 28 | **`DxilGenerationPass`** | Yes | `lib/HLSL/DxilGenerationPass.cpp` |
| 29 | `DxilPrecisePropagatePass` | Yes | `lib/HLSL/DxilPrecisePropagatePass.cpp` |
| 30 | `SimplifyInstPass` | No | LLVM core |
| 31 | `ScalarizerPass` | Yes | `lib/HLSL/` |
| 32 | `DxilEliminateVectorPass` | Yes | `lib/Transforms/Scalar/DxilEliminateVector.cpp` |
| 33 | `DxilLoopUnrollPass` | Yes | `lib/Transforms/Scalar/DxilLoopUnroll.cpp` |
| 34 | `LoopUnrollPass` | O3 only | LLVM core |
| 35 | `SimplifyInstPass` | No | LLVM core |
| 36 | `CFGSimplificationPass` | No | LLVM core |
| 37 | `DCE` | Yes | LLVM core |
| 38 | `DxilFixConstArrayInitializerPass` | O1+ | `lib/Transforms/Scalar/DxilFixConstArrayInitializer.cpp` |

### Phase 3: Standard LLVM Optimization

| # | Pass | Condition |
|---|------|-----------|
| 39 | `TargetLibraryInfoWrapperPass` | If LibraryInfo |
| 40 | Alias Analysis setup | Always |
| 41 | `IPSCCPPass` | Always |
| 42 | `GlobalOptimizerPass` | Always |
| 43 | `DeadArgEliminationPass` | Always |
| 44 | `InstCombine` | Always |
| 45 | `CFGSimplificationPass` | Always |
| 46 | `PruneEHPass` | Always |
| 47 | `Inliner` (late) | If not early-inlined |
| 48 | `FunctionAttrsPass` | Always |
| 49 | `SROA` (new SROA or ScalarRepl) | Always |
| 50 | `CorrelatedValuePropagation` | Always |
| 51 | `CFGSimplificationPass` | Always |
| 52 | `InstCombine` | Always |
| 53 | `CFGSimplificationPass` | Always |
| 54 | `Reassociate` | Always |
| 55 | `LoopRotatePass` | Always |
| 56 | `InstCombine` | Always |
| 57 | `IndVarSimplifyPass` | Always |
| 58 | `LoopDeletionPass` | Always |
| 59 | `LoopInterchangePass` | If enabled |
| 60 | `SimpleLoopUnrollPass` | If not disabled |
| 61 | `MergedLoadStoreMotion` | O2+ & enabled |
| 62 | `GVN` (+ `DxilSimpleGVNHoist`) | O2+ & `EnableGVN` |
| 63 | `Reassociate` + `GVN` (again) | If `HLSLEnableAggressiveReassociation` |
| 64 | `DxilSimpleGVNEliminateRegionPass` | Always |
| 65 | `SCCP` | Always |
| 66 | `BitTrackingDCE` | Always |
| 67 | `InstCombine` | Always |
| 68 | `CorrelatedValuePropagation` | Always |
| 69 | `DSE` | Always |
| 70 | `HoistConstantArrayPass` | Always |
| 71 | `AggressiveDCE` | Always |
| 72 | `CFGSimplificationPass` | Always |
| 73 | `InstCombine` | Always |
| 74 | `BarrierNoopPass` | Always |
| 75 | `Float2IntPass` | If enabled |
| 76 | `LoopRotatePass` (2nd) | Always |
| 77 | `LoopDistributePass` | If enabled |
| 78 | `InstCombine` | Always |
| 79 | `DxilLoopDeletionPass` | Always |
| 80 | `LoopUnrollPass` | If not disabled |
| 81 | `InstCombine` | If loop unroll ran |
| 82 | `AlignmentFromAssumptionsPass` | Always |
| 83 | `StripDeadPrototypesPass` | Always |
| 84 | `EliminateAvailableExternallyPass` | O2+ & !PrepareForLTO |
| 85 | `GlobalDCE` | O2+ |
| 86 | `ConstantMergePass` | O2+ |
| 87 | `MergeFunctionsPass` | If enabled |

### Phase 4: DXIL Aggressive Optimization (O2+)

| # | Pass | File |
|---|------|------|
| 88 | `DxilAggressiveOptimize` | `lib/HLSL/DxilAggressiveOptimize.cpp` |

### Phase 5: DXIL Finalization

| # | Pass | File |
|---|------|------|
| 89 | `DxilEraseDeadRegionPass` | `lib/Transforms/Scalar/DxilEraseDeadRegion.cpp` |
| 90 | `DxilConvergentClearPass` | `lib/HLSL/DxilConvergent.cpp` |
| 91 | `DCE` | LLVM core |
| 92 | `MultiDimArrayToOneDimArrayPass` | `lib/HLSL/` |
| 93 | `DxilRemoveDeadBlocksPass` | `lib/Transforms/Scalar/DxilRemoveDeadBlocks.cpp` |
| 94 | `DCE` | LLVM core |
| 95 | `GlobalDCE` | LLVM core |
| 96 | `DxilMutateResourceToHandlePass` | `lib/HLSL/` |
| 97 | `DxilCleanupDynamicResourceHandlePass` | `lib/HLSL/` |
| 98 | `DxilLowerCreateHandleForLibPass` | `lib/HLSL/` |
| 99 | `DxilTranslateRawBuffer` | `lib/HLSL/DxilTranslateRawBuffer.cpp` |
| 100 | `DxilLegalizeSampleOffsetPass` | `lib/HLSL/DxilLegalizeSampleOffsetPass.cpp` |
| 101 | `DxilFinalizeModulePass` | `lib/HLSL/` |
| 102 | `ComputeViewIdStatePass` | `lib/HLSL/ComputeViewIdStateBuilder.cpp` |
| 103 | `DxilDeadFunctionEliminationPass` | `lib/HLSL/` |
| 104 | `DxilDeleteRedundantDebugValuesPass` | `lib/HLSL/DxilDeleteRedundantDebugValues.cpp` |
| 105 | `NoPausePassesPass` | `lib/HLSL/PauseResumePasses.cpp` |
| 106 | `DxilValidateWaveSensitivityPass` | `lib/HLSL/` |
| 107 | `DxilEmitMetadataPass` | `lib/HLSL/HLMetadataPasses.cpp` |

---

## O0 Pipeline Differences

At O0, the pipeline is significantly shorter:

1. `HLEnsureMetadataPass`
2. `DxilRewriteOutputArgDebugInfoPass`
3. `DxilInsertPreservesPass` (if debug NOPs enabled)
4. `HLLegalizeParameter` + `Inliner`
5. `DxilPreserveToSelectPass`
6. `addHLSLPasses()` (with `NoOpt = true`)
7. Post-HLSL cleanup (simplified):
   - `DxilConvergentClearPass`
   - `DxilSimpleGVNEliminateRegionPass`
   - `DCE`, `DxilRemoveDeadBlocksPass`, `DxilEraseDeadRegionPass`
   - `DxilNoOptSimplifyInstructionsPass`
   - `GlobalOptimizerPass`
   - `MultiDimArrayToOneDimArrayPass`
   - `DCE`, `GlobalDCE`
   - `DxilMutateResourceToHandlePass`
   - `DxilCleanupDynamicResourceHandlePass`
   - `DxilLowerCreateHandleForLibPass`
   - `DxilTranslateRawBuffer`
   - `DxilLegalizeSampleOffsetPass`
   - `DxilNoOptLegalizePass`
   - `DxilFinalizePreservesPass`
   - `DxilFinalizeModulePass`
   - `ComputeViewIdStatePass`
   - `DxilDeadFunctionEliminationPass`
   - `DxilDeleteRedundantDebugValuesPass`
   - `NoPausePassesPass`
   - `DxilEmitMetadataPass`

Key differences from optimized path:
- Uses `DxilNoOptSimplifyInstructionsPass` instead of `InstCombine` + repeated `CFGSimplification`
- Uses `DxilNoOptLegalizePass` instead of full legalization
- Uses `DxilFinalizePreservesPass`
- Skips `DxilValidateWaveSensitivityPass`

---

## Custom Pass Ordering

Via `-opt_select`, users can control pass ordering from a pre-defined list. Passes are also individually toggleable via `-opt_enable` / `-opt_disable`. The `OptimizationToggles` class in `HLSLOptions.h` manages the boolean state for each toggle, and `PassManagerBuilder` reads them.
