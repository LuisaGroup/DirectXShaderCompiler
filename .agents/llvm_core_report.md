# LLVM Core (IR, CodeGen, Analysis, Transforms) Analysis

This report analyzes the LLVM core libraries within the DirectX Shader Compiler (DXC) project. These libraries form the backbone of the compiler, handling intermediate representation (IR), machine code generation, program analysis, and optimization transforms.

**Directories Analyzed:**
- `lib/IR` — LLVM Intermediate Representation
- `lib/CodeGen` — Target-Independent Code Generation
- `lib/Analysis` — Program Analysis Framework
- `lib/Transforms` — Optimization Passes
- `lib/Passes` — Pass Pipeline Infrastructure

---

## Overview

The LLVM core in DXC is a fork of LLVM 3.7 adapted for HLSL/DXIL compilation. It retains the standard LLVM architecture:

1. **IR Layer**: Defines in-memory representation of programs (Values, Instructions, Functions, Modules).
2. **Analysis Layer**: Computes properties of IR (alias analysis, dominators, loops, scalar evolution).
3. **Transforms Layer**: Modifies IR to improve performance or prepare for code generation.
4. **CodeGen Layer**: Lowers IR to target-specific machine code via SelectionDAG and register allocation.
5. **Passes Layer**: Orchestrates which passes run and in what order.

DXC-specific extensions (marked as "HLSL Change" in source) include DXIL constant folding, DXIL simplification, vector elimination, loop unroll heuristics tailored for shaders, and integration with the DXIL module metadata system.

---

## Directory: `lib/IR`

**Purpose:** Implements the LLVM Intermediate Representation — the in-memory data structures that represent a program.

### Structure
- **Flat directory** (no subdirectories)
- ~57 source/header files

### Key Files and Their Purposes

| File | Purpose |
|------|---------|
| `Core.cpp` | Common initialization for libLLVMCore; C bindings for IR operations; registers core passes (Verifier, DominatorTree, printers). |
| `Value.cpp` | Implements `Value`, `ValueHandle`, and `User` classes — the base of all IR entities. Manages use-def chains and value handles. |
| `Instruction.cpp` | Implements the `Instruction` class — base for all IR instructions. Manages parent BasicBlock linkage, insertion, and removal. |
| `Instructions.cpp` | Implements all non-inline methods for concrete instruction classes (`CallInst`, `LoadInst`, `StoreInst`, `PHINode`, etc.). |
| `Function.cpp` | Implements `Function` and `Argument` classes. Manages function symbol table, argument list, and attribute handling. |
| `Module.cpp` | Implements `Module` — top-level container for functions, global variables, and aliases. Includes DXC-specific `ResetHLModule()` / `ResetDxilModule()` hooks. |
| `BasicBlock.cpp` | Implements `BasicBlock` — container of instructions. HLSL Change: uses `UnreachableInst` as a sentinel for the instruction list. |
| `Type.cpp` | Implements `Type` hierarchy (`IntegerType`, `PointerType`, `VectorType`, `StructType`, etc.). |
| `Constants.cpp` | Implements `Constant` hierarchy (`ConstantInt`, `ConstantFP`, `ConstantArray`, `ConstantStruct`, etc.). |
| `LLVMContext.cpp` | Implements `LLVMContext` — owns global state (types, metadata kinds, constants). Wraps opaque `LLVMContextImpl`. |
| `LLVMContextImpl.cpp/h` | Private implementation of LLVMContext — caches types, metadata, and constants. |
| `Pass.cpp` | Implements the base `Pass` class and derived classes (`ModulePass`, `FunctionPass`, `BasicBlockPass`). |
| `LegacyPassManager.cpp` | Implements the legacy pass manager infrastructure that schedules and runs passes. |
| `PassManager.cpp` | Implements the new pass manager (thin wrapper around `FunctionAnalysisManagerModuleProxy`). |
| `Verifier.cpp` | Implements IR verification — checks SSA form, type consistency, terminator placement, PHI node structure, etc. |
| `AsmWriter.cpp` | Implements LLVM assembly (`.ll`) text output. |
| `IRBuilder.cpp` | Implements `IRBuilder` — helper for creating instructions with a consistent API. |
| `Dominators.cpp` | Implements `DominatorTree` and `DomTreeNode` using generic dominator construction algorithms. |
| `Attributes.cpp` | Implements function/parameter attributes (`Attribute`, `AttributeSet`). |
| `Metadata.cpp` | Implements metadata nodes (`MDNode`, `MDString`, `ValueAsMetadata`). |
| `DebugInfo.cpp` / `DebugInfoMetadata.cpp` | Implements DWARF/debug info metadata generation and manipulation. |
| `DIBuilder.cpp` | Helper API for constructing debug info metadata. |
| `DataLayout.cpp` | Implements `DataLayout` — specifies type sizes, alignments, and endianness. |
| `Mangler.cpp` | Implements name mangling for symbols. |
| `GCOV.cpp` | GCOV profiling support. |
| `AutoUpgrade.cpp` | Auto-upgrades bitcode from older LLVM versions. |
| `Operator.cpp` | Implements operator classes (`GEPOperator`, etc.). |
| `Use.cpp` / `User.cpp` | Implement the use-def chain infrastructure. |
| `ValueSymbolTable.cpp` | Symbol table for named values within a function. |
| `SymbolTableListTraitsImpl.h` | Template implementation for intrusive lists used by Module, Function, and BasicBlock. |
| `IntrinsicInst.cpp` | Implements intrinsic instruction subclasses. |
| `IRPrintingPasses.cpp` | Passes that print IR (`PrintModulePass`, `PrintFunctionPass`). |
| `Statepoint.cpp` | Statepoint GC support. |
| `ConstantFold.cpp/h` | Constant folding for IR-level expressions. |

### Main Classes and Responsibilities

- **`Value`** — Base class for all IR entities. Tracks type, use list, and subclass ID.
- **`User`** — Base class for values that have operands (instructions, constants).
- **`Instruction`** — Base class for all IR instructions. Linked into a BasicBlock.
- **`BasicBlock`** — Sequence of instructions ending with a terminator.
- **`Function`** — Contains arguments, basic blocks, and attributes.
- **`Module`** — Top-level container. Owns functions, globals, aliases, and named metadata.
- **`LLVMContext`** — Global state container. Type and constant uniquing happens here.
- **`Type`** / **`IntegerType`** / **`PointerType`** / **`VectorType`** — Type system.
- **`Constant`** / **`ConstantInt`** / **`ConstantFP`** — Immutable constant values.
- **`Pass`** / **`ModulePass`** / **`FunctionPass`** — Pass infrastructure base classes.
- **`DominatorTree`** — CFG dominance information for SSA verification and optimization.
- **`Verifier`** — Pass that checks IR well-formedness.

---

## Directory: `lib/CodeGen`

**Purpose:** Target-independent code generation — lowers LLVM IR to machine instructions and eventually to assembly or object code.

### Structure
- **Top-level:** ~140 source/header files
- **Subdirectories:**
  - `AsmPrinter/` — Assembly and debug info emission
  - `MIRParser/` — Machine IR parser
  - `SelectionDAG/` — DAG-based instruction selection

### Key Files and Their Purposes

#### Top-Level CodeGen

| File | Purpose |
|------|---------|
| `CodeGen.cpp` | Initializes all CodeGen passes in the pass registry. |
| `LLVMTargetMachine.cpp` | Implements `LLVMTargetMachine` — base for target-specific code generation setups. |
| `Passes.cpp` | Defines standard target-independent CodeGen pass pipelines. |
| `CodeGenPrepare.cpp` | IR-level prepass for SelectionDAG: sinks address computations, expands selects, prepares branches. |
| `MachineFunction.cpp` | Implements `MachineFunction` — machine-level representation of a function (frame info, constant pool, register info). |
| `MachineInstr.cpp` | Implements `MachineInstr` and `MachineOperand` — target-independent machine instructions. |
| `MachineBasicBlock.cpp` | Implements `MachineBasicBlock` — sequence of machine instructions. |
| `MachineRegisterInfo.cpp` | Tracks virtual and physical register usage in a `MachineFunction`. |
| `MachineFunctionPass.cpp` | Base class for passes operating on `MachineFunction`. |
| `MachineModuleInfo.cpp` | Module-level machine code metadata. |
| `MachineDominators.cpp` / `MachineLoopInfo.cpp` | Machine-level dominator and loop analyses. |
| `LiveIntervalAnalysis.cpp` | Computes live intervals for virtual registers. |
| `LiveVariables.cpp` / `LivePhysRegs.cpp` / `LiveRegMatrix.cpp` | Liveness analyses for register allocation. |
| `RegAllocGreedy.cpp` | Greedy register allocator (default optimized allocator). |
| `RegAllocFast.cpp` | Fast register allocator (used at -O0). |
| `RegAllocBasic.cpp` / `RegAllocPBQP.cpp` | Alternative register allocators. |
| `RegisterCoalescer.cpp` | Merges copy-related live ranges to reduce spills. |
| `StackColoring.cpp` / `StackSlotColoring.cpp` | Reduces stack usage by merging non-overlapping stack slots. |
| `PrologEpilogInserter.cpp` | Inserts function prologue/epilogue code. |
| `MachineScheduler.cpp` / `ScheduleDAG.cpp` / `PostRASchedulerList.cpp` | Instruction scheduling before and after register allocation. |
| `BranchFolding.cpp` | Machine-level branch optimization and tail merging. |
| `IfConversion.cpp` | Converts branches to predicated instructions. |
| `TailDuplication.cpp` | Duplicates tail blocks to enable fall-through optimization. |
| `PeepholeOptimizer.cpp` | Machine-level peephole optimizations. |
| `TwoAddressInstructionPass.cpp` | Converts three-address instructions to two-address form. |
| `PHIElimination.cpp` | Lowers PHI nodes to register copies. |
| `ExpandISelPseudos.cpp` / `ExpandPostRAPseudos.cpp` | Expands pseudo-instructions. |
| `DeadMachineInstructionElim.cpp` | Removes dead machine instructions. |
| `MachineCSE.cpp` / `MachineLICM.cpp` / `MachineSink.cpp` | Machine-level CSE, LICM, and sinking. |
| `GlobalMerge.cpp` | Merges global variables to reduce address computation. |
| `IntrinsicLowering.cpp` | Lowers intrinsic calls to standard IR or libcalls. |
| `AtomicExpandPass.cpp` | Expands atomic operations for targets without native support. |
| `WinEHPrepare.cpp` / `DwarfEHPrepare.cpp` / `SjLjEHPrepare.cpp` | Exception handling preparation. |
| `GCStrategy.cpp` / `GCRootLowering.cpp` / `GCMetadata.cpp` | Garbage collection support. |
| `StackProtector.cpp` | Stack canary insertion. |
| `FaultMaps.cpp` / `StackMaps.cpp` | Runtime metadata for stack maps and faulting. |

#### `SelectionDAG/` Subdirectory

| File | Purpose |
|------|---------|
| `SelectionDAG.cpp` | Implements `SelectionDAG` data structure — DAG of operations for a basic block. |
| `SelectionDAGISel.cpp` | Main instruction selection pass using SelectionDAG. Integrates FastISel and DAG-based selection. |
| `SelectionDAGBuilder.cpp/h` | Builds SelectionDAG from LLVM IR instructions. |
| `DAGCombiner.cpp` | DAG combiner — performs algebraic simplification on the DAG. |
| `LegalizeDAG.cpp` / `LegalizeTypes.cpp` / `LegalizeVectorTypes.cpp` / `LegalizeFloatTypes.cpp` / `LegalizeIntegerTypes.cpp` | Legalizes DAG nodes for target capabilities. |
| `ScheduleDAGSDNodes.cpp/h` | Schedules SelectionDAG nodes into machine instructions. |
| `ScheduleDAGFast.cpp` / `ScheduleDAGRRList.cpp` / `ScheduleDAGVLIW.cpp` | Different scheduling algorithms. |
| `FastISel.cpp` | Fast instruction selection path (avoids building full DAG). |
| `FunctionLoweringInfo.cpp` | Tracks per-function lowering state. |
| `InstrEmitter.cpp/h` | Emits machine instructions from scheduled DAG nodes. |
| `TargetLowering.cpp` / `TargetLoweringBase.cpp` | Base class for target-specific lowering. |
| `StatepointLowering.cpp/h` | GC statepoint lowering in SelectionDAG. |

#### `AsmPrinter/` Subdirectory

| File | Purpose |
|------|---------|
| `AsmPrinter.cpp` | Base class for assembly printing. Emits instructions, constants, and global variables. |
| `AsmPrinterDwarf.cpp` / `DwarfDebug.cpp/h` / `DwarfCompileUnit.cpp/h` / `DwarfUnit.cpp/h` | DWARF debug info emission. |
| `WinCodeViewLineTables.cpp/h` | CodeView/PDB debug info emission (Windows). |
| `WinException.cpp/h` / `DwarfCFIException.cpp` / `ARMException.cpp` / `EHStreamer.cpp/h` | Exception handling table emission. |
| `DwarfAccelTable.cpp/h` / `DwarfStringPool.cpp/h` / `DwarfFile.cpp/h` / `AddressPool.cpp/h` | DWARF support structures. |
| `DebugLocStream.cpp/h` / `DbgValueHistoryCalculator.cpp/h` | Debug location tracking. |
| `ByteStreamer.h` | Helper for emitting bytes to output. |

#### `MIRParser/` Subdirectory

| File | Purpose |
|------|---------|
| `MIRParser.cpp` | Parses Machine IR (`.mir` files). |
| `MILexer.cpp/h` / `MIParser.cpp/h` | Lexer and parser for machine IR text format. |

### Main Classes and Responsibilities

- **`MachineFunction`** — Machine-level function representation. Owns `MachineBasicBlock`s, frame info, and register info.
- **`MachineInstr`** — A single machine instruction composed of `MachineOperand`s.
- **`MachineBasicBlock`** — Sequence of `MachineInstr`s.
- **`MachineRegisterInfo`** — Tracks register definitions/uses and allocation state.
- **`SelectionDAG`** / **`SDNode`** — DAG representation used for instruction selection.
- **`SelectionDAGISel`** — Pass that drives DAG-based instruction selection.
- **`FastISel`** — Fast path for simple instruction selection.
- **`TargetLowering`** — Target hooks for DAG legalization and lowering.
- **`LiveInterval`** / **`LiveRange`** — Represents liveness of a virtual register.
- **`RegAllocBase`** / **`RAGreedy`** — Register allocation framework and greedy implementation.
- **`AsmPrinter`** — Base class for emitting assembly or object code.
- **`TargetFrameLowering`** — Target-specific stack frame layout.
- **`TargetInstrInfo`** — Target instruction descriptions and patterns.

---

## Directory: `lib/Analysis`

**Purpose:** Program analyses that compute properties of IR used by optimizations and code generation.

### Structure
- **Top-level:** ~75 source/header files
- **Subdirectory:** `IPA/` — Interprocedural Analysis

### Key Files and Their Purposes

#### Top-Level Analysis

| File | Purpose |
|------|---------|
| `Analysis.cpp` | Initializes all Analysis passes in the pass registry. |
| `AliasAnalysis.cpp` | Generic alias analysis interface and default "NoAA" implementation. |
| `BasicAliasAnalysis.cpp` | BasicAliasAnalysis (BAA) — simple but fast alias analysis using type and object identification. |
| `CFLAliasAnalysis.cpp` | CFL-based (context-free language) alias analysis. |
| `TypeBasedAliasAnalysis.cpp` | TBAA — uses type metadata to disambiguate memory accesses. |
| `ScalarEvolutionAliasAnalysis.cpp` | Alias analysis based on scalar evolution. |
| `LoopInfo.cpp` | Implements `LoopInfo` and `Loop` — identifies natural loops and loop nesting. |
| `Dominators.cpp` / `PostDominators.cpp` | Dominator and post-dominator tree construction. |
| `DominanceFrontier.cpp` | Dominance frontier calculation. |
| `ScalarEvolution.cpp` | Scalar Evolution (SCEV) — represents loop induction variables as closed-form expressions. |
| `ValueTracking.cpp` | Computes known bits, sign bits, overflow flags, and other value properties by walking use-def chains. |
| `MemoryDependenceAnalysis.cpp` | Determines memory dependencies between instructions (local and non-local). |
| `DependenceAnalysis.cpp` | Array dependence analysis for loop transformations (Goff-Kennedy-Tseng approach). |
| `AliasSetTracker.cpp` | Tracks alias sets for memory objects. |
| `AssumptionCache.cpp` | Caches `llvm.assume` intrinsics for quick lookup. |
| `BlockFrequencyInfo.cpp` / `BranchProbabilityInfo.cpp` | Profile-guided block frequency and branch probability analysis. |
| `CostModel.cpp` / `TargetTransformInfo.cpp` | Cost models for target-specific instruction costs. |
| `CaptureTracking.cpp` | Determines whether a pointer value is captured. |
| `ConstantFolding.cpp` | Folds constant expressions at the IR level. |
| `InstructionSimplify.cpp` | Simplifies instructions using algebraic identities. |
| `LazyValueInfo.cpp` | Lazy value range analysis. |
| `Loads.cpp` / `Loads.h` | Helpers for analyzing load instructions. |
| `IVUsers.cpp` | Tracks users of induction variables. |
| `LoopAccessAnalysis.cpp` | Analyzes memory accesses in loops for vectorization. |
| `DivergenceAnalysis.cpp` | Identifies divergent values (relevant for GPU/SIMD targets). |
| `TargetLibraryInfo.cpp` | Information about standard library functions for optimization. |
| `CodeMetrics.cpp` | Computes function complexity metrics for inlining decisions. |
| `Lint.cpp` | Static checker for undefined behavior and suspicious constructs. |
| `InstCount.cpp` | Counts instructions for statistics. |
| `VectorUtils.cpp` / `VectorUtils2.cpp` | Utilities for vector code analysis. |

#### DXC-Specific Analysis Files

| File | Purpose |
|------|---------|
| `DxilConstantFolding.cpp` / `DxilConstantFoldingExt.cpp` | Constant folding for DXIL intrinsics (e.g., `dx.op`). Understands DXIL opcode encoding and convergent markers. |
| `DxilSimplify.cpp` | Simplifies DXIL operations (e.g., `mad 0, a, b -> b`). Uses `DxilModule` and `DxilOperations` to lookup opcode classes. |
| `DxilValueCache.cpp` | Caches constant values for instructions in DXIL. Supports unreachable block marking and conditional branch evaluation. |

#### `IPA/` Subdirectory

| File | Purpose |
|------|---------|
| `CallGraph.cpp` | Builds and maintains the call graph of a module. |
| `CallGraphSCCPass.cpp` | Base class for passes that operate on strongly connected components of the call graph. |
| `GlobalsModRef.cpp` | Interprocedural mod/ref analysis for global variables. |
| `InlineCost.cpp` | Computes inlining cost/heuristics. |
| `IPA.cpp` | Initialization of IPA passes. |

### Main Classes and Responsibilities

- **`AliasAnalysis`** — Base class for all alias analyses. Provides `alias()`, `getModRefInfo()` interfaces.
- **`LoopInfo` / `Loop`** — Identifies loops, loop headers, latches, and nesting depth.
- **`DominatorTree`** — Fast dominance queries and edge analysis.
- **`ScalarEvolution` / `SCEV`** — Represents and simplifies loop recurrence expressions.
- **`MemoryDependenceAnalysis`** — Maps memory instructions to their dependencies.
- **`DependenceAnalysis`** — Determines data dependencies between memory accesses in loops.
- **`ValueTracking`** — Computes known bits, isNonNull, isAligned, overflow info, etc.
- **`LazyValueInfo`** — Lazy range analysis for values.
- **`BlockFrequencyInfo`** — Profile-weighted block execution frequencies.
- **`AssumptionCache`** — Fast lookup for `llvm.assume` calls.
- **`CallGraph`** — Module-wide call graph.
- **`DxilValueCache`** — DXC-specific: caches evaluated constants for DXIL shader values.

---

## Directory: `lib/Transforms`

**Purpose:** Optimization and transformation passes that modify IR to improve performance or prepare for code generation.

### Structure
- **Top-level subdirectories:**
  - `Hello/` — Example pass skeleton
  - `InstCombine/` — Instruction combining
  - `Instrumentation/` — Sanitizers and profiling
  - `IPO/` — Interprocedural optimizations
  - `ObjCARC/` — Objective-C Automatic Reference Counting
  - `Scalar/` — Scalar optimizations
  - `Utils/` — Transformation utilities
  - `Vectorize/` — Vectorization passes

### Key Files and Their Purposes

#### `Scalar/` — Scalar Optimizations

| File | Purpose |
|------|---------|
| `SROA.cpp` | Scalar Replacement of Aggregates — promotes alloca elements to SSA registers. HLSL Change: excludes resource types and matrix types. |
| `GVN.cpp` | Global Value Numbering — eliminates redundant instructions and dead loads. |
| `LICM.cpp` | Loop Invariant Code Motion — hoists/sinks instructions out of loops. |
| `EarlyCSE.cpp` | Early Common Subexpression Elimination. |
| `MemCpyOptimizer.cpp` | Optimizes `memcpy`, `memmove`, `memset` calls. |
| `SCCP.cpp` | Sparse Conditional Constant Propagation. |
| `IndVarSimplify.cpp` | Simplifies induction variables using SCEV. |
| `LoopStrengthReduce.cpp` | Reduces strength of induction variable expressions. |
| `LoopUnrollPass.cpp` | Standard LLVM loop unrolling. |
| `LoopRotation.cpp` / `LoopDeletion.cpp` / `LoopIdiomRecognize.cpp` / `LoopDistribute.cpp` | Loop canonicalization and idiom recognition. |
| `Reassociate.cpp` | Reassociates expressions for better CSE. |
| `ConstantProp.cpp` / `ConstantHoisting.cpp` | Constant propagation and hoisting. |
| `DeadStoreElimination.cpp` | Removes dead stores. |
| `ADCE.cpp` | Aggressive Dead Code Elimination. |
| `DCE.cpp` | Simple Dead Code Elimination. |
| `BDCE.cpp` | Bit-tracking DCE. |
| `SimplifyCFGPass.cpp` / `FlattenCFGPass.cpp` | CFG simplification and flattening. |
| `JumpThreading.cpp` | Threads jumps through blocks. |
| `TailRecursionElimination.cpp` | Converts tail recursion to loops. |
| `PartiallyInlineLibCalls.cpp` | Inlines small library calls. |
| `Reg2Mem.cpp` / `Reg2MemHLSL.cpp` | Converts SSA registers to memory (reverse of mem2reg). |
| `Scalar.cpp` | Initializes scalar transformation passes. |
| `ScalarReplAggregates.cpp` / `ScalarReplAggregatesHLSL.cpp` | Scalar replacement of aggregates (legacy and HLSL-specific). |
| `DxilLoopUnroll.cpp` | DXC-specific loop unroll for mandatory constant values and loops with exits. Includes special handling for HLSL `[unroll]` attribute. |
| `DxilEraseDeadRegion.cpp` | Heuristically removes dead CFG regions in DXIL. |
| `DxilEliminateVector.cpp` | Removes vector instructions (InsertElement/ExtractElement) from DXIL, especially when optimizations are disabled. |
| `DxilFixConstArrayInitializer.cpp` | Fixes constant array initializers in DXIL by folding early stores into initializers. |
| `DxilConditionalMem2Reg.cpp` | Conditional mem2reg for DXIL. |
| `DxilRemoveDeadBlocks.cpp` | Removes dead basic blocks in DXIL. |
| `DxilRemoveUnstructuredLoopExits.cpp` | Removes unstructured loop exits to make DXIL more amenable to analysis. |
| `StructurizeCFG.cpp` | Converts irreducible/unstructured CFG to structured form (important for GPU shaders). |
| `HoistConstantArray.cpp` | Hoists constant array data. |
| `SampleProfile.cpp` | Sample-based profile-guided optimization. |

#### `InstCombine/` — Instruction Combining

| File | Purpose |
|------|---------|
| `InstructionCombining.cpp` | Main InstCombine pass driver. Worklist-driven algebraic simplification. |
| `InstCombineAddSub.cpp` | Combine add/subtract instructions. |
| `InstCombineAndOrXor.cpp` | Combine bitwise AND/OR/XOR. |
| `InstCombineCalls.cpp` | Combine call instructions. |
| `InstCombineCasts.cpp` | Combine cast instructions. |
| `InstCombineCompares.cpp` | Combine compare instructions. |
| `InstCombineLoadStoreAlloca.cpp` | Combine load/store/alloca. |
| `InstCombineMulDivRem.cpp` | Combine multiply/divide/remainder. |
| `InstCombinePHI.cpp` | Combine PHI nodes. |
| `InstCombineSelect.cpp` | Combine select instructions. |
| `InstCombineShifts.cpp` | Combine shift instructions. |
| `InstCombineSimplifyDemanded.cpp` | Simplify based on demanded bits. |
| `InstCombineVectorOps.cpp` | Combine vector operations. |
| `InstCombineInternal.h` | Internal helpers and state for InstCombine. |

#### `IPO/` — Interprocedural Optimizations

| File | Purpose |
|------|---------|
| `Inliner.cpp` | Main inliner logic — updates call graph, handles diagnostics. |
| `InlineSimple.cpp` / `InlineAlways.cpp` | Simple and always-inline policies. |
| `GlobalOpt.cpp` | Global variable optimization. |
| `GlobalDCE.cpp` | Dead global elimination. |
| `ConstantMerge.cpp` | Merges identical constants. |
| `FunctionAttrs.cpp` | Deduces function attributes (readnone, readonly, etc.). |
| `ArgumentPromotion.cpp` | Promotes by-reference arguments to by-value. |
| `DeadArgumentElimination.cpp` | Removes unused function arguments. |
| `MergeFunctions.cpp` | Merges identical functions. |
| `PassManagerBuilder.cpp` | Constructs standard optimization pipelines. HLSL Change: includes DXIL generation passes (`DxilGenerationPass`, `HLMatrixLowerPass`, `ComputeViewIdState`). |
| `Internalize.cpp` | Makes global symbols internal for LTO. |
| `StripSymbols.cpp` / `StripDeadPrototypes.cpp` | Strips symbols and unused prototypes. |
| `PruneEH.cpp` | Prunes exception handling information. |
| `IPO.cpp` | Initializes IPO passes. |

#### `Utils/` — Transformation Utilities

| File | Purpose |
|------|---------|
| `Mem2Reg.cpp` | `-mem2reg` pass wrapper around `PromoteMemToReg`. |
| `PromoteMemoryToRegister.cpp` | Core mem2reg algorithm using iterated dominance frontiers and PHI insertion. |
| `Local.cpp` | Local analysis utilities (simplify instructions in a basic block). |
| `SimplifyInstructions.cpp` | Instruction simplification utilities. |
| `SimplifyCFG.cpp` | CFG simplification utilities. |
| `CloneFunction.cpp` / `CloneModule.cpp` | Function and module cloning. |
| `InlineFunction.cpp` | Inlines a call site into its caller. |
| `LoopUtils.cpp` / `LoopSimplify.cpp` / `LCSSA.cpp` | Loop canonicalization and LCSSA formation. |
| `LoopUnroll.cpp` / `LoopUnrollRuntime.cpp` | Loop unrolling utilities. |
| `BreakCriticalEdges.cpp` | Breaks critical edges in the CFG. |
| `DemoteRegToStack.cpp` | Demotes SSA values to stack slots. |
| `SSAUpdater.cpp` | Updates SSA form after transformations. |
| `ValueMapper.cpp` | Maps values during cloning/remapping. |
| `BasicBlockUtils.cpp` | Basic block manipulation utilities. |
| `CodeExtractor.cpp` | Extracts a region into a new function. |
| `ModuleUtils.cpp` | Module-level utilities. |
| `GlobalStatus.cpp` | Analyzes global variable usage. |
| `Utils.cpp` | Initializes utility passes. |

#### `Vectorize/` — Vectorization

| File | Purpose |
|------|---------|
| `LoopVectorize.cpp` | Loop vectorization pass. |
| `SLPVectorizer.cpp` | SLP (Superword Level Parallelism) vectorization. |
| `BBVectorize.cpp` | Basic block vectorization. |
| `Vectorize.cpp` | Initializes vectorization passes. |

#### `Instrumentation/` — Instrumentation and Sanitizers

| File | Purpose |
|------|---------|
| `AddressSanitizer.cpp` | AddressSanitizer instrumentation. |
| `MemorySanitizer.cpp` | MemorySanitizer instrumentation. |
| `ThreadSanitizer.cpp` | ThreadSanitizer instrumentation. |
| `DataFlowSanitizer.cpp` | DataFlowSanitizer instrumentation. |
| `BoundsChecking.cpp` | Array bounds checking instrumentation. |
| `SafeStack.cpp` | SafeStack instrumentation. |
| `GCOVProfiling.cpp` / `InstrProfiling.cpp` | Profile-guided optimization instrumentation. |
| `SanitizerCoverage.cpp` | Coverage instrumentation for fuzzers. |

#### `ObjCARC/` — Objective-C ARC

| File | Purpose |
|------|---------|
| `ObjCARCOpts.cpp` / `ObjCARCContract.cpp` / `ObjCARCExpand.cpp` / `ObjCARCAPElim.cpp` | Objective-C ARC optimizations. |
| `ObjCARCAliasAnalysis.cpp` | Alias analysis for ARC. |
| `DependencyAnalysis.cpp` / `ProvenanceAnalysis.cpp` | ARC dependency and provenance analysis. |

#### `Hello/` — Example Pass

| File | Purpose |
|------|---------|
| `Hello.cpp` | Skeleton example pass demonstrating pass structure. |

### Main Classes and Responsibilities

- **`SROA`** — Promotes aggregate allocas to scalar SSA values.
- **`GVN`** — Global value numbering; eliminates redundant computation.
- **`LICM`** — Hoists invariant code out of loops.
- **`InstCombiner`** — Worklist-driven peephole optimizer combining instructions.
- **`Inliner`** — Decides which calls to inline and performs the inlining.
- **`LoopUnroll`** / **`DxilLoopUnroll`** — Unrolls loops; DXC version handles HLSL `[unroll]` semantics.
- **`SimplifyCFG`** — Canonicalizes and simplifies control flow.
- **`Mem2Reg` / `PromoteMemToReg`** — Converts stack-allocated locals to SSA registers.
- **`ScalarEvolution`** — Analysis used by loop transforms for induction variable analysis.
- **`LoopVectorize`** / **`SLPVectorizer`** — Automatically vectorizes scalar code.
- **`DxilEliminateVector`** — DXC-specific pass to scalarize vectors for DXIL compatibility.
- **`DxilEraseDeadRegion`** — DXC-specific dead code elimination using dominance/post-dominance.

---

## Directory: `lib/Passes`

**Purpose:** Pass pipeline construction and the new pass manager infrastructure.

### Structure
- Flat directory with 4 files

### Key Files and Their Purposes

| File | Purpose |
|------|---------|
| `PassBuilder.cpp` | Implements `PassBuilder` — constructs pass pipelines from string descriptions and static registries. Defines no-op passes for testing. Provides the core infrastructure for the new pass manager. |
| `PassRegistry.def` | Static registry of passes (macros defining pass IDs). |

### Main Classes and Responsibilities

- **`PassBuilder`** — Parses pass pipeline strings (e.g., `"module(function(instcombine))"`) and builds corresponding pass managers.
- **`NoOpModulePass` / `NoOpFunctionPass`** — No-op passes used for testing the pass manager.

---

## Component Interactions

```
+---------------------------------------------------------------+
|                         FRONTEND                              |
|         (Clang/HLSL Parser → LLVM IR Builder)                 |
+---------------------------------------------------------------+
                              |
                              v
+---------------------------------------------------------------+
|                      lib/IR (IR Layer)                        |
|  Module → Function → BasicBlock → Instruction → Value/Type    |
|  LLVMContext owns global state. Verifier checks well-formedness.|
+---------------------------------------------------------------+
                              |
              +---------------+---------------+
              |                               |
              v                               v
+----------------------------+   +----------------------------+
|    lib/Analysis            |   |    lib/Transforms          |
|  - AliasAnalysis           |   |  - InstCombine             |
|  - DominatorTree           |   |  - GVN, LICM, SROA         |
|  - LoopInfo                |   |  - Inliner                 |
|  - ScalarEvolution         |   |  - LoopUnroll              |
|  - MemoryDependence        |   |  - Mem2Reg                 |
|  - DxilValueCache (DXC)    |   |  - Dxil* passes (DXC)      |
|  Provides analysis results  |   |  Consumes & invalidates    |
|  used by transforms & CG   |   |  analysis results          |
+----------------------------+   +----------------------------+
              |                               |
              +---------------+---------------+
                              |
                              v
+---------------------------------------------------------------+
|              lib/Passes (Pass Pipeline Orchestration)         |
|  LegacyPassManager / PassBuilder schedules analyses & transforms|
+---------------------------------------------------------------+
                              |
                              v
+---------------------------------------------------------------+
|                    lib/CodeGen (Code Generation)              |
|  1. CodeGenPrepare (IR cleanup)                               |
|  2. SelectionDAGBuilder → SelectionDAGISel (instr selection)  |
|  3. ScheduleDAG* (instruction scheduling)                     |
|  4. Register Allocation (Greedy/Fast)                         |
|  5. AsmPrinter (assembly/object emission)                     |
|  6. Machine-level passes (peephole, branch folding, etc.)     |
+---------------------------------------------------------------+
                              |
                              v
+---------------------------------------------------------------+
|                     TARGET BACKEND                            |
|              (e.g., DXIL Backend, x86 Backend)                |
+---------------------------------------------------------------+
```

### Interaction Details

1. **IR ↔ Analysis**: Analysis passes (e.g., `AliasAnalysis`, `DominatorTree`) run on IR and cache results. Transforms declare dependencies via `getAnalysisUsage()`.

2. **Transforms ↔ IR**: Transforms modify IR in place. The legacy pass manager invalidates analyses as needed. DXC-specific transforms (`DxilLoopUnroll`, `DxilEliminateVector`) integrate with `DxilModule` metadata.

3. **IR ↔ CodeGen**: CodeGen consumes verified IR. `LLVMTargetMachine` sets up the CodeGen pass pipeline (instruction selection, scheduling, register allocation, assembly emission).

4. **CodeGen Internal Flow**:
   - `SelectionDAGBuilder` converts IR to `SelectionDAG`.
   - `DAGCombiner` simplifies the DAG.
   - `Legalize*` phases ensure all operations are supported by the target.
   - `InstrEmitter` converts scheduled DAG to `MachineInstr`.
   - Register allocators (`RAGreedy`) map virtual to physical registers.
   - `AsmPrinter` emits final assembly or object code.

5. **Pass Management**: `LegacyPassManager` (in `lib/IR`) and `PassBuilder` (in `lib/Passes`) coordinate when analyses and transforms run. IPO passes like the inliner use `CallGraph` from `lib/Analysis/IPA`.

6. **DXC-Specific Integration**:
   - `DxilValueCache` (Analysis) caches evaluated constants for shader values.
   - `DxilConstantFolding` and `DxilSimplify` understand DXIL opcodes (`dx.op.*`).
   - `PassManagerBuilder` includes HLSL-specific passes (`DxilGenerationPass`, `HLMatrixLowerPass`).
   - `Module` has DXC-specific methods (`HasDxilModule()`, `GetDxilModule()`).

---

## Summary

| Library | File Count | Core Responsibility |
|---------|-----------|---------------------|
| `lib/IR` | ~57 | In-memory representation of programs; values, types, instructions, modules; pass infrastructure base; IR verification and printing. |
| `lib/CodeGen` | ~180+ | Lowering IR to machine code: SelectionDAG instruction selection, scheduling, register allocation, prologue/epilogue, assembly emission, debug info. |
| `lib/Analysis` | ~80+ | Computing program properties: alias analysis, dominators, loops, scalar evolution, memory dependence, cost models, and DXC-specific value caches. |
| `lib/Transforms` | ~200+ | Optimizing and canonicalizing IR: instruction combining, GVN, LICM, inlining, SROA, mem2reg, loop transforms, vectorization, and DXC-specific DXIL cleanup passes. |
| `lib/Passes` | 4 | Pass pipeline construction and the new pass manager infrastructure. |

### Key Architectural Observations

1. **Standard LLVM Architecture**: DXC retains the classic LLVM three-phase architecture (frontend → optimizer → backend), with IR as the universal intermediate language.

2. **DXC Customizations**: The codebase contains numerous "HLSL Change" comments and DXC-specific files (`Dxil*.cpp`) that adapt LLVM for shader compilation:
   - Vector elimination for DXIL scalarization
   - Special loop unroll handling for `[unroll]` and mandatory constant folding
   - DXIL intrinsic constant folding and simplification
   - Integration with `DxilModule` and `HLModule` metadata

3. **Pass-Centric Design**: Nearly all optimization and code generation is organized as passes that operate on IR or machine code. The pass manager orchestrates execution order and analysis caching.

4. **SSA Form**: LLVM IR is in strict SSA form. `Mem2Reg` / `SROA` promote stack memory to SSA, while `Reg2Mem` can reverse this when needed.

5. **SelectionDAG CodeGen**: The backend uses the SelectionDAG approach for instruction selection, which is mature but has been partially superseded by GlobalISel in newer LLVM versions. DXC uses the classic SelectionDAG path.

6. **Register Allocation**: The default optimized allocator is the greedy allocator (`RegAllocGreedy.cpp`), with fast (`RegAllocFast.cpp`) and basic (`RegAllocBasic.cpp`) alternatives for different optimization levels.

---

*Report generated from analysis of `D:/DirectXShaderCompiler/lib/{IR,CodeGen,Analysis,Transforms,Passes}`.*
