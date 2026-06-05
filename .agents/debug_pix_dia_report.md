# Debug, PIX & DIA Analysis

## Overview

This report analyzes five key directories in the DirectX Shader Compiler (DXC) project that relate to debugging, PIX instrumentation, DIA (Debug Interface Access), compression, and debug information handling. These libraries form the backbone of DXC's shader debugging and profiling capabilities.

---

## 1. DxilDia (`lib/DxilDia/`)

### Purpose
The DxilDia library implements the Microsoft Debug Interface Access (DIA) API for DXIL modules. It allows debugging tools (primarily PIX) to inspect HLSL shader debug metadata, source locations, symbols, variables, and types embedded in compiled DXIL shaders.

### Directory Structure
- **45 files total** (no subdirectories)
- Mix of headers (`.h`) and implementation files (`.cpp`)
- Build files: `CMakeLists.txt`, `LLVMBuild.txt`

### Key Files and Their Purposes

| File | Purpose |
|------|---------|
| `DxilDia.h` / `DxilDia.cpp` | Core utilities: COM error handling (`ENotImpl()`), string conversion (`StringRefToBSTR`) |
| `DxilDiaDataSource.h` / `.cpp` | Implements `IDiaDataSource` — entry point for loading DXIL/PDB data from streams. Parses DxilContainer or raw bitcode, creates LLVM module, and initializes debug info finder |
| `DxilDiaSession.h` / `.cpp` | Implements `IDiaSession` and `IDxcPixDxilDebugInfoFactory` — central session object holding the LLVM module, DxilModule, instruction RVA maps, line info, and symbol manager |
| `DxilDiaSymbolManager.h` / `.cpp` | Manages DIA symbols for the DXIL module. Maps LLVM `DIScope` objects to symbol IDs, tracks live ranges, parent-child relationships |
| `DxilDiaTable.h` / `.cpp` | Base template (`TableBase`) for all DIA tables (Symbols, SourceFiles, LineNumbers, Sections, etc.) |
| `DxilDiaTableSymbols.h` / `.cpp` | Implements `IDiaSymbol` interface for HLSL symbols (variables, functions, types) |
| `DxilDiaTableLineNumbers.h` / `.cpp` | Maps LLVM instructions to source line/column information via `IDiaLineNumber` |
| `DxilDiaTableSourceFiles.h` / `.cpp` | Enumerates source files referenced in debug metadata |
| `DxilDiaTableInjectedSources.h` / `.cpp` | Handles injected source code (e.g., from `#line` directives or embedded sources) |
| `DxilDiaTableFrameData.h` / `.cpp` | Stack frame data for debugging |
| `DxilDiaTableSections.h` / `.cpp` | Section table implementation |
| `DxilDiaTableSegmentMap.h` / `.cpp` | Segment map table |
| `DxilDiaTableInputAssemblyFile.h` / `.cpp` | Input assembly file table |
| `DxilDiaEnumTables.h` / `.cpp` | Enumerator over all DIA tables |
| `DxcPixBase.h` | Base utilities for PIX COM object creation (`NewDxcPixDxilDebugInfoObjectOrThrow`) |
| `DxcPixEntrypoints.cpp` | **Critical entrypoint wrapper** — wraps all PIX API calls with exception handling, parameter validation (`InParam`/`OutParam`/`CheckNotNull`), and COM lifecycle management. Defines `SetupAndRun` which is the execution environment for all PIX requests |
| `DxcPixDxilDebugInfo.h` / `.cpp` | Implements `IDxcPixDxilDebugInfo` — main PIX debug info interface: live variables at instruction offsets, function names, stack depth, source location mapping |
| `DxcPixLiveVariables.h` / `.cpp` | Maps instructions to sets of live HLSL variables. Uses `VariableInfo` to track DIVariable locations (DXIL alloca registers) |
| `DxcPixLiveVariables_FragmentIterator.h` / `.cpp` | Iterates over variable fragments for complex types (structs, arrays) |
| `DxcPixTypes.h` / `.cpp` | Implements PIX type inspection: `IDxcPixConstType`, `IDxcPixTypedefType`, `IDxcPixScalarType`, `IDxcPixArrayType`, `IDxcPixStructType`, `IDxcPixStructField` — wraps LLVM `DIType` metadata |
| `DxcPixVariables.h` / `.cpp` | Implements `IDxcPixVariable` — exposes HLSL variable names, types, and storage locations |
| `DxcPixDxilStorage.h` / `.cpp` | Implements `IDxcPixDxilStorage` — access to DXIL register storage for variable values |
| `DxcPixCompilationInfo.h` / `.cpp` | Retrieves compilation metadata: entry point, target profile, macro definitions, arguments, source files |

### Main Classes and Responsibilities

| Class | Interface | Responsibility |
|-------|-----------|---------------|
| `dxil_dia::DataSource` | `IDiaDataSource` | Loads DXIL containers or bitcode from `IStream`, parses LLVM IR, initializes debug metadata |
| `dxil_dia::Session` | `IDiaSession`, `IDxcPixDxilDebugInfoFactory` | Owns LLVM module/context, maintains instruction-to-RVA mapping, line number tables, creates PIX debug info objects |
| `dxil_dia::SymbolManager` | (internal) | Factory pattern for creating `Symbol` objects from LLVM debug metadata. Tracks scope-to-ID mapping, live ranges, parent-child hierarchies |
| `dxil_dia::Symbol` | `IDiaSymbol` | Represents a single debug symbol (variable, function, compiland). Exposes ~100 DIA properties (name, type, location, etc.) |
| `dxil_debug_info::DxcPixDxilDebugInfo` | `IDxcPixDxilDebugInfo` | Primary PIX interface: query live variables, check if variable is in register, get function name, map source<->instruction offsets |
| `dxil_debug_info::LiveVariables` | (internal) | Computes which HLSL variables are live at each DXIL instruction by analyzing `dbg.declare`/`dbg.value` intrinsics |
| `dxil_debug_info::DxcPixDxilInstructionOffsets` | `IDxcPixDxilInstructionOffsets` | List of instruction offsets matching a source location |
| `dxil_debug_info::DxcPixDxilSourceLocations` | `IDxcPixDxilSourceLocations` | Source file/line/column for a given instruction offset |

---

## 2. DxilPIXPasses (`lib/DxilPIXPasses/`)

### Purpose
A collection of LLVM module/function passes that instrument DXIL shaders to enable debugging, profiling, and analysis by Microsoft's PIX (Performance Investigator for Xbox/DirectX) tool.

### Directory Structure
- **20 files total** (no subdirectories)
- Build files: `CMakeLists.txt`, `LLVMBuild.txt`

### Key Files and Their Purposes

| File | Purpose |
|------|---------|
| `DxilPIXPasses.cpp` | Pass registry setup (`SetupRegistryPassForPIX`) — registers all PIX passes with LLVM's pass manager |
| `PixPassHelpers.h` / `.cpp` | **Shared utilities** for all PIX passes: UAV creation, handle generation, entry function discovery, struct expansion, root signature modification, dynamic resource indexing iteration |
| `DxilAnnotateWithVirtualRegister.cpp` | Annotates LLVM instructions with virtual register numbers used by PIX to track values during debugging |
| `DxilDebugInstrumentation.cpp` | **Core shader debugging pass** — adds UAV-based trace instrumentation to capture shader execution history. Writes thread traces to a UAV for post-mortem debugging |
| `DxilDebugBreakInstrumentation.cpp` | Adds instrumentation to support debug breakpoints in shaders |
| `DxilAddPixelHitInstrumentation.cpp` | Pixel shader instrumentation: counts pixel hits and costs by writing to a UAV |
| `DxilShaderAccessTracking.cpp` | Tracks resource access patterns (reads/writes to textures, buffers, UAVs) for PIX performance analysis |
| `DxilOutputColorBecomesConstant.cpp` | Replaces shader output colors with constants (used for pixel isolation in PIX) |
| `DxilReduceMSAAToSingleSample.cpp` | Converts MSAA rendering to single-sample for simplified debugging |
| `DxilRemoveDiscards.cpp` | Removes `discard` instructions so PIX can debug all pixels |
| `DxilForceEarlyZ.cpp` | Forces early depth/stencil testing |
| `DxilPIXVirtualRegisters.cpp` | Functions for reading/writing virtual register metadata on DXIL instructions |
| `DxilNonUniformResourceIndexInstrumentation.cpp` | Instruments non-uniform resource index usage |
| `DxilPIXAddTidToAmplificationShaderPayload.cpp` | Adds thread ID to amplification shader payload for mesh shader debugging |
| `DxilPIXDXRInvocationsLog.cpp` | Logs DXR (ray tracing) shader invocations for PIX |
| `DxilPIXMeshShaderOutputInstrumentation.cpp` | Instruments mesh shader output for debugging |
| `DxilDbgValueToDbgDeclare.cpp` | Converts `llvm.dbg.value` to `llvm.dbg.declare` to improve debug info stability |

### Main Classes and Responsibilities

| Class/Function | Responsibility |
|----------------|---------------|
| `PixPassHelpers` namespace | Shared infrastructure: creates global UAVs in reserved register space (-2), generates DXIL resource handles, extends root signatures, finds entry functions, expands struct types for payload instrumentation |
| `DxilAnnotateWithVirtualRegister` pass | Assigns unique virtual register IDs to allocas and instructions so PIX can correlate DXIL registers with HLSL variables |
| `DxilDebugInstrumentation` pass | Most complex pass. Inserts UAV write instructions at basic block boundaries to record execution trace. Supports thread-of-interest filtering via SV_Position, thread ID, etc. |
| `DxilShaderAccessTracking` pass | Instruments every resource access (texture sample, buffer load, UAV write) to record which resources were accessed and how |
| `DxilAddPixelHitInstrumentation` pass | Pixel-shader-specific: records which pixels were executed and execution cost |

---

## 3. DxrFallback (`lib/DxrFallback/`)

### Purpose
The DXR Fallback Compiler transforms DXR (DirectX Raytracing) shader libraries into a single compute shader that can run on hardware without native DXR driver support. It is part of the D3D12 Raytracing Fallback Layer.

### Directory Structure
- **18 files total**
- Subdirectory: `runtime/` (contains `runtime.c`, `rewriteRuntime.py`, `script.cmd`)
- Build files: `CMakeLists.txt`, `LLVMBuild.txt`

### Key Files and Their Purposes

| File | Purpose |
|------|---------|
| `readme.md` | Documentation: explains the fallback compiler's purpose, build instructions, and state machine concept |
| `DxrFallbackCompiler.cpp` | Main compiler implementation. Links DXR shader libs, inlines functions, discovers called shaders, drives the state function transform |
| `StateFunctionTransform.h` / `.cpp` | **Core transformation** — splits functions into state machine substates at continuation points (TraceRay, CallShader). Manages stack frames for live values, arguments, return addresses, payload, and attributes |
| `LiveValues.h` / `.cpp` | Liveness analysis: computes which LLVM values are live across continuation points so they can be spilled to the runtime stack |
| `FunctionBuilder.h` | Fluent API for creating LLVM functions with typed arguments |
| `LLVMUtils.h` / `.cpp` | LLVM utility functions: find call sites, create functions, load/save modules, dump CFG |
| `Reducibility.h` / `.cpp` | Graph reducibility analysis for control flow |
| `runtime.h` / `runtime/runtime.c` | Runtime data structures and functions used by the generated compute shader (stack manipulation, trace frame push/pop) |
| `runtime/rewriteRuntime.py` | Python script to patch runtime.h from LLVM 3.7 bitcode |

### Main Classes and Responsibilities

| Class | Responsibility |
|-------|---------------|
| `DxrFallbackCompiler` | Orchestrates the entire fallback compilation: takes DXR shader names, max attribute size, stack size; runs state function transformation; outputs state IDs and stack sizes |
| `StateFunctionTransform` | Transforms a single LLVM function into multiple "substate" functions. At each call to another candidate function (e.g., `TraceRay`), splits the function and replaces the call with a state transition. Manages stack allocation for live values, arguments, return state IDs, payload, and raytracing attributes |
| `LiveValues` | Computes liveness at specified instructions (call sites, returns). Used by `StateFunctionTransform` to determine what values must be saved/restored across state transitions |
| `FunctionBuilder` | Helper for constructing LLVM `Function` objects with a fluent API (`voidTy().i32().floatPtr().build()`) |

### State Function Transformation Concept

The fallback compiler views GPU execution as a **state machine**:
- Each shader function is split into substates at `TraceRay` and `CallShader` calls
- Instead of recursive calls, the shader returns a "next state ID"
- Live values are spilled to a software-managed stack
- The runtime (`runtime.c`) manages stack frames, payload, and attribute memory

---

## 4. DxilCompression (`lib/DxilCompression/`)

### Purpose
Simple zlib compression/decompression wrapper for DXIL data. Used to compress shader debug info or other DXIL payloads.

### Directory Structure
- **6 files total** (no subdirectories)

### Key Files and Their Purposes

| File | Purpose |
|------|---------|
| `DxilCompression.cpp` | Implements `hlsl::ZlibCompress` and `hlsl::ZlibDecompress` using a custom `Zlib` RAII wrapper around miniz |
| `miniz.c` / `miniz.h` | Single-file zlib replacement library (public domain) |
| `LICENSE.TXT` | License for miniz |

### Main Classes and Responsibilities

| Class/Function | Responsibility |
|----------------|---------------|
| `Zlib` (internal RAII class) | Wraps miniz inflate/deflate streams. Uses custom allocators backed by `IMalloc` for COM-compatible memory management |
| `hlsl::ZlibCompress` | Compresses data using deflate with `Z_DEFAULT_COMPRESSION`. Uses a callback to allocate output buffer |
| `hlsl::ZlibDecompress` | Decompresses zlib-compressed data in a single call |
| `hlsl::ZlibResult` | Error code enum: `Success`, `OutOfMemory`, `InvalidData` |

---

## 5. DebugInfo (`lib/DebugInfo/`)

### Purpose
LLVM's standard debug information libraries. In DXC, these are used for parsing and generating DWARF and PDB debug information. The DWARF subsystem is used for Linux/Clang-style debug info; the PDB/DIA subsystem provides Windows-style debug info access.

### Directory Structure
- **74 files total** across two subdirectories:
  - `DWARF/` — 22 files
  - `PDB/` — 48 files (including `DIA/` subdirectory with 8 files)

### Key Files and Their Purposes

#### DWARF Subsystem (`lib/DebugInfo/DWARF/`)

| File | Purpose |
|------|---------|
| `DWARFContext.cpp` | Main entry point for DWARF debug info parsing. Coordinates parsing of abbreviations, line tables, aranges, frames, info entries |
| `DWARFCompileUnit.cpp` / `DWARFUnit.cpp` | Parses DWARF compilation units and type units |
| `DWARFDebugLine.cpp` | Parses `.debug_line` section — source line number mappings |
| `DWARFDebugLoc.cpp` | Parses `.debug_loc` section — location lists for variables |
| `DWARFDebugFrame.cpp` | Parses `.debug_frame` / `.eh_frame` — call frame information |
| `DWARFDebugInfoEntry.cpp` | Represents a single DWARF DIE (Debug Information Entry) |
| `DWARFDebugAbbrev.cpp` | Parses abbreviation tables that define DIE structures |
| `DWARFAcceleratorTable.cpp` | Parses `.debug_pubnames` / `.debug_pubtypes` for fast symbol lookup |
| `DWARFFormValue.cpp` | Decodes DWARF attribute form values (addresses, strings, blocks, etc.) |
| `SyntaxHighlighting.cpp` / `.h` | Syntax highlighting for DWARF dumps |

#### PDB Subsystem (`lib/DebugInfo/PDB/`)

| File | Purpose |
|------|---------|
| `PDB.cpp` | Factory functions `loadDataForPDB` and `loadDataForEXE` — creates DIA sessions |
| `PDBContext.cpp` | Context object for PDB debug info (line info, symbol lookup) |
| `PDBSymbol.cpp` / `PDBSymbol*.cpp` | Implements `PDBSymbol` hierarchy — wrappers for DIA symbols (functions, data, types, compilands, etc.) |
| `PDBSymDumper.cpp` | Symbol dumper for debugging PDB contents |
| `PDBInterfaceAnchors.cpp` | Ensures vtables are emitted in the library |
| `IPDBSourceFile.cpp` | Source file representation |

#### DIA Subsystem (`lib/DebugInfo/PDB/DIA/`)

| File | Purpose |
|------|---------|
| `DIASession.cpp` / `.h` | Wraps Microsoft DIA `IDiaSession` in LLVM's `IPDBSession` interface |
| `DIAEnumDebugStreams.cpp` | Enumerates DIA debug streams |
| `DIAEnumLineNumbers.cpp` | Enumerates DIA line numbers |
| `DIAEnumSourceFiles.cpp` | Enumerates DIA source files |
| `DIAEnumSymbols.cpp` | Enumerates DIA symbols — wraps `IDiaEnumSymbols` into LLVM's `IPDBEnumSymbols` |
| `DIARawSymbol.cpp` | Wraps `IDiaSymbol` into LLVM's `IPDBRawSymbol` |
| `DIASourceFile.cpp` | Wraps `IDiaSourceFile` |
| `DIALineNumber.cpp` | Wraps `IDiaLineNumber` |

### Main Classes and Responsibilities

| Class | Responsibility |
|-------|---------------|
| `llvm::DWARFContext` | Parses and provides access to all DWARF debug sections in an object file |
| `llvm::DWARFCompileUnit` | Represents a single DWARF compilation unit |
| `llvm::DWARFDebugLine::LineTable` | Maps code addresses to source file/line/column |
| `llvm::DWARFDebugInfoEntry` | Represents one DWARF DIE with attributes |
| `llvm::pdb::IPDBSession` | Abstract interface for PDB sessions |
| `llvm::pdb::DIASession` | Concrete implementation using Microsoft's DIA SDK (`msdia*.dll`) |
| `llvm::pdb::PDBSymbol` | Base class for typed PDB symbol wrappers (`PDBSymbolFunc`, `PDBSymbolData`, `PDBSymbolTypeUDT`, etc.) |
| `llvm::pdb::DIAEnumSymbols` | Adapts `IDiaEnumSymbols` to LLVM's generic enumerator interface |
| `llvm::pdb::DIARawSymbol` | Adapts `IDiaSymbol` to LLVM's `IPDBRawSymbol` interface |

---

## Key Files and Their Purposes

### Cross-Cutting Critical Files

| File | Directory | Why It's Critical |
|------|-----------|-------------------|
| `DxilDiaDataSource.cpp` | `DxilDia` | Entry point for all DIA/PIX debug info — loads and parses DXIL containers |
| `DxilDiaSession.h` | `DxilDia` | Central data structure holding the LLVM module, instruction maps, and symbol manager |
| `DxcPixEntrypoints.cpp` | `DxilDia` | Every PIX API call goes through `SetupAndRun` here — handles exceptions, parameter validation, COM lifecycle |
| `DxcPixDxilDebugInfo.h` | `DxilDia` | Main PIX debug info interface — maps between HLSL source and DXIL instructions |
| `PixPassHelpers.cpp` | `DxilPIXPasses` | Shared infrastructure for all PIX passes: UAV setup, handle creation, root sig extension |
| `DxilDebugInstrumentation.cpp` | `DxilPIXPasses` | The pass that makes shader debugging possible by emitting execution traces to UAVs |
| `DxilAnnotateWithVirtualRegister.cpp` | `DxilPIXPasses` | Prepares DXIL for PIX by annotating registers |
| `StateFunctionTransform.h` | `DxrFallback` | Core algorithm for DXR fallback: transforms recursive raytracing into iterative state machine |
| `DxrFallbackCompiler.cpp` | `DxrFallback` | Orchestrates fallback compilation pipeline |
| `DxilCompression.cpp` | `DxilCompression` | Compresses/decompresses DXIL payloads (e.g., embedded debug info) |
| `DWARFContext.cpp` | `DebugInfo/DWARF` | LLVM's DWARF parser — used for ELF/object file debug info |
| `DIASession.cpp` | `DebugInfo/PDB/DIA` | Bridges LLVM's PDB abstraction to Microsoft's DIA SDK |

---

## Component Interactions

### Interaction Diagram

```
+-------------------------------------------------------------+
|                         PIX Tool                             |
|  (User wants to debug a shader at a pixel/invocation)       |
+-------------+-----------------------------------------------+
              |
              v
+-------------+-----------------------------------------------+
|  dxcompiler.dll                                             |
|                                                             |
|  +------------------+    +---------------------------+      |
|  |  DxilPIXPasses   |    |        DxilDia            |      |
|  |                  |    |                           |      |
|  |  DxilDebugInstr- |    |  +-------------------+    |      |
|  |  umentation      |--->|  | DxcPixDxilDebugInfo|    |      |
|  |  (adds UAV       |    |  | - GetLiveVariables |<---+      |
|  |   traces)        |    |  | - SourceLocations  |    |      |
|  |                  |    |  +-------------------+    |      |
|  |  DxilAnnotateWith|    |           ^               |      |
|  |  VirtualRegister |    |           |               |      |
|  |                  |    |  +--------+--------+      |      |
|  |  DxilShaderAccess|    |  | DxilDiaSession  |      |      |
|  |  Tracking        |    |  | - LLVM Module   |      |      |
|  |                  |    |  | - SymbolManager |      |      |
|  |  (other passes)  |    |  | - RVAMap        |      |      |
|  +------------------+    |  +-----------------+      |      |
|           ^              |           ^               |      |
|           |              |           |               |      |
|  +--------+--------+     |  +--------+--------+      |      |
|  |   DxilModule    |<----+  | DxilDiaDataSource|      |      |
|  |   (DXIL IR)     |        | - LoadContainer  |      |      |
|  |   (LLVM IR)     |        | - ParseBitcode   |      |      |
|  +-----------------+        +-------------------+      |      |
|           ^                                            |      |
|           |                                            |      |
|  +--------+--------+                                   |      |
|  | DebugInfo/DWARF |                                   |      |
|  | (LLVM metadata) |<----------------------------------+      |
|  +-----------------+                                         |
|                                                              |
|  +------------------+                                        |
|  | DxilCompression  | (compresses debug info payloads)       |
|  +------------------+                                        |
|                                                              |
|  +------------------+                                        |
|  | DxrFallback      | (separate pipeline for raytracing)     |
|  | (StateFunction   |                                        |
|  |  Transform)      |                                        |
|  +------------------+                                        |
+--------------------------------------------------------------+
```

### Data Flow: PIX Shader Debugging

1. **Compile Time**: `DxilPIXPasses` runs on the shader during compilation
   - `DxilAnnotateWithVirtualRegister` assigns IDs to registers
   - `DxilDebugInstrumentation` adds UAV write instructions to trace execution
   - `DxilShaderAccessTracking` records resource usage

2. **Runtime**: The instrumented shader executes on the GPU, writing trace data to a UAV

3. **Debug Time**: PIX loads the compiled shader via `DxilDia`
   - `DxilDiaDataSource` parses the DXIL container and extracts the debug module
   - `DxilDiaSession` builds instruction-to-source-line mappings
   - `DxcPixDxilDebugInfo` answers queries like "what variables are live at instruction 42?"
   - `LiveVariables` analyzes `dbg.declare`/`dbg.value` to map HLSL variables to DXIL registers

### Data Flow: DXR Fallback

1. `DxrFallbackCompiler` receives DXR shader libraries and entry point names
2. It links shaders and discovers transitive call graph
3. `StateFunctionTransform` splits each function at `TraceRay`/`CallShader` calls
4. `LiveValues` determines what must be saved across continuations
5. The compiler emits a single compute shader with state machine dispatch
6. Runtime (`runtime.c`) manages the stack, payload, and attribute memory

### DIA / PDB Bridge

- `DebugInfo/PDB/DIA` wraps Microsoft's DIA SDK (`msdia140.dll` or similar)
- This allows LLVM-based tools (and DXC) to read `.pdb` files via a cross-platform abstraction (`IPDBSession`)
- `DxilDia` does **not** use this directly — it implements its own `IDiaDataSource`/`IDiaSession` for DXIL specifically

---

## Summary

| Directory | Primary Role | Key Consumer | Lines of Code (approx) |
|-----------|-------------|--------------|------------------------|
| `lib/DxilDia` | DIA API + PIX debug info for DXIL | PIX, Visual Studio Graphics Debugger | ~8,000 |
| `lib/DxilPIXPasses` | Shader instrumentation passes | PIX (at compile time) | ~6,000 |
| `lib/DxrFallback` | DXR -> compute shader fallback | D3D12 Raytracing Fallback Layer | ~4,000 |
| `lib/DxilCompression` | zlib compression for DXIL payloads | DXIL container writer/reader | ~200 |
| `lib/DebugInfo` | DWARF/PDB debug format parsers | LLVM tools, object file analysis | ~15,000+ |

### Architecture Insights

1. **Separation of Concerns**: `DxilDia` provides read-only debug info access, while `DxilPIXPasses` modifies shaders at compile time. They share the same LLVM debug metadata format but operate at different times.

2. **COM Everywhere**: The DxilDia library is heavily COM-based (`IDiaDataSource`, `IDiaSession`, `IDiaSymbol`, `IDxcPixDxilDebugInfo`) with custom memory management via `IMalloc`. The `DxcPixEntrypoints.cpp` wrapper is essential for safe API boundaries.

3. **State Machine for Recursion**: The `DxrFallback` compiler elegantly solves the problem of recursive raytracing on non-DXR hardware by converting function calls into explicit state transitions with a software-managed stack.

4. **LLVM as Foundation**: All components build on LLVM's IR, metadata, and pass infrastructure. Debug info flows through LLVM's `DI*` metadata classes (`DILocalVariable`, `DIType`, `DISubprogram`, etc.).

5. **miniz over zlib**: `DxilCompression` uses `miniz` (a single-file public domain zlib implementation) rather than linking external zlib, keeping DXC self-contained.

---

*Report generated from analysis of DirectXShaderCompiler source tree.*
