# DXC Project Structure Overview

> **Target Audience:** New developers joining the DirectX Shader Compiler (DXC) project.  
> **Last Updated:** Auto-generated from comprehensive source analysis.  
> **Repository Root:** `D:\\DirectXShaderCompiler`

The **DirectX Shader Compiler (DXC)** is a fork of **LLVM 3.7 + Clang** heavily modified to compile **High-Level Shading Language (HLSL)** into **DirectX Intermediate Language (DXIL)** — an LLVM-based IR used by DirectX 12 GPU drivers. DXC also supports emitting **SPIR-V** for Vulkan targets.

This document provides a comprehensive, layer-by-layer map of the codebase, explaining what lives where, how data flows through the compiler, and which dependencies and tools you need to understand.

---

## Top-Level Directory Tree

```
DirectXShaderCompiler/
├── cmake/                    # CMake modules, platform toolchains, cache presets
├── docs/                     # Documentation (DXIL spec, SPIR-V mapping, build guides)
├── examples/                 # Educational LLVM API samples (ModuleMaker)
├── external/                 # External dependencies (SPIRV-Tools, DirectX-Headers, etc.)
├── include/
│   ├── dxc/                  # Public DXC APIs and DXIL/HLSL headers
│   ├── llvm/                 # LLVM C++ infrastructure headers
│   ├── llvm-c/               # Stable C API for LLVM
│   └── miniz/                # zlib replacement header
├── lib/                      # Core libraries (see Architecture Layers below)
├── projects/
│   ├── dxilconv/             # DXBC-to-DXIL converter
│   └── include/Tracing/      # Windows ETW tracing manifests
├── resources/
│   └── windows_version_resource.rc
├── test/                     # LLVM core regression tests (mostly disabled for HLSL)
├── tools/                    # Command-line tools (dxc, opt, llvm-dis, llc, etc.)
│   └── clang/                # Clang frontend + DXC-specific compiler tools
├── unittests/                # C++ unit tests (GoogleTest)
└── utils/                    # Build scripts, test runners, code generators
    ├── hct/                  # HLSL Console Tools (hctbuild, hcttest, hctgen)
    ├── lit/                  # LLVM Integrated Tester (LIT)
    └── unittest/googletest/  # Google Test framework
```

---

## Architecture Layers

DXC follows the classic compiler architecture: **Frontend → Intermediate Representation (IR) → Backend/Infrastructure → Tools**. The table below maps each layer to its directories and primary responsibilities.

| Layer | Directories | Responsibility |
|-------|-------------|----------------|
| **Frontend** | `tools/clang/lib/{Lex,Parse,AST,Sema,CodeGen,SPIRV}`<br>`tools/clang/include/clang/{Lex,Parse,AST,Sema,CodeGen,SPIRV}` | HLSL parsing, semantic analysis, AST construction, and initial IR generation. Reuses Clang's C/C++ infrastructure but adds extensive HLSL-specific behavior. |
| **High-Level IR** | `lib/HLSL/`<br>`include/dxc/HLSL/` | `HLModule` and lowering passes that transform frontend-generated IR into a structured high-level DXIL representation (matrices, signatures, resources). |
| **Low-Level IR (DXIL)** | `lib/DXIL/`<br>`include/dxc/DXIL/` | `DxilModule` — the canonical DXIL data model. Defines shader resources, signatures, operations (`OP`), metadata serialization, and shader model constraints. |
| **LLVM Core** | `lib/IR/`, `lib/Analysis/`, `lib/Transforms/`<br>`lib/Passes/`, `lib/CodeGen/` | Standard LLVM infrastructure: SSA IR, analyses (dominators, loops, alias), optimization passes (GVN, LICM, inlining), and code generation pipeline. |
| **DXIL Infrastructure** | `lib/DxilContainer/`, `lib/DxilValidation/`<br>`lib/DxilRootSignature/`, `lib/DxilHash/`<br>`lib/DxilPdbInfo/`, `lib/DxilCompression/` | Container format (DXBC-like packaging), validation, root signatures, hashing, PDB debug info, and compression. |
| **Debug / PIX** | `lib/DxilDia/`, `lib/DxilPIXPasses/`<br>`lib/DxrFallback/`, `lib/DebugInfo/` | DIA API for shader debugging, PIX instrumentation passes, DXR fallback compiler, and DWARF/PDB debug format parsers. |
| **Compiler Support** | `lib/DxcSupport/`, `lib/Support/`<br>`lib/MSSupport/`, `lib/Bitcode/`<br>`lib/AsmParser/`, `lib/Linker/` | Cross-platform utilities, file I/O, Unicode, Windows shims, bitcode serialization, assembly parser, module linking. |
| **Tools & Drivers** | `tools/clang/tools/{dxc,dxclib,dxcompiler,dxa,dxopt,dxl,dxr,dxv,...}`<br>`tools/{opt,llvm-dis,llc,...}` | Entry points: `dxc.exe`, `dxcompiler.dll`, validator, assembler, linker, disassembler, optimizer, and legacy LLVM tools. |
| **Build & Test** | `cmake/`, `utils/hct/`, `utils/TableGen/`<br>`test/`, `tools/clang/test/`, `unittests/` | CMake configuration, HCT automation scripts, TableGen code generation, LIT/TAEF/GoogleTest test suites. |

---

## Directory-by-Directory Reference

### `tools/clang/` — Clang Frontend (HLSL-Modified)

The heart of the HLSL language implementation. This is not a shallow wrapper around Clang; HLSL support is woven through every major subsystem.

| Subsystem | Key Files | Purpose |
|-----------|-----------|---------|
| **Lexer** | `lib/Lex/HLSLMacroExpander.cpp` | Post-lexing macro expansion for semantic/root signature defines. |
| **Parser** | `lib/Parse/ParseHLSL.cpp`<br>`lib/Parse/HLSLRootSignature.cpp` | Parses `cbuffer`/`tbuffer`, HLSL `[attribute]` syntax, and root signature sub-languages. |
| **AST** | `include/clang/AST/HlslTypes.h`<br>`lib/AST/ASTContext.cpp` | HLSL scalar types, swizzle tracking, builtin object declarations, unusual annotations (registers, packoffsets, semantics). |
| **Sema** | `lib/Sema/SemaHLSL.cpp` (~18K lines)<br>`lib/Sema/SemaHLSLDiagnoseTU.cpp`<br>`lib/Sema/SemaDXR.cpp` | Type checking, overload resolution, intrinsics, attributes, TU-level validation (recursion, entry points, patch constants, exports), DXR checks. |
| **CodeGen** | `lib/CodeGen/CGHLSLMS.cpp` (~268K lines)<br>`lib/CodeGen/CGHLSLMSFinishCodeGen.cpp` (~156K lines)<br>`include/clang/CodeGen/CGHLSLRuntime.h` | Generates **High-Level DXIL** (`HLModule`) from the AST. Handles resources, entry functions, matrix/vector ops, root signatures, subobjects. |
| **SPIR-V** | `lib/SPIRV/EmitSpirvAction.cpp`<br>`lib/SPIRV/EmitVisitor.cpp`<br>`lib/SPIRV/DeclResultIdMapper.cpp` | Alternative backend emitting SPIR-V for Vulkan when `-spirv` is enabled. |
| **Tools** | `tools/dxc/dxcmain.cpp`<br>`tools/dxclib/dxc.cpp`<br>`tools/dxcompiler/dxcapi.cpp`<br>`tools/dxcompiler/dxcompilerobj.cpp` | `dxc.exe` entry point, command-line logic, `DxcCreateInstance` COM entry point, `IDxcCompiler3` implementation. |

### `lib/HLSL/` — HLSL Lowering & DXIL Generation Passes

Transforms high-level HLSL IR into final DXIL through a series of LLVM passes.

| File / Class | Purpose |
|--------------|---------|
| `HLModule.h/cpp` | High-level IR module tracking resources, signatures, options, and thread-group shared memory before DXIL generation. |
| `DxilGenerationPass.h/cpp` | **The bridge pass.** Copies `HLModule` state into `DxilModule` and replaces HL intrinsics with DXIL operations. |
| `HLSignatureLower.h/cpp` | Lowers entry I/O parameters to `LoadInput` / `StoreOutput` DXIL intrinsics. |
| `HLMatrixLowerPass.cpp` / `HLMatrixBitcastLowerPass.cpp` / `HLMatrixType.cpp` | Eliminates HLSL matrix types by lowering them to LLVM vectors. |
| `HLOperationLower.h/cpp` / `HLOperationLowerExtension.cpp` | Lowers HL texture/buffer/math intrinsics to DXIL `OP` calls. |
| `HLOperations.h/cpp` | Defines HL opcode groups (`HLIntrinsic`, `HLCast`, `HLBinOp`, `HLSubscript`, etc.) and name mangling. |
| `DxcOptimizer.cpp` | Implements `IDxcOptimizer` COM interface — enumerates and runs LLVM passes on DXIL blobs. |
| `ComputeViewIdState.cpp` / `ComputeViewIdStateBuilder.cpp` | Computes output-to-input signature dependencies for pipeline validation. |
| `DxilLinker.cpp` | Links multiple DXIL modules/libraries, resolving exports and merging resources. |
| `DxilPreparePasses.cpp` | Prepares and finalizes modules for DXIL emission (collects shader flags, upgrades validator version). |
| `WaveSensitivityAnalysis.cpp` | Validates wave-operation sensitivity constraints. |
| `DxilTargetLowering.cpp` / `DxilTargetTransformInfo.h/cpp` | LLVM target hooks for the DXIL target. |

### `lib/DXIL/` — DXIL Data Model & Metadata Core

Defines what DXIL *is* — the shader-specific LLVM IR dialect.

| File / Class | Purpose |
|--------------|---------|
| `DxilModule.h/cpp` | Central class wrapping `llvm::Module`. Manages shader model, entry functions, resources, signatures, type annotations, subobjects, validator version. |
| `DxilOperations.h/cpp` | **`hlsl::OP`** — DXIL operation manager. Maintains opcode tables, overload types, and caches intrinsic `llvm::Function*` objects per module. |
| `DxilMetadataHelper.h/cpp` | Serializes in-memory DXIL structures to LLVM named metadata (`dx.version`, `dx.shaderModel`, `dx.resources`, `dx.entryPoints`) and deserializes them back. |
| `DxilResource.h/cpp` / `HLResource.h/cpp` | SRV and UAV resources with component type, sample count, stride, coherence flags. |
| `DxilCBuffer.h/cpp` | Constant buffer representation. |
| `DxilSampler.h/cpp` | Sampler state representation. |
| `DxilSignature.h/cpp` / `DxilSignatureElement.h/cpp` | Input/output/patch-constant signature elements with semantic names, interpolation modes, and packing info. |
| `DxilTypeSystem.h/cpp` | Type annotations for structs and functions (matrix annotations, field layouts). |
| `DxilShaderModel.h/cpp` | Shader model versions (`6_0`, `6_5`, `lib_6_6`) and capability queries. |
| `DxilShaderFlags.h/cpp` | Computes shader capability flags (doubles, raytracing, UAVs, wave ops, etc.). |
| `DxilSubobject.h/cpp` | Raytracing pipeline subobjects (state objects, hit groups). |
| `DxilUtil.h/cpp` | General utilities: name demangling, static global detection, diagnostic printing. |
| `DxilInstructions.h` | Typed instruction wrappers for DXIL operations. |
| `DxilConstants.h` | DXIL constants and enumerations. |

### `lib/DxilContainer/` — DXIL Container Format

The binary packaging standard for compiled shaders (analogous to the legacy DXBC format).

| File | Purpose |
|------|---------|
| `DxilContainer.h` (include) | Format specification: headers, FourCC codes, program headers, signatures, source info. |
| `DxilContainerAssembler.cpp` | Serializes LLVM modules + metadata into container parts (signatures, PSV, RDAT, feature info). |
| `DxilContainerReader.cpp` | Parses existing containers; enumerates and extracts parts. |
| `DxcContainerBuilder.cpp` | COM implementation of `IDxcContainerBuilder` — add/remove parts, serialize with optional validation. |
| `DxilRDATBuilder.cpp` | Runtime Data (RDAT) table builder for reflection and subobjects. |
| `DxilPipelineStateValidation.cpp` | Pipeline State Validation (PSV) data structures. |
| `D3DReflectionDumper.cpp` / `RDATDumper.cpp` | Debug utilities for dumping reflection data. |

**Common Container FourCC Parts:**

| FourCC | Description |
|--------|-------------|
| `DXBC` | Container identifier |
| `DXIL` | DXIL program bitcode |
| `PSV0` | Pipeline State Validation data |
| `RDAT` | Runtime reflection data |
| `ISG1` / `OSG1` / `PSG1` | Input / Output / Patch-constant signatures |
| `RDEF` | Resource definitions |
| `STAT` | Shader statistics / feature info |
| `RTS0` | Root signature |
| `HASH` | Shader hash |
| `PDBI` | PDB information |
| `SRCI` | Source information |
| `ILDB` / `ILDN` | Debug info / debug name |

### `lib/DxilValidation/` — DXIL Validator

Ensures DXIL modules and containers are correct, conformant, and internally consistent.

| File | Purpose |
|------|---------|
| `DxilValidation.h` | Public API: `ValidateDxilContainer`, `ValidateLoadModule`, `PrintDiagnosticContext`. |
| `DxilValidation.cpp` | Core module validation: instructions, signatures, resources, shader model constraints. |
| `DxilContainerValidation.cpp` | Container-level validation: verifies parts match module data. |
| `DxilValidationUtils.h/cpp` | `ValidationContext`, `EntryStatus`, and diagnostic emit functions. |

### `lib/DxilRootSignature/` — Root Signature Handling

Parsing, serialization, deserialization, conversion, and validation of HLSL root signatures.

| File | Purpose |
|------|---------|
| `DxilRootSignature.h` | Public structures: `DxilRootSignatureDesc`, `DxilRootParameter`, `DxilDescriptorRange`, `DxilStaticSamplerDesc`. |
| `DxilRootSignature.cpp` | `RootSignatureHandle` implementation and printing. |
| `DxilRootSignatureConvert.cpp` | Version conversion (1.0 ↔ 1.1). |
| `DxilRootSignatureSerializer.cpp` | Binary serialization to blobs. |
| `DxilRootSignatureValidator.cpp` | Overlap detection, descriptor table verification, static sampler checks, PSV binding verification. |

### `lib/DxcSupport/` — Compiler Support Utilities

Foundational utilities used across the compiler.

| File | Purpose |
|------|---------|
| `HLSLOptions.h/cpp` / `HLSLOptions.td` | Command-line option parsing via LLVM `OptTable`. Defines `DxcOpts` struct (~80+ fields). |
| `dxcapi.use.h/cpp` | C++ helpers for loading `dxcompiler.dll`/`dxil.dll`, reading/writing blobs. |
| `FileIOHelper.h/cpp` | Binary file I/O, code page detection, BOM handling. |
| `Unicode.h/cpp` | Wide/UTF-8/UTF-16 conversions. |
| `WinAdapter.cpp` / `WinFunctions.cpp` / `WinIncludes.cpp` | Windows API compatibility layer for non-Windows platforms. |
| `Global.h/cpp` | `DXASSERT`, `hlsl::Exception`, shared constants. |

### `lib/Support/` — LLVM Core Support Library

Platform abstraction, containers, I/O, and diagnostics inherited from LLVM.

| File / Class | Purpose |
|--------------|---------|
| `raw_ostream.cpp` | Universal buffered output stream (`raw_ostream`, `raw_fd_ostream`, `raw_string_ostream`). |
| `MemoryBuffer.cpp` | Read-only file/memory buffer abstraction. |
| `SourceMgr.cpp` / `SMDiagnostic` | Diagnostic infrastructure with source locations and caret output. |
| `CommandLine.cpp` / `cl::opt` | Declarative command-line parsing. |
| `APInt.cpp` / `APFloat.cpp` | Arbitrary-precision integer and floating-point arithmetic. |
| `Triple.cpp` | Target triple parsing (includes `dxil-ms-dx`). |
| `StringMap.cpp` / `SmallVector.cpp` / `FoldingSet.cpp` | Efficient containers and node uniquing. |
| `ErrorHandling.cpp` | Fatal errors and `llvm_unreachable`. **DXC change:** throws `hlsl::Exception` on Windows. |
| `Path.cpp` / `FileSystem` abstractions | Cross-platform path and file operations. |

### `lib/IR/`, `lib/Analysis/`, `lib/Transforms/`, `lib/Passes/`, `lib/CodeGen/` — LLVM Core

Standard LLVM compiler infrastructure. DXC adds shader-specific passes and disables CPU-backend features.

| Directory | Responsibility |
|-----------|----------------|
| `lib/IR/` | In-memory IR: `Value`, `Instruction`, `BasicBlock`, `Function`, `Module`, `LLVMContext`, verifier, printers. |
| `lib/Analysis/` | Alias analysis, dominators, loops, scalar evolution, memory dependence, `DxilValueCache`, `DxilConstantFolding`, `DxilSimplify`. |
| `lib/Transforms/` | Optimization passes: InstCombine, GVN, LICM, SROA, inlining, loop unrolling, `DxilLoopUnroll`, `DxilEliminateVector`, `DxilEraseDeadRegion`, `StructurizeCFG`. |
| `lib/Passes/` | Pass pipeline construction (`PassBuilder`). |
| `lib/CodeGen/` | SelectionDAG instruction selection, scheduling, register allocation, assembly emission, debug info (DWARF/CodeView). |

### `lib/Bitcode/`, `lib/AsmParser/`, `lib/Linker/`, `lib/IRReader/` — IR I/O

| Directory | Responsibility |
|-----------|----------------|
| `lib/Bitcode/Reader/` | Bitstream decoding and IR reconstruction (`BitcodeReader`, `BitstreamReader`). |
| `lib/Bitcode/Writer/` | IR serialization to compact bitcode (`BitcodeWriter`, `ValueEnumerator`). |
| `lib/AsmParser/` | Textual LLVM IR (`.ll`) parser (`LLLexer`, `LLParser`). |
| `lib/Linker/` | Module linking for DXIL libraries (`LinkModules.cpp`, `TypeMapTy`). |
| `lib/IRReader/` | Unified auto-detecting reader for `.ll` and `.bc`. |

### `lib/DxilDia/` — DIA / PIX Debug Info

Implements the Microsoft Debug Interface Access (DIA) API for DXIL, enabling PIX and Visual Studio Graphics Debugger to inspect shader debug metadata.

| File / Class | Interface | Purpose |
|--------------|-----------|---------|
| `DxilDiaDataSource.cpp` | `IDiaDataSource` | Loads DXIL/PDB from streams, parses container/bitcode. |
| `DxilDiaSession.cpp` | `IDiaSession`, `IDxcPixDxilDebugInfoFactory` | Owns LLVM module, instruction maps, line info, symbol manager. |
| `DxcPixEntrypoints.cpp` | (wrapper) | Exception handling, parameter validation, COM lifecycle for all PIX APIs. |
| `DxcPixDxilDebugInfo.cpp` | `IDxcPixDxilDebugInfo` | Main PIX interface: live variables, source locations, stack depth. |
| `DxcPixLiveVariables.cpp` | (internal) | Maps instructions to live HLSL variables via `dbg.declare`/`dbg.value`. |
| `DxcPixTypes.cpp` | `IDxcPix*Type` | Type introspection wrapping LLVM `DIType`. |
| `DxilDiaTableSymbols.cpp` | `IDiaSymbol` | Symbol table for HLSL variables, functions, types. |
| `DxilDiaTableLineNumbers.cpp` | `IDiaLineNumber` | Source line/column mapping. |

### `lib/DxilPIXPasses/` — PIX Instrumentation Passes

LLVM passes that instrument DXIL shaders at compile time to enable PIX debugging and profiling.

| Pass | Purpose |
|------|---------|
| `DxilAnnotateWithVirtualRegister` | Assigns virtual register IDs to instructions for PIX value tracking. |
| `DxilDebugInstrumentation` | **Core debugging pass.** Inserts UAV writes to capture shader execution traces. |
| `DxilShaderAccessTracking` | Instruments every resource access (sample, load, store) for performance analysis. |
| `DxilAddPixelHitInstrumentation` | Pixel-shader-specific hit counting and cost recording. |
| `DxilDbgValueToDbgDeclare` | Converts `llvm.dbg.value` to `llvm.dbg.declare` for debug stability. |
| `PixPassHelpers` | Shared infrastructure: UAV creation, handle generation, root signature extension. |

### `lib/DxrFallback/` — DXR Fallback Compiler

Transforms DXR (DirectX Raytracing) shader libraries into a single compute shader for hardware without native DXR driver support.

| File / Class | Purpose |
|--------------|---------|
| `DxrFallbackCompiler.cpp` | Orchestrates fallback compilation: links libs, inlines functions, drives state transform. |
| `StateFunctionTransform.h/cpp` | Splits functions into state-machine substates at `TraceRay`/`CallShader` calls; manages software stack for live values. |
| `LiveValues.h/cpp` | Liveness analysis across continuation points. |

### `lib/DebugInfo/` — Debug Format Parsers

| Subdirectory | Purpose |
|--------------|---------|
| `DWARF/` | Parses `.debug_line`, `.debug_loc`, `.debug_frame`, `.debug_info` for ELF/object files. |
| `PDB/` | Windows PDB abstraction: `PDBSymbol`, `PDBContext`, symbol dumping. |
| `PDB/DIA/` | Bridges LLVM's `IPDBSession` to Microsoft's DIA SDK (`msdia*.dll`). |

### `projects/dxilconv/` — DXBC to DXIL Converter

| Component | Purpose |
|-----------|---------|
| `lib/DxbcConverter/` | Core converter: reads legacy DXBC shaders, translates to DXIL. |
| `lib/DxilConvPasses/` | LLVM passes that clean up and normalize converted DXIL (`DxilCleanup`, `NormalizeDxil`, `ScopeNestedCFG`). |
| `lib/ShaderBinary/` | DXBC container reader. |
| `tools/dxbc2dxil/` | Command-line tool. |
| `test/` | Extensive regression tests with `.dxbc`, `.hlsl`, and `.ref` files. |

### `external/` — External Dependencies

| Directory | License | Purpose |
|-----------|---------|---------|
| `DirectX-Headers/` | MIT | Official D3D12 headers + WSL compatibility shims. Required for reflection on Linux. |
| `SPIRV-Headers/` | MIT | Canonical SPIR-V instruction set headers (`spirv.hpp`). |
| `SPIRV-Tools/` | Apache 2.0 | SPIR-V assembler, disassembler, validator, optimizer libraries. |

---

## Data Flow Diagram

```text
  HLSL Source Code (.hlsl)
        │
        ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  FRONTEND: tools/clang                                      │
  │  • Lexer     → Tokens (with HLSL keywords)                  │
  │  • Preprocessor → Macro expansion                           │
  │  • Parser    → AST (cbuffer, [attributes], root signatures) │
  │  • Sema      → Validated AST (types, intrinsics, overloads) │
  │  • SemaHLSLDiagnoseTU → Recursion/entry-point validation    │
  └─────────────────────────────────────────────────────────────┘
        │
        ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  HIGH-LEVEL IR: lib/HLSL (HLModule)                         │
  │  • CGHLSLMS.cpp generates HLModule + LLVM IR                │
  │  • Resources tracked as HL objects (textures, buffers, etc.)│
  │  • Matrix/vector types present                              │
  │  • Entry signatures in high-level form                      │
  └─────────────────────────────────────────────────────────────┘
        │
        ▼  [LLVM Pass Pipeline]
  ┌─────────────────────────────────────────────────────────────┐
  │  LOWERING PASSES (lib/HLSL + lib/Transforms)                │
  │  • HLMatrixLowerPass      → matrices → vectors              │
  │  • HLSignatureLower       → I/O params → LoadInput/StoreOut │
  │  • HLOperationLower       → HL intrinsics → DXIL OP calls   │
  │  • DxilLoopUnroll, DxilEliminateVector, StructurizeCFG      │
  │  • Mem2Reg, SROA, GVN, LICM, Inliner, etc.                  │
  └─────────────────────────────────────────────────────────────┘
        │
        ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  DXIL GENERATION: lib/HLSL                                  │
  │  • DxilGenerationPass (HLModule → DxilModule)               │
  │    - Copies resources, signatures, shader properties          │
  │    - Replaces HL intrinsics with dx.op.* calls               │
  │    - Attaches DxilModule to llvm::Module                     │
  └─────────────────────────────────────────────────────────────┘
        │
        ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  LOW-LEVEL IR: lib/DXIL (DxilModule)                        │
  │  • DxilModule owns canonical shader state                   │
  │  • OP manages dx.op opcode tables                           │
  │  • DxilMetadataHelper serializes to LLVM named metadata     │
  │  • ShaderModel, ShaderFlags, Subobjects computed            │
  └─────────────────────────────────────────────────────────────┘
        │
        ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  DXIL INFRASTRUCTURE                                        │
  │  • DxilValidation  → Validates instructions & constraints   │
  │  • DxilContainerAssembler → Packs bitcode + metadata parts  │
  │    - DXIL bitcode, PSV0, RDAT, signatures, hash, root sig   │
  │  • DxilHash        → Computes container hash                │
  │  • DxilPdbInfo     → Compresses debug info (optional)       │
  │  • DxilCompression → zlib via miniz                         │
  └─────────────────────────────────────────────────────────────┘
        │
        ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  OUTPUT: DXIL Container (.dxil / .cso)                      │
  │  • DXBC header + multiple parts (DXIL, PSV0, RDAT, etc.)    │
  │  • Optional: debug info (PDB), reflection, root signature   │
  └─────────────────────────────────────────────────────────────┘
```

**Alternative SPIR-V Path:**
```text
  Validated AST
        │
        ▼
  tools/clang/lib/SPIRV/
  • EmitSpirvAction → SPIR-V instructions
  • SPIRV-Tools opt/validate (optional)
        │
        ▼
  SPIR-V Binary (.spv)
```

---

## Build System Overview

DXC uses **CMake** as its primary build system generator, with extensive customizations for HLSL/DXIL and SPIR-V compilation.

### Key CMake Files

| File | Purpose |
|------|---------|
| `CMakeLists.txt` (root) | Defines `ENABLE_SPIRV_CODEGEN`, `SPIRV_BUILD_TESTS`, `HLSL_INCLUDE_TESTS`. Adds `external/` subdirectory. |
| `cmake/modules/AddLLVM.cmake` | Core LLVM target helpers; HLSL-specific iterator debug level (`_ITERATOR_DEBUG_LEVEL=0`). |
| `cmake/modules/HandleLLVMOptions.cmake` | Compiler version validation, EH/RTTI flags, HLSL-specific compile flags. |
| `cmake/modules/HCT.cmake` | **DXC-specific.** Defines `add_hlsl_hctgen()` for generating HLSL/DXIL sources from `hctgen.py`. |
| `cmake/modules/TableGen.cmake` | Runs `llvm-tblgen` on `.td` files; supports cross-compilation via `LLVM_USE_HOST_TOOLS`. |
| `cmake/caches/PredefinedParams.cmake` | Pre-configured cache for *nix builds: `LLVM_DEFAULT_TARGET_TRIPLE="dxil-ms-dx"`, `LLVM_ENABLE_EH=ON`, `LLVM_ENABLE_RTTI=ON`, `LLVM_TARGETS_TO_BUILD="None"`. |

### HCT Build Automation (`utils/hct/`)

The **HLSL Console Tools** provide a polished Windows command-line workflow.

| Script | Purpose |
|--------|---------|
| `hctstart.cmd` | Entry point: sets environment (`HLSL_SRC_DIR`, `HLSL_BLD_DIR`), finds CMake/Python/TAEF/Git, validates Windows SDK. |
| `hctbuild.cmd` | Main build script: CMake + MSBuild/VS. Supports `-official`, `-fv`, `-analyze`, `-spirv`, `DXILCONV`, multiple architectures. |
| `hcttest.cmd` | Test runner: TAEF-based and LIT-based tests. Supports filtering, SPIRV tests, execution tests, parallel runs. |
| `hctclean.cmd` | Deletes the build directory. |
| `hctgen.py` | **Code generator.** Generates headers/tables from `gen_intrin_main.txt` and the DXIL database. Modes: `HLSLIntrinsicOp`, `DxilConstants`, `DxilInstructions`, `DxilShaderModel`, `DxilValidation`, `HLSLOptions`, `DxcOptimizer`. |
| `hctdb.py` / `hctdb_instrhelp.py` | DXIL database: shader stages, instruction overloads, enums. |
| `gen_version.py` | Generates version resources from Git metadata and `latest-release.json`. |

### Source Generation Pipeline

```text
gen_intrin_main.txt  +  hctdb.py/hctdb_instrhelp.py
         │
         ▼
    hctgen.py --mode <MODE> --output <file>
         │
         ▼
    clang-format -i <file>
         │
         ▼
    [copy_if_different to source tree]
         │
         ▼
    <generated .h/.cpp/.inl files>
```

**Generated artifacts include:** `HlslIntrinsicOp.h`, `DxilConstants.h`, `DxilInstructions.h`, `DxilShaderModel.h`, `DxilValidation.inc`, `HLSLOptions.cpp`, `DxcOptimizer.cpp`.

### Build Configurations

| Variable | Typical Value | Description |
|----------|---------------|-------------|
| `LLVM_DEFAULT_TARGET_TRIPLE` | `dxil-ms-dx` | Target triple for DXIL generation |
| `LLVM_ENABLE_EH` | `ON` | C++ exceptions (required by DXC frontend) |
| `LLVM_ENABLE_RTTI` | `ON` | Run-Time Type Information |
| `LLVM_TARGETS_TO_BUILD` | `None` | No native CPU backends |
| `ENABLE_SPIRV_CODEGEN` | `ON` (Linux) / `OFF` (Windows default) | SPIR-V backend |
| `HLSL_INCLUDE_TESTS` | `ON` | HLSL-specific tests |
| `HLSL_COPY_GENERATED_SOURCES` | `Off` | Copy generated sources back to source tree |

### Cross-Compilation

- **Android:** `cmake/platforms/Android.cmake` — NDK toolchain, `arm-linux-androideabi`.
- **iOS:** `cmake/platforms/iOS.cmake` — Xcode toolchain, `xcrun` compiler detection.
- **Native TableGen:** When cross-compiling, builds a host-native `llvm-tblgen` first.

---

## Testing Infrastructure Overview

DXC inherits LLVM's multi-layered testing infrastructure and extends it with HLSL/DXIL-specific suites.

### Test Frameworks

| Framework | Purpose | Location |
|-----------|---------|----------|
| **LIT** | LLVM Integrated Tester — runs `.ll`, `.hlsl`, `.test` files with `RUN:` directives. | `utils/lit/`, `test/lit.cfg`, `tools/clang/test/lit.cfg` |
| **FileCheck** | Pattern-matching utility for verifying compiler output. | `utils/FileCheck/` |
| **GoogleTest** | C++ unit tests for LLVM/DXC libraries. | `utils/unittest/googletest/`, `unittests/` |
| **TAEF** | Test Authoring and Execution Framework (Windows-only, from WDK). | Driven via `tools/clang/test/taef/lit.cfg` |

### Test Directory Layout

| Directory | Framework | Status | Description |
|-----------|-----------|--------|-------------|
| `test/` | LIT | Partial | LLVM core tests. Most disabled for HLSL (`config.suffixes = []`). Active: `FileCheck/`, `TableGen/`, `Verifier/`, `HLSL/`, `LTO/`. |
| `unittests/` | GoogleTest | Active | ADT, Analysis, Bitcode, IR, Support, DxcSupport, DxilHash, Option, Transforms. |
| `tools/clang/test/HLSLFileCheck/` | TAEF | Hidden from LIT | **Largest HLSL corpus** (~2,210 files). Runs via `ClangHLSLTests.dll`. |
| `tools/clang/test/HLSLFileCheckLit/` | LIT | Active | Lit-native subset of HLSLFileCheck tests. |
| `tools/clang/test/CodeGenDXIL/` | LIT | Active | DXIL code generation tests (~135 files). |
| `tools/clang/test/CodeGenHLSL/` | TAEF | Hidden | HLSL codegen tests run under TAEF. |
| `tools/clang/test/SemaHLSL/` | LIT | Active | HLSL semantic analysis (~261 files). |
| `tools/clang/test/DXC/` | LIT | Active | DXC driver/CLI tests (~153 files). |
| `tools/clang/test/LitDXILValidation/` | LIT | Active | DXIL validation tests (~35 files). |
| `tools/clang/test/CodeGenSPIRV/` | LIT | Active | SPIR-V backend tests (~1,573 files). |
| `projects/dxilconv/test/` | TAEF | Active | DXBC-to-DXIL converter tests. |

### Running Tests

| Command | Description |
|---------|-------------|
| `ninja check-llvm` | LLVM core LIT tests |
| `ninja check-clang` | Clang/HLSL LIT tests |
| `ninja check-all` | All enabled LIT tests |
| `hcttest` (Windows) | Unified TAEF + LIT test runner |
| `te.exe ClangHLSLTests.dll` | Direct TAEF execution |

### Key Architectural Decisions

1. **Most LLVM backend tests are disabled** because DXC does not target CPU architectures.
2. **TAEF runs the bulk of HLSL tests** (`HLSLFileCheck/`, `CodeGenHLSL/`) for efficient batch execution on Windows.
3. **Lit-native suites** (`SemaHLSL/`, `CodeGenDXIL/`, `DXC/`, `LitDXILValidation/`) provide cross-platform coverage.
4. **External DXIL validator testing:** CMake can download released DXC binaries and run tests against historical `dxil.dll` versions to ensure backward compatibility.

---

## Key Dependencies

### External Submodules (`external/`)

| Dependency | License | Required For | Platform Notes |
|------------|---------|--------------|----------------|
| **DirectX-Headers** | MIT | Reflection on *nix | Linux/WSL require this; Windows can use SDK headers. |
| **SPIRV-Headers** | MIT | SPIR-V codegen | Required when `ENABLE_SPIRV_CODEGEN=ON`. |
| **SPIRV-Tools** | Apache 2.0 | SPIR-V opt/validate/disasm | Library-only consumption (`SPIRV_SKIP_EXECUTABLES=ON`). |

### Bundled / Inherited

| Dependency | Location | Purpose |
|------------|----------|---------|
| **Google Test** | `utils/unittest/googletest/` | C++ unit testing framework. |
| **miniz** | `lib/DxilCompression/`, `include/miniz/` | Single-file zlib replacement for PDB/container compression. |

### Windows-Only Requirements

| Dependency | Purpose |
|------------|---------|
| **Windows SDK ≥ 10.0.26100.0** | D3D12 headers (`d3d12.h`) for build and `dxexp` tool. |
| **DIA SDK** | Debug info processing (`dia2.h`, `diaguids.lib`). Located via `vswhere.exe`. |
| **TAEF (WDK)** | Running `hcttest` and TAEF-based test suites (`te.exe`). |

---

## Glossary of Important Terms

| Term | Definition |
|------|------------|
| **DXIL** | **DirectX Intermediate Language.** Microsoft's LLVM-based IR for shader compilation. Fixed on LLVM 3.7 bitcode. It is the contract between compilers (like DXC) and GPU driver JIT compilers. |
| **DXBC** | **DirectX ByteCode.** The legacy binary shader format used by D3D9–D3D11 and the old `fxc` compiler. DXC can disassemble DXBC and `dxilconv` can convert it to DXIL. |
| **DXIL Container** | The binary packaging format for compiled DXIL shaders (FourCC `DXBC` header + multiple parts: DXIL bitcode, PSV, RDAT, signatures, hash, PDB, etc.). |
| **HLModule** | **High-Level Module.** Attached to `llvm::Module` during frontend code generation. Tracks high-level HLSL concepts (matrix types, HL intrinsics, resources) before they are lowered to strict DXIL. |
| **DxilModule** | **DXIL Module.** The canonical low-level shader representation attached to `llvm::Module` after `DxilGenerationPass`. Manages shader model, entry functions, resources, signatures, type annotations, and subobjects. |
| **OP (DxilOperations)** | The DXIL operation manager (`hlsl::OP`). Maintains tables of all `dx.op.*` intrinsics, their overload types, and caches `llvm::Function*` objects. |
| **DxilMetadataHelper** | Serializes in-memory DXIL structures (resources, signatures, shader properties) into LLVM named metadata nodes (`dx.version`, `dx.shaderModel`, `dx.resources`, `dx.entryPoints`) and deserializes them back. |
| **PSV (Pipeline State Validation)** | Container part (`PSV0`) that tracks pipeline state: signatures, resource bindings, thread counts, wave sizes. Used by the D3D12 runtime for PSO creation validation. |
| **RDAT (Runtime Data)** | Container part (`RDAT`) that holds runtime reflection data: subobjects, function tables, resource bindings, and metadata for `ID3D12ShaderReflection`. |
| **Root Signature** | A DirectX 12 descriptor binding declaration that defines how shader resources (CBVs, SRVs, UAVs, samplers) are mapped to the pipeline. Can be defined in HLSL or via API. |
| **Shader Model** | The execution model and capability version (e.g., `6_0`, `6_6`, `6_8`, `lib_6_3`). Determines which intrinsics and features are available. |
| **Shader Stage** | The GPU pipeline stage: Vertex (VS), Hull (HS), Domain (DS), Geometry (GS), Pixel (PS), Compute (CS), Mesh (MS), Amplification (AS), Raytracing (various), Library (`lib`). |
| **SPIR-V** | Khronos's standard intermediate language for Vulkan and OpenCL. DXC can emit SPIR-V via the `clangSPIRV` backend when `-spirv` is specified. |
| **TAEF** | **Test Authoring and Execution Framework.** Microsoft's Windows test framework (part of WDK). DXC uses it for large HLSL regression test suites on Windows. |
| **LIT** | **LLVM Integrated Tester.** The primary cross-platform test runner for LLVM and DXC. Executes `RUN:` directives in `.ll`, `.hlsl`, and `.test` files. |
| **TableGen** | LLVM's domain-specific language and tool for generating code from `.td` files. DXC uses it for intrinsics, diagnostics, pass registration, and command-line options. |
| **HCT** | **HLSL Console Tools.** DXC's Windows build/test automation suite (`hctstart`, `hctbuild`, `hcttest`, `hctgen`). |
| **hctgen.py** | Python script that generates C++ source files (headers, tables, documentation) from `gen_intrin_main.txt` and the DXIL database (`hctdb.py`). |
| **PIX** | **Performance Investigator for Xbox/DirectX.** Microsoft's GPU debugging/profiling tool. DXC provides `DxilPIXPasses` for shader instrumentation and `DxilDia` for debug info access. |
| **DIA** | **Debug Interface Access.** Microsoft's COM API for reading debug info from PDBs. `DxilDia` implements DIA for DXIL modules so PIX can inspect HLSL source locations and variables. |
| **DXR** | **DirectX Raytracing.** Shader model 6.3+ feature for hardware-accelerated raytracing. DXC supports DXR shaders and the `DxrFallback` compiler for non-DXR hardware. |
| **SROA** | **Scalar Replacement of Aggregates.** LLVM pass that promotes `alloca` structs/arrays to scalar SSA registers. DXC excludes resource and matrix types. |
| **Mem2Reg** | LLVM pass that promotes memory references to registers using dominance frontiers and PHI insertion. |
| **SelectionDAG** | LLVM's DAG-based instruction selection framework used by `lib/CodeGen`. DXC uses the classic SelectionDAG path (not GlobalISel). |
| **FourCC** | A four-character code used to identify parts within a DXIL container (e.g., `DXIL`, `PSV0`, `RDAT`, `ISG1`). |
| **IDxcCompiler3** | The main COM interface for compiling HLSL. Replaces older `IDxcCompiler`/`IDxcCompiler2`. |
| **IDxcUtils** | COM utility interface for blob creation, file loading, argument building, reflection creation, and container part extraction. |
| **IDxcBlob** / **IDxcBlobEncoding** | COM interfaces for sized buffers with optional text encoding. Replace `ID3DBlob` in DXC. |

---

*Document synthesized from comprehensive source analysis of the DirectX ShaderCompiler repository.*
