# Include Headers Analysis

This report analyzes the public include directories in the DirectX Shader Compiler (DXC) project, focusing on the APIs and data structures exposed through header files.

---

## Table of Contents
1. [Directory: `include/dxc`](#directory-includedxc)
2. [Directory: `include/llvm`](#directory-includellvm)
3. [Directory: `include/llvm-c`](#directory-includellvm-c)
4. [Directory: `include/miniz`](#directory-includeminiz)
5. [Key Public APIs](#key-public-apis)
6. [Summary](#summary)

---

## Directory: `include/dxc`

This is the primary public API surface for the DirectX Shader Compiler. It contains COM-style interfaces for compilation, linking, validation, reflection, and debugging.

### Top-Level Key Headers

| Header | Description |
|--------|-------------|
| `dxcapi.h` | **Main public API** — Defines `DxcCreateInstance`, `IDxcCompiler3`, `IDxcUtils`, `IDxcBlob`, `IDxcResult`, and all core compiler interfaces. |
| `dxcapi.internal.h` | Internal/private APIs for language extensions, intrinsics, and container events. |
| `dxcerrors.h` | Defines DXC-specific exception codes (e.g., `EXCEPTION_LOAD_LIBRARY_FAILED`). |
| `dxctools.h` | Tooling interfaces: `IDxcRewriter`, `IDxcRewriter2` for HLSL rewriting. |
| `dxcisense.h` | IntelliSense components: token kinds, type kinds, diagnostics, and code-completion APIs. |
| `dxcpix.h` | PIX debugging support: `IDxcPixType`, `IDxcPixDxilStorage`, `IDxcPixStructType`, etc. |
| `dxcdxrfallbackcompiler.h` | DXR fallback compiler interface. |
| `HlslIntrinsicOp.h` | Auto-generated enumeration of all HLSL intrinsic opcodes (`hlsl::IntrinsicOp`). |
| `WinAdapter.h` | Cross-platform adapter for Windows/COM types on non-Windows platforms. |

### Subdirectory: `include/dxc/DXIL` (30 headers)

The DXIL directory defines the **DirectX Intermediate Language** representation — the LLVM-based IR used by shaders.

| Header | Description |
|--------|-------------|
| `DXIL.h` | Top-level DXIL definitions. |
| `DxilModule.h` | Core class `hlsl::DxilModule` — manipulates DXIL of a shader, similar to `llvm::Module`. |
| `DxilConstants.h` | Essential DXIL constants: version (`kDxilMajor` = 1, `kDxilMinor` = 10), shader flags, limits. |
| `DxilOperations.h` | `hlsl::OP` class — interacts with DXIL operation tables, overloads, and opcode classes. |
| `DxilShaderModel.h` | Shader model representation and version checks. |
| `DxilSignature.h` | Input/output signature management. |
| `DxilSignatureElement.h` | Individual signature element definitions. |
| `DxilResource.h` | SRV/UAV/CBuffer resource definitions. |
| `DxilSampler.h` | Sampler state definitions. |
| `DxilCBuffer.h` | Constant buffer definitions. |
| `DxilTypeSystem.h` | DXIL type system helpers. |
| `DxilMetadataHelper.h` | Metadata serialization/deserialization helpers. |
| `DxilShaderFlags.h` | Shader capability flags collection. |
| `DxilSubobject.h` | Pipeline state subobjects (root signature, state objects). |
| `DxilInstructions.h` | DXIL instruction definitions and properties. |
| `DxilFunctionProps.h` | Function properties for shader entry points. |
| `DxilEntryProps.h` | Entry-point properties container. |
| `DxilResourceBinding.h` | Resource binding metadata. |
| `DxilResourceProperties.h` | Resource property descriptors. |
| `DxilSemantic.h` | HLSL semantic definitions (SV_Position, etc.). |
| `DxilSigPoint.h` | Signature point enumeration (vertex input, pixel output, etc.). |
| `DxilCompType.h` | Component type definitions (float, int, etc.). |
| `DxilInterpolationMode.h` | Interpolation mode enumeration. |
| `DxilCounters.h` | Performance counter metadata. |
| `DxilPDB.h` | PDB (debug info) container support. |
| `DxilUtil.h` | General DXIL utilities. |
| `DxilLinker.h` | DXIL module linking interface. |
| `DxilGenerationPass.h` | DXIL generation LLVM pass. |
| `DxilExportMap.h` | Shader export mapping. |
| `DxilConvergentName.h` | Convergent execution naming. |

### Subdirectory: `include/dxc/HLSL` (25 headers)

High-Level Shader Language (HLSL) specific compiler passes and helpers.

| Header | Description |
|--------|-------------|
| `HLModule.h` | High-level DX IR module (`hlsl::HLModule`). |
| `HLOperations.h` | HLSL operation definitions. |
| `HLOperationLower.h` | Lowering HLSL ops to DXIL. |
| `HLResource.h` | HLSL resource representation. |
| `HLMatrixType.h` / `HLMatrixLowerPass.h` / `HLMatrixLowerHelper.h` | HLSL matrix type lowering passes. |
| `HLLowerUDT.h` | User-defined type lowering. |
| `HLSLExtensionsCodegenHelper.h` | Extension codegen helpers. |
| `DxilGenerationPass.h` | Pass that generates DXIL from HLDXIR. |
| `DxilLinker.h` | Linker for DXIL libraries. |
| `DxilSignatureAllocator.h` | Signature element allocation. |
| `DxilPackSignatureElement.h` | Signature packing logic. |
| `DxilSpanAllocator.h` | Span/interval allocator. |
| `DxilPoisonValues.h` | Poison value handling. |
| `ComputeViewIdState.h` | ViewID dependency computation. |
| `ControlDependence.h` | Control dependence analysis. |
| `ViewIDPipelineValidation.inl` | Pipeline validation inlines. |

### Subdirectory: `include/dxc/Support` (24 headers)

Support utilities for the compiler.

| Header | Description |
|--------|-------------|
| `dxcapi.use.h` | C++ RAII wrapper for `DxcCreateInstance`. |
| `dxcapi.impl.h` / `dxcapi.extval.h` | Implementation helpers and external validator hooks. |
| `HLSLOptions.h` / `HLSLOptions.td` | Command-line option definitions. |
| `ErrorCodes.h` | DXC error/result codes. |
| `Global.h` | Global macros and definitions. |
| `DxcLangExtensionsHelper.h` / `DxcLangExtensionsCommonHelper.h` | Language extension helpers. |
| `SPIRVOptions.h` | SPIR-V backend options. |
| `FileIOHelper.h` | File I/O utilities. |
| `WinIncludes.h` / `WinFunctions.h` | Windows portability. |
| `D3DReflection.h` / `d3dx12.h` | D3D reflection helpers and D3D12 utility. |

---

## Directory: `include/llvm`

This directory contains the **LLVM compiler infrastructure** headers used by DXC. DXC is based on LLVM 3.7 with extensive HLSL/DXIL modifications.

### Top-Level Key Headers

| Header | Description |
|--------|-------------|
| `Pass.h` | Base class for all LLVM optimization and analysis passes. |
| `PassRegistry.h` | Pass registration infrastructure. |
| `PassSupport.h` | Macros for defining passes. |
| `PassAnalysisSupport.h` | Analysis usage support. |
| `InitializePasses.h` | Pass initialization declarations. |
| `LinkAllIR.h` / `LinkAllPasses.h` | Force-link all IR and pass symbols. |

### Subdirectory: `include/llvm/IR` (88 headers)

The core **LLVM Intermediate Representation** definitions.

| Header | Description |
|--------|-------------|
| `Module.h` | `llvm::Module` — top-level container for global data, functions, and globals. Contains HLSL-specific forward declarations for `hlsl::DxilModule` and `hlsl::HLModule`. |
| `Function.h` | `llvm::Function` — represents a single function/procedure in LLVM IR. |
| `Value.h` | `llvm::Value` — base class of all computed values in LLVM IR. |
| `Type.h` | `llvm::Type` — type system (Void, Half, Float, Double, Integer, Function, Struct, Array, Pointer, Vector). |
| `Instruction.h` | `llvm::Instruction` — base class for all IR instructions. |
| `Instructions.h` | Concrete instruction subclasses: `AllocaInst`, `LoadInst`, `StoreInst`, `CallInst`, `ReturnInst`, branches, etc. |
| `InstrTypes.h` | Common instruction type utilities. |
| `BasicBlock.h` | `llvm::BasicBlock` — a list of instructions executed sequentially. |
| `Argument.h` | `llvm::Argument` — formal arguments of a function. |
| `Constant.h` / `Constants.h` | Constant values (`ConstantInt`, `ConstantFP`, `ConstantArray`, etc.). |
| `DerivedTypes.h` | Derived type classes (`FunctionType`, `StructType`, `ArrayType`, `PointerType`, `VectorType`). |
| `IRBuilder.h` | `llvm::IRBuilder` — convenient API for creating LLVM instructions. |
| `LLVMContext.h` | `llvm::LLVMContext` — owns global LLVM state and type uniquing. |
| `Metadata.h` / `DebugInfoMetadata.h` | Metadata and debug info nodes. |
| `DIBuilder.h` | Builder for debug info metadata. |
| `Attributes.h` | Function/parameter attributes. |
| `CallingConv.h` | Calling convention definitions. |
| `Use.h` / `User.h` | Use-chain tracking (def-use chains). |
| `GlobalVariable.h` / `GlobalObject.h` / `GlobalValue.h` | Global variable and value classes. |
| `InlineAsm.h` | Inline assembly representation. |
| `IntrinsicInst.h` / `Intrinsics.h` | LLVM intrinsic instructions and enumerations. |
| `Verifier.h` | IR verifier. |
| `PatternMatch.h` | Pattern matching helpers for IR transformations. |
| `Dominators.h` | Dominator tree analysis. |
| `Comdat.h` | COMDAT section support. |
| `DataLayout.h` | Target data layout (type sizes, alignments). |
| `Mangler.h` | Name mangling. |
| `AssemblyAnnotationWriter.h` | Annotation writer for textual IR. |
| `IRPrintingPasses.h` | Passes to print IR. |
| `LegacyPassManager.h` / `PassManager.h` | Pass manager infrastructure. |
| `AutoUpgrade.h` | Automatic IR upgrade for older bitcode. |
| `GetElementPtrTypeIterator.h` | Type iteration for GEP instructions. |

### Subdirectory: `include/llvm/Bitcode` (6 headers)

| Header | Description |
|--------|-------------|
| `ReaderWriter.h` | Read/write LLVM bitcode: `parseBitcodeFile`, `WriteBitcodeToFile`, `getLazyBitcodeModule`. |
| `BitstreamReader.h` / `BitstreamWriter.h` | Low-level bitstream primitives. |
| `LLVMBitCodes.h` / `BitCodes.h` | Bitcode format constants. |
| `BitcodeWriterPass.h` | Bitcode writer as an LLVM pass. |

### Subdirectory: `include/llvm/Support` (113 headers)

Utility and support library.

| Header | Description |
|--------|-------------|
| `MemoryBuffer.h` | Read-only memory buffer abstraction. |
| `raw_ostream.h` | Stream output abstraction. |
| `FileSystem.h` | File system operations. |
| `CommandLine.h` | Command-line parsing. |
| `ErrorHandling.h` | Error reporting and assertions. |
| `Casting.h` | LLVM-style RTTI (`isa<>`, `dyn_cast<>`, `cast<>`). |
| `DataTypes.h` | Fixed-width integer types. |
| `Compiler.h` | Compiler-specific macros and attributes. |
| `Endian.h` | Byte-order utilities. |
| `MD5.h` / `SHA1.h` | Hash algorithms. |
| `Regex.h` | Regular expressions. |
| `YAMLParser.h` / `YAMLTraits.h` | YAML parsing and serialization. |
| `SourceMgr.h` | Source location management. |
| `Timer.h` / `TimeProfiler.h` | Timing and profiling. |
| `TargetRegistry.h` | Target backend registry. |
| `DynamicLibrary.h` | Dynamic library loading. |
| `Path.h` | Path manipulation. |
| `COM.h` | COM support utilities. |

### Subdirectory: `include/llvm/Transforms` (5 headers)

| Header | Description |
|--------|-------------|
| `Scalar.h` | Scalar transformation passes (SROA, GVN, LICM, etc.). |
| `IPO.h` | Inter-procedural optimization passes (inlining, globalDCE, etc.). |
| `Instrumentation.h` | Instrumentation passes (sanitizers, profiling). |
| `Vectorize.h` | Loop and SLP vectorization. |
| `ObjCARC.h` | Objective-C automatic reference counting. |

### Other Notable LLVM Subdirectories

- `ADT/` — Abstract Data Types (SmallVector, StringRef, ArrayRef, DenseMap, etc.)
- `Analysis/` — Analysis passes (DxilValueCache, DxilSimplify, DxilConstantFolding)
- `CodeGen/` — Code generation infrastructure
- `ExecutionEngine/` — JIT / interpreter
- `MC/` — Machine code layer
- `Target/` — Target-specific backends (X86, ARM, etc.)
- `Object/` — Object file formats (ELF, COFF, Mach-O)
- `Linker/` — Module linker
- `LTO/` — Link-time optimization
- `Option/` — Option parsing library
- `ProfileData/` — Profile data formats
- `DebugInfo/` — Debug info formats (DWARF, PDB)

---

## Directory: `include/llvm-c`

This directory provides a **stable C API** wrapper around the C++ LLVM libraries.

### Key Headers (15 total)

| Header | Description |
|--------|-------------|
| `Core.h` | **Primary C API** — opaque types (`LLVMModuleRef`, `LLVMValueRef`, `LLVMTypeRef`, `LLVMContextRef`, `LLVMBuilderRef`), attribute enums, type kinds, and core IR manipulation functions. |
| `BitReader.h` | C API for reading bitcode (`LLVMParseBitcodeInContext`). |
| `BitWriter.h` | C API for writing bitcode (`LLVMWriteBitcodeToFile`). |
| `IRReader.h` | C API for reading LLVM IR text (`LLVMParseIRInContext`). |
| `Analysis.h` | C API for analysis (verifier). |
| `Disassembler.h` | C API for disassembly. |
| `ExecutionEngine.h` | C API for JIT execution engines. |
| `Linker.h` | C API for linking modules. |
| `Target.h` / `TargetMachine.h` | C API for target selection and machine code generation. |
| `Object.h` | C API for object file inspection. |
| `Support.h` | C API support types. |
| `Initialization.h` | C API for pass/target initialization. |
| `lto.h` | Link-time optimization C API. |
| `LinkTimeOptimizer.h` | Legacy LTO C API. |

---

## Directory: `include/miniz`

A minimal, self-contained zlib replacement used for compression tasks within DXC.

| Header | Description |
|--------|-------------|
| `miniz.h` | Single-header library providing deflate/inflate, zlib-subset, ZIP archive reading/writing, and PNG writing. Includes `tdefl`/`tinfl` APIs and `mz_zip_*` archive APIs. Used for PDB compression and container packaging. |

---

## Key Public APIs

### DXC Compiler API (`dxcapi.h`)

The main entry point is **`DxcCreateInstance`** (or `DxcCreateInstance2` with a custom allocator). Key interfaces:

#### Blob Interfaces
- `IDxcBlob` — Sized buffer (alias of `ID3D10Blob`/`ID3DBlob`).
- `IDxcBlobEncoding` — Blob with known text encoding.
- `IDxcBlobWide` / `IDxcBlobUtf8` — Null-terminated wide/UTF-8 string blobs.

#### Core Compilation
- `IDxcCompiler3` — Latest compiler interface:
  - `Compile(const DxcBuffer*, LPCWSTR*, UINT32, IDxcIncludeHandler*, REFIID, LPVOID*)`
  - `Disassemble(const DxcBuffer*, REFIID, LPVOID*)`
- `IDxcResult` — Multi-output result object with `GetOutput(DXC_OUT_KIND, ...)`. Output kinds include:
  - `DXC_OUT_OBJECT` — Compiled shader/library object.
  - `DXC_OUT_ERRORS` — Diagnostics text.
  - `DXC_OUT_PDB` — Debug PDB blob.
  - `DXC_OUT_DISASSEMBLY` — Disassembly text.
  - `DXC_OUT_HLSL` — Preprocessed HLSL.
  - `DXC_OUT_REFLECTION` — Reflection data (RDAT).
  - `DXC_OUT_ROOT_SIGNATURE` — Serialized root signature.
  - `DXC_OUT_SHADER_HASH` — Shader hash.

#### Utilities
- `IDxcUtils` — Utility functions:
  - `CreateBlobFromPinned`, `CreateBlob`, `LoadFile`
  - `GetBlobAsUtf8`, `GetBlobAsWide`
  - `GetDxilContainerPart` — Extract parts from DXIL container.
  - `CreateReflection` — Create `ID3D12ShaderReflection` from container.
  - `BuildArguments` — Build compiler argument lists.
  - `GetPDBContents`
- `IDxcCompilerArgs` — Argument management with `AddArguments`, `AddDefines`.
- `IDxcIncludeHandler` — Custom `#include` resolution.

#### Linking & Validation
- `IDxcLinker` — Link shader libraries:
  - `RegisterLibrary`, `Link(...)`
- `IDxcValidator` / `IDxcValidator2` — Shader validation:
  - `Validate`, `ValidateWithDebug`

#### Container Manipulation
- `IDxcContainerBuilder` — Add/remove parts from DXIL containers.
- `IDxcContainerReflection` — Inspect container parts (`GetPartCount`, `GetPartKind`, `GetPartContent`).
- `IDxcAssembler` — Assemble DXIL bitcode/LL into a DXIL container.

#### Legacy Interfaces
- `IDxcCompiler` / `IDxcCompiler2` — Deprecated; use `IDxcCompiler3`.
- `IDxcLibrary` — Deprecated; use `IDxcUtils`.
- `IDxcOperationResult` — Deprecated; use `IDxcResult`.

#### Debugging & PDB
- `IDxcPdbUtils2` — Inspect PDB or DXIL containers for source files, compiler flags, defines, and entry points.

#### PIX Debugging
- `IDxcPixType`, `IDxcPixStructType`, `IDxcPixArrayType` — Type introspection.
- `IDxcPixDxilStorage` — Access DXIL storage (registers, fields, arrays).

#### Tooling
- `IDxcRewriter2` — HLSL source rewriting (`RewriteWithOptions`, `RemoveUnusedGlobals`).

#### IntelliSense
- `IDxcIntelliSense` — Tokenization, type information, diagnostics, and code completion for HLSL.

---

### LLVM IR C++ API (`include/llvm/IR`)

DXC builds on LLVM IR to represent shaders internally before emitting DXIL.

| Class | Role |
|-------|------|
| `llvm::Module` | Top-level container for functions, globals, and metadata. |
| `llvm::Function` | A shader function or entry point. |
| `llvm::BasicBlock` | A sequence of instructions with a single entry/exit. |
| `llvm::Instruction` | Base of all IR instructions (`Add`, `Load`, `Store`, `Call`, `Ret`, etc.). |
| `llvm::Value` | Base of all values (instructions, constants, arguments, globals). |
| `llvm::Type` / `llvm::StructType` / `llvm::FunctionType` | Type system. |
| `llvm::IRBuilder<>` | Fluent API for constructing IR instructions. |
| `llvm::LLVMContext` | Owns types and metadata; required to create a `Module`. |
| `llvm::GlobalVariable` | Global constants and variables. |
| `llvm::CallInst` | Function/intrinsic calls (including DXIL ops). |
| `llvm::Metadata` / `llvm::MDNode` | Metadata nodes for shader signatures, resource bindings, and debug info. |

---

### DXIL Internal API (`include/dxc/DXIL`)

These headers are used by the compiler backends and validators.

| Class | Role |
|-------|------|
| `hlsl::DxilModule` | Encapsulates all DXIL-specific state in an `llvm::Module` (shader model, entry function, resources, signatures, subobjects). |
| `hlsl::OP` | DXIL operation manager — creates/looks up DXIL op functions (`GetOpFunc`), manages overload types (`GetResRetType`, `GetHandleType`). |
| `hlsl::HLModule` | High-level DX IR state before full DXIL lowering. |
| `hlsl::ShaderModel` | Shader model version and profile queries. |
| `hlsl::DxilSignature` / `hlsl::DxilSignatureElement` | Input/output signature management. |
| `hlsl::DxilResource` / `hlsl::DxilSampler` / `hlsl::DxilCBuffer` | Shader resource descriptions. |
| `hlsl::DxilSubobject` | Raytracing and pipeline subobjects. |
| `DXIL::OpCode` | Enumeration of all DXIL opcodes (load, store, texture sample, wave ops, etc.). |

---

### LLVM C API (`include/llvm-c`)

Stable C bindings for tooling and language bindings:
- `LLVMModuleRef`, `LLVMValueRef`, `LLVMTypeRef`, `LLVMBuilderRef`
- `LLVMContextCreate`, `LLVMModuleCreateWithNameInContext`
- `LLVMParseBitcodeInContext`, `LLVMWriteBitcodeToFile`
- `LLVMVerifyModule`, `LLVMPrintModuleToString`

---

## Summary

The DirectX Shader Compiler exposes a **rich, layered API surface**:

1. **Public COM API** (`include/dxc/dxcapi.h`) — The primary interface for applications and build tools. It provides compilation, linking, validation, reflection, and container manipulation through stable UUID-based interfaces.

2. **LLVM IR Infrastructure** (`include/llvm/IR`, `include/llvm-c`) — The compiler is built on LLVM 3.7. The IR layer defines how shaders are represented as SSA-based control-flow graphs before DXIL emission. DXC modifies LLVM with HLSL-specific passes and DXIL metadata.

3. **DXIL Representation** (`include/dxc/DXIL`) — DXIL is the shader-specific LLVM IR dialect. `DxilModule` wraps an `llvm::Module` with shader semantics (resources, signatures, shader model, subobjects). `OP` manages the DXIL operation table.

4. **HLSL Frontend** (`include/dxc/HLSL`) — High-level IR (`HLModule`) and lowering passes transform parsed HLSL into DXIL.

5. **Tooling & Debugging** (`dxctools.h`, `dxcisense.h`, `dxcpix.h`) — Source rewriting, IntelliSense, and PIX debugging interfaces extend DXC beyond simple compilation.

6. **Utilities** (`include/llvm/Support`, `include/miniz`) — Compression (miniz), memory buffers, file I/O, command-line parsing, and YAML support underpin the compiler infrastructure.

Overall, DXC's include directories reveal a compiler architecture that bridges a **public, stable COM API** with a **deep, LLVM-based compiler core** specialized for GPU shader compilation through the DXIL intermediate representation.
