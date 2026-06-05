# HLSL/DXIL Core Analysis

This report analyzes the three core libraries in the DirectX Shader Compiler (DXC) project responsible for HLSL compilation, DXIL generation, and compiler support infrastructure.

**Analyzed Directories:**
- `lib/HLSL` — HLSL frontend lowering and DXIL generation passes
- `lib/DXIL` — DXIL intermediate representation and metadata model
- `lib/DxcSupport` — Compiler support utilities, options, and I/O

---

## Directory: lib/DXIL — The DXIL Data Model and Metadata Core

**Overview:**
`lib/DXIL` implements the core data model for DXIL (DirectX Intermediate Language), which is Microsoft's LLVM-based IR for shader compilation. This library defines how shader programs are represented, how resources are tracked, and how metadata is serialized to/deserialized from LLVM IR. It has **26 source files** and **no subdirectories**.

**Key Classes and Responsibilities:**

| Class/File | Responsibility |
|---|---|
| `DxilModule` (DxilModule.h/cpp) | The central class representing a DXIL module. Wraps an `llvm::Module` and manages shader model, entry functions, resources (SRVs/UAVs/CBuffers/Samplers), signatures, type annotations, subobjects, and validator version. |
| `OP` (DxilOperations.h/cpp) | **DXIL Operation Manager**. Maintains opcode tables for all DXIL operations (e.g., `Sample`, `LoadInput`, `Barrier`, `WaveIsFirstLane`). Handles operation overloading, type slots, and caches DXIL intrinsic functions per-module. |
| `DxilMDHelper` (DxilMetadataHelper.h/cpp) | **Metadata Serialization Engine**. Converts in-memory DXIL structures (resources, signatures, type annotations) to LLVM named metadata nodes (e.g., `dx.version`, `dx.shaderModel`, `dx.resources`, `dx.entryPoints`) and back. |
| `DxilResource` / `HLResource` (DxilResource.h/cpp) | Represents SRV and UAV resources with properties like component type, sample count, stride, globally coherent flag, ROV, and counters. |
| `DxilCBuffer` (DxilCBuffer.h/cpp) | Represents constant buffer resources with size and layout information. |
| `DxilSampler` (DxilSampler.h/cpp) | Represents sampler resources with sampler kind (comparison, linear, etc.). |
| `DxilSignature` / `DxilSignatureElement` (DxilSignature.h/cpp, DxilSignatureElement.h/cpp) | Manages input/output/patch-constant signature elements with semantic names, interpolation modes, packing info, and system-value semantics. |
| `DxilTypeSystem` (DxilTypeSystem.h/cpp) | Manages type annotations for structs and functions, including matrix annotations, field layouts, and parameter annotations. |
| `DxilShaderModel` (DxilShaderModel.h/cpp) | Encapsulates shader model versions (e.g., `6_0`, `6_5`, `lib_6_3`) and capabilities. |
| `DxilShaderFlags` (DxilShaderFlags.h/cpp) | Computes and stores shader capability flags (e.g., uses double precision, raytracing, UAVs at every stage). |
| `DxilSubobject` (DxilSubobject.h/cpp) | Represents DXIL subobjects for raytracing pipelines (state objects, hit groups, etc.). |
| `DxilUtil` (DxilUtil.h/cpp, DxilUtilDbgInfoAndMisc.cpp) | Helper utilities: name demangling, static global detection, shared memory detection, diagnostic printing, legacy cbuffer field size calculation. |
| `DxilInstructions.h` | Auto-generated or hand-written instruction wrappers for typed access to DXIL operation arguments. |

**Key Design Patterns:**
- **Metadata Bridge**: `DxilModule` maintains both in-memory C++ objects and LLVM metadata representations. `EmitDxilMetadata()` serializes to LLVM; `LoadDxilMetadata()` deserializes from LLVM.
- **Resource Ownership**: Resources are stored as `std::vector<std::unique_ptr<T>>` inside `DxilModule`, with IDs assigned by insertion order.
- **Operation Caching**: `OP` caches `llvm::Function*` objects per opcode and overload type to avoid redundant function creation.

---

## Directory: lib/HLSL — HLSL Lowering and DXIL Generation Passes

**Overview:**
`lib/HLSL` contains the **compilation pipeline** that transforms high-level HLSL IR into final DXIL. It includes the high-level module representation (`HLModule`), LLVM passes for lowering constructs (matrices, signatures, operations), the DXIL generation pass, and various legalization/optimization passes. It has **57 source files** and **no subdirectories**.

**Key Classes and Responsibilities:**

| Class/File | Responsibility |
|---|---|
| `HLModule` (HLModule.h/cpp) | **High-Level IR Module**. Predecessor to `DxilModule`. Represents the shader during frontend/codegen before DXIL generation. Tracks HL-specific resources, options (`HLOptions`), thread-group shared memory, function properties, and metadata. |
| `HLOptions` (HLModule.h) | Bit-packed struct of high-level compile options: row-major default, IEEE strict, all resources bound, disable optimizations, min precision, DX9 compat, legacy resource reservation. |
| `DxilGenerationPass` (DxilGenerationPass.h/cpp) | **The DXIL Generator**. Transforms `HLModule` into `DxilModule` by copying resources, signatures, shader properties, type system, and OP ownership. This is the bridge from high-level IR to DXIL. |
| `HLSignatureLower` (HLSignatureLower.h/cpp) | Lowers entry function input/output parameters to DXIL `LoadInput` and `StoreOutput` intrinsic calls based on semantic names and signature elements. Handles system-value semantics (e.g., `SV_Position`, `SV_DispatchThreadID`). |
| `HLMatrixLowerPass` (HLMatrixLowerPass.h/cpp, HLMatrixType.cpp, HLMatrixBitcastLowerPass.cpp) | **Matrix Lowering**. Converts HLSL matrix types to LLVM vectors. Handles global variables, allocas, operations, load/store, subscripting, and intrinsic calls (transpose, determinant). |
| `HLOperationLower` (HLOperationLower.h/cpp, HLOperationLowerExtension.cpp) | **HL Operation Lowering**. Translates high-level HL intrinsic operations (texture sampling, buffer operations, math intrinsics) into DXIL `OP` calls. Contains `HLObjectOperationLowerHelper` for resource handle lowering. |
| `HLOperations` (HLOperations.h/cpp) | Defines **HL Opcode Groups**: `HLIntrinsic`, `HLCast`, `HLInit`, `HLBinOp`, `HLUnOp`, `HLSubscript`, `HLMatLoadStore`, `HLSelect`, `HLCreateHandle`, `HLAnnotateHandle`, and node handle variants. Provides name mangling and group lookup. |
| `DxcOptimizer` (DxcOptimizer.cpp) | Implements `IDxcOptimizer` COM interface. Enumerates available LLVM passes and runs them on a DXIL blob. Integrates with the legacy LLVM pass manager. |
| `ComputeViewIdState` / `ComputeViewIdStateBuilder` (ComputeViewIdState.cpp, ComputeViewIdStateBuilder.cpp) | Computes which output signatures depend on which input signatures (ViewID state), used for pipeline validation and reflection. |
| `WaveSensitivityAnalysis` (WaveSensitivityAnalysis.cpp) | Analyzes whether instructions are sensitive to wave operations for validation. |
| `ControlDependence` (ControlDependence.cpp) | Computes control dependence for optimizations and validation. |
| `DxilLinker` (DxilLinker.cpp) | Links multiple DXIL modules/libraries together, resolving exports and merging resources. |
| `DxilPreparePasses` / `DxilFinalizeModulePass` (DxilPreparePasses.cpp) | Prepares the module for DXIL emission and finalizes it (e.g., collecting shader flags, upgrading validator version). |
| `DxilPromoteResourcePasses` (DxilPromoteResourcePasses.cpp) | Promotes local/static resources to global resources where legal. |
| `DxilLegalizeEvalOperations` (DxilLegalizeEvalOperations.cpp) | Legalizes `evalCentroid`, `evalSnapped`, `evalSampleIndex` operations. |
| `DxilEliminateOutputDynamicIndexing` (DxilEliminateOutputDynamicIndexing.cpp) | Eliminates dynamic indexing on shader outputs to satisfy DXIL constraints. |
| `DxilScalarizeVectorIntrinsics` (DxilScalarizeVectorIntrinsics.cpp) | Scalarizes vector intrinsics that must be scalar in DXIL. |
| `DxilTranslateRawBuffer` (DxilTranslateRawBuffer.cpp) | Translates raw/structured buffer operations to DXIL equivalents. |
| `HLDeadFunctionElimination` / `DxilDeadFunctionElimination` (HLDeadFunctionElimination.cpp) | Removes unused functions before/after DXIL generation. |
| `HLResource` (HLResource.cpp) | High-level resource representation used by `HLModule`. |
| `HLPreprocess` (HLPreprocess.cpp) | Preprocessing pass for HL IR. |
| `HLExpandStoreIntrinsics` (HLExpandStoreIntrinsics.cpp) | Expands store intrinsics for complex types. |
| `HLLegalizeParameter` (HLLegalizeParameter.cpp) | Legalizes function parameters for DXIL constraints. |
| `HLLowerUDT` (HLLowerUDT.cpp) | Lowers user-defined types. |
| `DxilCondenseResources` (DxilCondenseResources.cpp) | Condenses resource bindings to minimize gaps. |
| `DxilContainerReflection` (DxilContainerReflection.cpp) | Reflection support for DXIL containers. |
| `DxilTargetLowering` / `DxilTargetTransformInfo` (DxilTargetLowering.cpp, DxilTargetTransformInfo.h/cpp) | LLVM target lowering hooks for DXIL target. |
| `PauseResumePasses` (PauseResumePasses.cpp) | Supports pass manager pause/resume for debugging. |

**Key Design Patterns:**
- **Pass Pipeline**: The HLSL library is organized as a sequence of LLVM passes. `DxilGenerationPass` is the central transformation; other passes legalize and optimize before/after it.
- **Two-Module Model**: `HLModule` exists during frontend/codegen; `DxilModule` exists after DXIL generation. `InitDxilModuleFromHLModule()` copies data between them.
- **Opcode Groups**: HLSL operations are categorized into groups (`HLOpcodeGroup`) to allow generic lowering logic.

---

## Directory: lib/DxcSupport — Compiler Support Infrastructure

**Overview:**
`lib/DxcSupport` provides foundational utilities used across the compiler: command-line option parsing, file I/O, Unicode handling, Windows compatibility shims, and DXC API consumer helpers. It has **13 source files** and **no subdirectories**.

**Key Classes and Responsibilities:**

| Class/File | Responsibility |
|---|---|
| `HLSLOptions` (HLSLOptions.h/cpp, HLSLOptions.td) | **Command-Line Option Parsing**. Defines all HLSL compiler options (`DxcOpts`): optimization level, debug info, target profile, entry point, warning flags, strip/reflection options, SPIR-V options, etc. Uses LLVM's `OptTable` infrastructure. |
| `DxcOpts` (HLSLOptions.h) | Central options struct with ~80+ fields covering every compiler flag. Provides helper methods like `ProduceDxModule()`, `NeedsValidation()`, `IsLibraryProfile()`. |
| `MainArgs` (HLSLOptions.h/cpp) | Converts `wchar_t**` or `char**` command-line arguments to UTF-8 `llvm::ArrayRef<const char*>` for LLVM option parsing. |
| `DxcDefines` (HLSLOptions.h/cpp) | Manages preprocessor definitions, converting UTF-8 strings to `DxcDefine` structures with proper wchar_t allocation. |
| `dxcapi.use` (dxcapi.use.h/cpp) | **DXC API Consumer Helpers**. Utilities for loading `dxcompiler.dll`/`dxil.dll`, reading files into blobs, writing blobs to files/console, and handling `IDxcOperationResult` errors. |
| `FileIOHelper` (FileIOHelper.h/cpp) | **Binary File I/O**. `ReadBinaryFile()`, `WriteBinaryFile()`, code page detection (`DxcCodePageFromBytes`), BOM handling, and blob serialization helpers. |
| `Unicode` (Unicode.h/cpp) | **Unicode Conversion**. Wide/UTF-8/UTF-16 conversions, console string encoding, and charset detection. |
| `WinAdapter` / `WinFunctions` / `WinIncludes` (WinAdapter.cpp, WinFunctions.cpp, WinIncludes.cpp) | **Windows Compatibility Layer**. Provides Windows API types and functions (`HRESULT`, `CoTaskMemAlloc`, `FormatMessage`, `CreateFileW`) on non-Windows platforms (e.g., Linux/macOS). |
| `Global` (Global.h/cpp) | Global macros (`DXASSERT`, `DXASSERT_NOMSG`), exception types (`hlsl::Exception`), and shared constants. |
| `dxcmem` (dxcmem.cpp) | Memory allocation utilities for the compiler. |
| `dxcapi.extval` (dxcapi.extval.h/cpp) | Extended validation helpers for the DXC API. |
| `SharedLibAffix.inc` | Platform-specific shared library prefix/suffix definitions. |

**Key Design Patterns:**
- **Cross-Platform Abstraction**: `WinAdapter` allows the rest of the codebase to use Windows-style APIs even on Linux builds.
- **Blob-Centric I/O**: File operations return `IDxcBlob*` / `IDxcBlobEncoding*` rather than raw buffers, integrating with the COM-based DXC API.

---

## Key Files and Their Purposes

### lib/DXIL

| File | Purpose |
|---|---|
| `DxilModule.h/cpp` | Core DXIL module; manages all shader state |
| `DxilOperations.h/cpp` | DXIL opcode tables, operation properties, and intrinsic function management (`OP` class) |
| `DxilMetadataHelper.h/cpp` | Serialize/deserialize DXIL structures to LLVM metadata |
| `DxilResource.h/cpp` | SRV/UAV resource definitions |
| `DxilCBuffer.h/cpp` | Constant buffer definitions |
| `DxilSampler.h/cpp` | Sampler definitions |
| `DxilSignature.h/cpp` | Input/output/patch-constant signature management |
| `DxilSignatureElement.h/cpp` | Individual signature element properties |
| `DxilTypeSystem.h/cpp` | Type annotations for structs and functions |
| `DxilShaderModel.h/cpp` | Shader model version and capability checking |
| `DxilShaderFlags.h/cpp` | Shader feature flag computation |
| `DxilSubobject.h/cpp` | Raytracing subobject definitions |
| `DxilUtil.h/cpp` | General DXIL utilities |
| `DxilInstructions.h` | Typed instruction wrappers for DXIL operations |
| `DxilConstants.h` | DXIL constants and enumerations |
| `DxilPDB.h/cpp` | PDB generation support |
| `DxilCounters.h/cpp` | Shader counter metadata |

### lib/HLSL

| File | Purpose |
|---|---|
| `HLModule.h/cpp` | High-level IR module before DXIL generation |
| `DxilGenerationPass.h/cpp` | Main pass converting HLModule → DxilModule |
| `HLSignatureLower.h/cpp` | Lower entry signatures to LoadInput/StoreOutput |
| `HLMatrixLowerPass.cpp` | Lower matrix types to vectors |
| `HLMatrixBitcastLowerPass.cpp` | Lower matrix bitcasts |
| `HLMatrixType.cpp` | Matrix type analysis helpers |
| `HLOperationLower.h/cpp` | Lower HL intrinsics to DXIL operations |
| `HLOperationLowerExtension.cpp` | Lower extended/custom intrinsics |
| `HLOperations.h/cpp` | HL opcode group definitions and name mangling |
| `DxcOptimizer.cpp` | `IDxcOptimizer` COM implementation |
| `ComputeViewIdState.cpp` | ViewID dependency analysis |
| `DxilLinker.cpp` | DXIL module linking |
| `DxilPreparePasses.cpp` | Module preparation and finalization passes |
| `DxilPromoteResourcePasses.cpp` | Resource promotion legalizations |
| `DxilEliminateOutputDynamicIndexing.cpp` | Output dynamic indexing removal |
| `DxilScalarizeVectorIntrinsics.cpp` | Vector intrinsic scalarization |
| `HLDeadFunctionElimination.cpp` | Dead function removal |
| `HLPreprocess.cpp` | HL IR preprocessing |
| `HLResource.cpp` | HL resource representation |
| `WaveSensitivityAnalysis.cpp` | Wave operation sensitivity analysis |
| `ControlDependence.cpp` | Control dependence analysis |
| `DxilTargetLowering.cpp` | LLVM target lowering for DXIL |
| `PauseResumePasses.cpp` | Pass manager pause/resume support |

### lib/DxcSupport

| File | Purpose |
|---|---|
| `HLSLOptions.h/cpp` | Command-line option parsing and `DxcOpts` struct |
| `HLSLOptions.td` | TableGen definition of HLSL options |
| `dxcapi.use.h/cpp` | DXC API consumer utilities (DLL loading, blob I/O) |
| `FileIOHelper.h/cpp` | Binary file reading/writing and code page detection |
| `Unicode.h/cpp` | Unicode string conversions |
| `WinAdapter.cpp` | Windows API compatibility for non-Windows builds |
| `WinFunctions.cpp` | Windows function implementations for cross-platform |
| `WinIncludes.cpp` | Windows header compatibility |
| `Global.h/cpp` | Global macros, assertions, exceptions |
| `dxcmem.cpp` | Memory management utilities |
| `dxcapi.extval.h/cpp` | Extended validation helpers |

---

## Component Interactions

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         HLSL Frontend / Clang                            │
│                    (generates HLModule + LLVM IR)                        │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         lib/HLSL : HLModule                              │
│  • HLModule tracks high-level resources, signatures, options             │
│  • HLOperations define HL opcode groups (cast, init, binop, etc.)        │
│  • HLMatrixLowerPass lowers matrices → vectors                           │
│  • HLSignatureLower lowers I/O params → LoadInput/StoreOutput            │
│  • HLOperationLower lowers HL intrinsics → DXIL OP calls                 │
│  • Various legalization passes (promote, eliminate dynamic indexing)     │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
              DxilGenerationPass (HLModule → DxilModule)
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         lib/DXIL : DxilModule                            │
│  • DxilModule owns the canonical DXIL representation                     │
│  • OP manages DXIL opcode tables and intrinsic functions                 │
│  • DxilMetadataHelper serializes to LLVM named metadata                  │
│  • Resources (SRV/UAV/CBuffer/Sampler), Signatures, TypeSystem           │
│  • ShaderModel, ShaderFlags, Subobjects                                  │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    DXIL Container / Validation / Driver                  │
│         (DxilContainerAssembler packs metadata + bitcode)                │
└─────────────────────────────────────────────────────────────────────────┘
        ▲                                                          ▲
        │                                                          │
┌───────┴────────────────────────┐                    ┌──────────┴──────────┐
│    lib/DxcSupport              │                    │   lib/DxcSupport    │
│  • HLSLOptions → DxcOpts       │                    │  • FileIOHelper     │
│  • dxcapi.use (DLL loading)    │                    │  • Unicode          │
│  • WinAdapter (cross-platform) │                    │  • Global utilities │
└────────────────────────────────┘                    └─────────────────────┘
```

**Interaction Details:**

1. **Frontend → HLModule**: The HLSL frontend (Clang-based) generates LLVM IR decorated with HL operations. `HLModule` is attached to the `llvm::Module` to track high-level shader properties.

2. **HLModule → DxilModule**: `DxilGenerationPass` copies all state from `HLModule` to `DxilModule`, including resources, signatures, shader properties, type annotations, and the `OP` instance. After this pass, the IR contains DXIL intrinsics rather than HL intrinsics.

3. **HLSL Passes**: Before and during DXIL generation, various HLSL passes transform the IR:
   - `HLMatrixLowerPass` eliminates matrix types.
   - `HLSignatureLower` replaces entry parameters with DXIL I/O operations.
   - `HLOperationLower` converts HL texture/buffer/math operations to DXIL opcodes.
   - Legalization passes ensure the output conforms to DXIL rules (no dynamic output indexing, promoted resources, etc.).

4. **DxilModule → Metadata**: `DxilModule::EmitDxilMetadata()` uses `DxilMetadataHelper` to write all shader state into LLVM named metadata nodes. This metadata is later read by the validator, driver, and reflection tools.

5. **DxcSupport Integration**: `HLSLOptions` provides the compiler flags that control which passes run and how they behave. `FileIOHelper` and `dxcapi.use` handle reading source files and writing compiled output. `WinAdapter` enables the entire stack to build on Linux.

6. **Optimizer Interface**: `DxcOptimizer` (in `lib/HLSL`) exposes LLVM passes through the `IDxcOptimizer` COM interface, allowing external tools to run specific passes on DXIL blobs.

---

## Summary

The three directories form a pipeline with clear separation of concerns:

- **`lib/DXIL`** is the **kernel** of the compiler. It defines what DXIL *is*: the module structure, the operations, the resources, the metadata format, and the serialization logic. Without this library, there is no DXIL representation.

- **`lib/HLSL`** is the **transformation engine**. It takes high-level HLSL IR and progressively lowers it to valid DXIL through a series of LLVM passes. It bridges the gap between frontend-generated IR and the strict DXIL representation required by drivers and validators.

- **`lib/DxcSupport`** is the **foundation**. It provides the command-line interface, file I/O, cross-platform compatibility, and API utilities that allow the compiler to be used as a tool (`dxc.exe`) and as a library (`dxcompiler.dll`).

Together, these libraries implement the core of the DirectX Shader Compiler: parsing HLSL, lowering it through high-level and low-level IR, and emitting validated DXIL bytecode with rich metadata for GPU execution.
