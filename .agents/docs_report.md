# Documentation Analysis

## Project Overview

The **DirectX Shader Compiler (DXC)** is a compiler and toolchain that compiles High-Level Shader Language (HLSL) programs into DirectX Intermediate Language (DXIL). It is built on LLVM 3.7 and Clang. The `docs/` directory contains a mixture of upstream LLVM documentation inherited from the fork, DXC-specific documentation for HLSL/DXIL/SPIR-V, build instructions, and contributor guides.

---

## Complete File Inventory

The `D:/DirectXShaderCompiler/docs` directory contains **93 items** (files and directories). Below is a categorized listing derived from glob patterns `docs/*` and `docs/**/*`.

### DXC-Specific Documentation
| File | Description |
|------|-------------|
| `HLSLChanges.rst` | Architectural changes to LLVM/Clang for HLSL support |
| `DXIL.rst` | DirectX Intermediate Language specification |
| `SPIR-V.rst` | HLSL to SPIR-V feature mapping manual |
| `SPIRV-Cookbook.rst` | Practical HLSL coding patterns for SPIR-V |
| `SourceLevelDebuggingHLSL.rst` | Source-level debugging specifics for HLSL/DXIL |
| `ReleaseNotes.md` | Changelog and release notes |
| `BuildingAndTestingDXC.rst` | Build and test instructions |

### LLVM Core Documentation (Inherited)
| File | Description |
|------|-------------|
| `LangRef.rst` | LLVM IR language reference |
| `CodingStandards.rst` | LLVM coding standards (C++11 style) |
| `ProgrammersManual.rst` | LLVM APIs and source layout |
| `Atomics.rst` | LLVM concurrency model |
| `CommandLine.rst` | Command-line parsing library |
| `ExtendingLLVM.rst` | Adding instructions and intrinsics |
| `CMake.rst` | CMake build system addendum |
| `Passes.rst` | Optimizations and analyses |
| `BitCodeFormat.rst` | LLVM bitcode encoding |
| `CodeGenerator.rst` | LLVM code generator design |
| `ExceptionHandling.rst` | Exception handling design |
| `LinkTimeOptimization.rst` | LTO interface |
| `Vectorizers.rst` | Vectorization status |
| `WritingAnLLVMBackend.rst` | Backend authoring guide |
| `WritingAnLLVMPass.rst` | Pass authoring guide |
| `TableGen/index.rst` | TableGen tool documentation |
| `CommandGuide/index.rst` | LLVM command-line utilities |

### Other Inherited LLVM Docs
- `AliasAnalysis.rst`, `BitSets.rst`, `BlockFrequencyTerminology.rst`, `BranchWeightMetadata.rst`
- `CoverageMappingFormat.rst`, `FaultMaps.rst`, `Frontend/PerformanceTips.rst`
- `GetElementPtr.rst`, `HowToSetUpLLVMStyleRTTI.rst`, `HowToUseAttributes.rst`
- `HowToUseInstrMappings.rst`, `InAlloca.rst`, `Lexicon.rst`, `LibFuzzer.rst`
- `LLVMBuild.rst`, `MarkedUpDisassembly.rst`, `MergeFunctions.rst`
- `SourceLevelDebugging.rst`, `SystemLibrary.rst`, `YamlIO.rst`

### Build and Infrastructure Files
| File | Description |
|------|-------------|
| `conf.py` | Sphinx configuration |
| `CMakeLists.txt` | CMake build for docs |
| `Makefile.sphinx` | Sphinx Makefile |
| `make.bat` | Windows batch build |
| `README.txt` | Docs directory readme |
| `Dummy.html` | Placeholder HTML |

### Themes and Styling
- `_static/` — Static assets (CSS, images)
- `_templates/` — HTML templates
- `_themes/dxc-theme/` — Custom DXC Sphinx theme

---

## Key Documents and Their Purposes

### 1. `index.rst` — Documentation Index
This is the main entry point for the Sphinx-generated documentation. It categorizes all documents into:
- **LLVM Design & Overview** — Introductory papers, LangRef, DXIL, HLSLChanges
- **User Guides** — CMake, command guides, lexicon, passes, performance tips
- **Programming Documentation** — Atomics, coding standards, programmer's manual, libFuzzer
- **Subsystem Documentation** — Code generator, alias analysis, debugging, bitcode format, TableGen

### 2. `HLSLChanges.rst` — HLSL Architecture Changes
This document explains the high-level design decisions made when forking LLVM/Clang to support HLSL. Key topics include:

- **Forking Rationale**: HLSL diverged from C/C++ in significant ways (type system, semantics), making upstreaming difficult at the time. Changes are marked with "HLSL Change" or "HLSL Change Starts/Ends" pairs to ease future LLVM integrations.
- **Dependency Injection**: To make `dxcompiler.dll` reusable and thread-safe, all process-wide state (stdin/stdout, filesystem access, memory allocation, environment variables) was virtualized via a thread-local `MSFileSystem` component.
- **Error Handling**: Two additional mechanisms were introduced beyond LLVM's existing ones:
  - **C++ Exceptions** — primarily for out-of-memory and recoverable errors
  - **HRESULT** — Windows-style error codes returned via APIs for familiarity
- **Component Design (COM-lite)**: The DLL exports a lightweight COM model. Objects implement `IUnknown`, and construction goes through `DxcCreateInstance`. Memory allocated for consumers uses `CoTaskMemAlloc`.
- **Text/Buffer Management**: `IDxcBlob` and `IDxcBlobEncoding` replace `ID3DBlob`. Internal text uses UTF-8 (`char*`), short API parameters use UTF-16 (`wchar_t*`), and buffers use `IDxcBlobEncoding`.
- **Specification Database**: `utils/hct/hctdb.py` contains a Python-driven specification database used for code generation and compatibility checks.
- **HLSL Modules**: Two in-memory modules attach to `llvm::Module`:
  - **HLModule** — high-level concepts (intrinsics, matrices, vectors)
  - **DxilModule** — low-level DXIL specification concepts
  The `DxilGenerationPass` destroys HLModule and creates DxilModule.

### 3. `DXIL.rst` — DirectX Intermediate Language Specification
This is the authoritative specification for DXIL. It is extremely detailed (~2000+ lines). Key topics include:

- **Purpose**: Unify the shader compilation toolchain and leverage the LLVM ecosystem. DXIL is a contract between IR producers (compilers) and IR consumers (driver JIT compilers, offline compilers).
- **Versioning**: Three mechanisms:
  - **Shader Model** (`!dx.shaderModel`) — execution model and capabilities
  - **DXIL Version** (`!dx.version`) — rules evolution (1.0, 1.1, 1.2)
  - **LLVM Bitcode Version** — fixed at LLVM 3.7
- **Type System**: Supports void, metadata, i1/i8/i16/i32/i64, half/float/double. Vectors, matrices, arrays, and user-defined types are scalarized/lowered but may remain in declarations for reflection/debugging.
- **Memory Model**: Uses LLVM address spaces:
  - `AS_default (0)` — code, local, indexable threadlocal
  - `AS_memory (1)` — device memory (raw buffers)
  - `AS_cbuffer (2)` — constant buffer memory
  - `AS_groupshared (3)` — groupshared memory
- **Control Flow**: Must be reducible (T1-T2 test). Supports functions and calls, but **no recursion, exceptions, or indirect calls**.
- **Shader Signatures**: Formalizes input/output parameters. Includes detailed signature packing algorithms, semantic index assignment, and metadata records for all shader stages (VS, HS, DS, GS, PS, CS, MS, AS).
- **Resources**: Metadata lists for SRVs, UAVs, CBVs, and Samplers. Resource operations (sample, load, store, atomic) are expressed as external function calls with overloads for precision.
- **Operations**: Extensive listings of DXIL intrinsics including `sample`, `textureLoad`, `bufferLoad`, `atomicBinOp`, `calculateLOD`, `textureGather`, `cbufferLoad`, `rawBufferLoad`, etc.

### 4. `SPIR-V.rst` — HLSL to SPIR-V Feature Mapping
This is a massive manual (~2000+ lines) describing how HLSL constructs map to SPIR-V for Vulkan. Key topics include:

- **Entry Function Wrapper**: Vulkan entry functions take no parameters and return void. DXC emits a wrapper that reads SPIR-V `Input` globals, calls the HLSL entry function, and writes to `Output` globals.
- **Descriptor Binding**: Supports `[[vk::binding(X, Y)]]`, `[[vk::counter_binding(Z)]]`, and `:register()` mappings. Command-line shifts (`-fvk-b-shift`, etc.) allow implicit register-to-binding conversion.
- **Vulkan-Specific Attributes**: A rich set of `vk::` attributes:
  - `location`, `binding`, `counter_binding`, `push_constant`, `offset`, `constant_id`
  - `input_attachment_index`, `builtin`, `index`, `post_depth_coverage`
  - `combinedImageSampler`, depth/stencil execution modes, `image_format`
- **Type Mappings**: Scalar, vector, matrix, struct, array, sampler, texture, and buffer mappings to SPIR-V types. Matrices are transposed (HLSL row-major → SPIR-V column-major conceptually).
- **Buffer Types**: Detailed mapping of `cbuffer`, `ConstantBuffer`, `StructuredBuffer`, `RWStructuredBuffer`, `ByteAddressBuffer`, etc. to Vulkan uniform/storage buffers with layout rules (std140/std430/DX/scalar).
- **System Value Semantics**: Comprehensive table mapping HLSL `SV_*` semantics to SPIR-V `BuiltIn` decorations and required capabilities.
- **Legalization / Optimization / Validation**: Delegated to SPIRV-Tools. Legalization removes temporary resource copies. Optimization uses `spirv-opt`. Validation is on by default.
- **Debugging**: `-Zi` enables debug info. `-fspv-debug=` provides fine-grained control. `-fspv-debug=vulkan-with-source` emits `NonSemantic.Shader.DebugInfo.100`.

### 5. `SPIRV-Cookbook.rst` — DXC Cookbook for SPIR-V
A practical guide with concrete HLSL examples showing what code patterns are accepted when targeting SPIR-V. Key lessons:
- **Legalization** is the process of transforming HLSL so all resource accesses go directly to global resources.
- **Accepted patterns**: Single copies to locals, function parameters, return values, nested struct copies, and unrolled loops with constant conditions.
- **Rejected patterns**: Runtime-conditional resource selection (if/switch with non-constant conditions), multiple returns with runtime-dependent values, loops with uninferable bounds, and floating-point induction variables.
- **Rule of thumb**: The compiler must be able to determine at compile time exactly which global resource is used for every load/store.

### 6. `BuildingAndTestingDXC.rst` — Build and Test Guide
- **Build System**: CMake-based. Cache script at `cmake/caches/PredefinedParams.cmake` simplifies configuration.
- **Prerequisites**: Git, Python 3.x, CMake ≥ 3.17.2, C++14 compiler. Windows additionally requires Visual Studio 2019+, Windows SDK 10.0.26100.0+, and WDK.
- **Generators**: Supports Visual Studio, Ninja, Unix Makefiles, and Visual Studio's CMake integration.
- **Testing**: LIT-based testing targets:
  - `llvm-test-depends`, `clang-test-depends`, `test-depends`
  - `check-llvm`, `check-clang`, `check-all`
- **Legacy Windows Tooling**: `utils/hct/hctshortcut.js` sets up environment; `hctbuild` and `hcttest` use TAEF framework from WDK.
- **CMake Options**: `CMAKE_BUILD_TYPE`, `LLVM_USE_LINKER`, `LLVM_PARALLEL_COMPILE_JOBS`, `LLVM_PARALLEL_LINK_JOBS`, `DXC_COVERAGE`.

### 7. `ReleaseNotes.md` — Changelog
Documents releases from **1.7.2207** through **1.9.2602** and the upcoming experimental release. Notable milestones:
- **Shader Model 6.7–6.9**: Wave intrinsics, QuadAny/QuadAll, raw gather, programmable offsets, long vectors, cooperative vectors, opacity micromaps, shader execution reordering.
- **Shader Model 6.10 (Experimental)**: `GetGroupWaveIndex`, `GetGroupWaveCount`, `DebugBreak()`, `dx::IsDebuggerPresent()`.
- **HLSL 2021/202x**: Enabled by default in 1.7.2308. Literal type conformance updates.
- **SPIR-V Backend**: Continuously improved with new extensions, bug fixes, and attribute support.
- **Platforms**: Windows (x64, ARM64), Linux (x64).

### 8. `SourceLevelDebuggingHLSL.rst` — Debug Information
- **Container Parts**:
  - `DFCC_DXIL` — compiled shader program
  - `DFCC_ShaderDebugInfoDXIL` (`ILDB`) — LLVM module with debug info (sometimes called "the PDB")
  - `DFCC_ShaderDebugName` (`ILDN`) — external debug info filename
- **API Access**: Full fidelity via LLVM libraries; limited DIA compatibility via `CLSID_DxcDiaDataSource`.
- **Command-Line Options**:
  - `/Zi` — enable debug info
  - `/Zss` — source-aware debug name
  - `/Zsb` — binary-only debug name (for deduplication)
  - `/Fd` — extract debug info to external file
  - `/Qstrip_debug` — remove debug info from container

---

## HLSL/DXIL Specific Documentation

The core DXC-specific docs are:

| Document | Scope | Audience |
|----------|-------|----------|
| `HLSLChanges.rst` | Architecture & design rationale | Compiler developers, integrators |
| `DXIL.rst` | IR specification (types, ops, resources, signatures) | Driver/compiler backend developers, tool authors |
| `SPIR-V.rst` | HLSL→SPIR-V translation reference | Vulkan shader developers, tool authors |
| `SPIRV-Cookbook.rst` | Valid HLSL patterns for SPIR-V | Shader programmers targeting Vulkan |
| `SourceLevelDebuggingHLSL.rst` | Debug info format and tools | Tool developers, debugger authors |
| `ReleaseNotes.md` | Feature changelog | All users and developers |

### Relationship Between Documents
```
HLSLChanges.rst  -->  Why and how LLVM was forked
       |
       v
DXIL.rst         -->  The DXIL intermediate representation specification
       |
       v
SPIR-V.rst       -->  How DXC maps HLSL/DXIL concepts to SPIR-V for Vulkan
       |
       v
SPIRV-Cookbook.rst --> Practical code patterns that legalize successfully
```

---

## Build and Contribution Docs

| Document | Scope |
|----------|-------|
| `BuildingAndTestingDXC.rst` | Primary build guide (CMake, LIT, legacy hctbuild) |
| `CMake.rst` | LLVM CMake addendum |
| `CodingStandards.rst` | LLVM C++ coding standards (formatting, doxygen, C++11 features) |
| `README.txt` | Brief docs directory readme |

### Key Build Facts
- **Submodules required**: `git submodule update --init --recursive`
- **Out-of-tree builds enforced**: Cannot run CMake in repository root
- **Cache script**: `cmake/caches/PredefinedParams.cmake` sets required DXC options
- **Windows legacy path**: `utils/hct/hctbuild` and `utils/hct/hcttest` via HLSL Console

---

## Summary

The `docs/` directory in DirectXShaderCompiler is a **hybrid documentation set** inherited from LLVM and extended with DXC-specific specifications.

### Strengths
1. **Comprehensive IR Specification**: `DXIL.rst` is an exhaustive, formal specification suitable for driver compiler authors.
2. **Detailed SPIR-V Mapping**: `SPIR-V.rst` is one of the most complete HLSL→SPIR-V references available, covering semantics, types, buffers, builtins, and Vulkan attributes.
3. **Practical Cookbook**: `SPIRV-Cookbook.rst` bridges the gap between specification and real-world shader authoring.
4. **Well-Organized Index**: `index.rst` categorizes docs by audience (users, programmers, subsystem developers).
5. **Release Tracking**: `ReleaseNotes.md` provides a clear history of feature evolution.

### Observations
- Much of the documentation is inherited from LLVM 3.7 and may not reflect current DXC practices (e.g., `CodingStandards.rst` explicitly notes it describes LLVM, not DXC).
- The build documentation has two parallel paths: the modern CMake/LIT path and the legacy Windows HCT/TAEF path.
- `DXIL.rst` and `SPIR-V.rst` are extremely long (~2000+ lines each) and function more as specifications than casual reading material.
- There is no dedicated "Getting Started for Shader Authors" document in `docs/`; that guidance lives in the repository root `README.md` and wiki.

### Quick Reference for Navigating Docs
| If you want to... | Read... |
|-------------------|---------|
| Understand DXC's LLVM fork | `HLSLChanges.rst` |
| Learn the DXIL instruction set | `DXIL.rst` |
| Target Vulkan with HLSL | `SPIR-V.rst` + `SPIRV-Cookbook.rst` |
| Build DXC from source | `BuildingAndTestingDXC.rst` + repo `README.md` |
| Add source-level debugging | `SourceLevelDebuggingHLSL.rst` |
| See what changed in each release | `ReleaseNotes.md` |
| Write an LLVM pass for DXC | `WritingAnLLVMPass.rst` |
| Understand LLVM IR basics | `LangRef.rst` |
