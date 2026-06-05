# Testing Infrastructure Analysis

## Executive Overview

The DirectX Shader Compiler (DXC) project inherits LLVM/Clang's multi-layered testing infrastructure and extends it with HLSL-specific and DXIL-specific test suites. Tests are organized across three primary locations:

- **`test/`** — LLVM core regression tests (LIT-based, many disabled for HLSL)
- **`unittests/`** — C++ unit tests using GoogleTest
- **`tools/clang/test/`** — Clang/HLSL/DXIL regression tests (the most active HLSL test area)

---

## Directory: `test/` — LLVM Core Regression Tests

### Location
`D:/DirectXShaderCompiler/test`

### Description
This directory contains LLVM's upstream regression test suite, driven by **LIT** (LLVM Integrated Tester). Because DXC is a fork focused on HLSL/DXIL compilation (not general-purpose CPU codegen), **most LLVM test subdirectories are explicitly disabled** via `lit.local.cfg` files marked with "HLSL Change" comments. Only a curated subset of LLVM tests still runs.

### Subdirectories

| Subdirectory | Status | Description |
|--------------|--------|-------------|
| `Analysis/` | **Disabled** | `config.suffixes = []` — HLSL Change |
| `Assembler/` | **Disabled** | `config.suffixes = []` — HLSL Change |
| `Bitcode/` | **Disabled** | `config.unsupported = True` — HLSL Change |
| `CodeGen/` | **Disabled** | `config.suffixes = []` — HLSL Change (contains only `NVPTX/`) |
| `Feature/` | **Disabled** | `config.suffixes = []` — HLSL Change |
| `FileCheck/` | **Active** | Tests the FileCheck pattern-matching tool itself |
| `HLSL/` | **Active** | Small HLSL-specific LLVM-level tests (15 files) |
| `Instrumentation/` | **Disabled** | `config.suffixes = []` — HLSL Change |
| `Integer/` | **Partially Active** | Some big-integer tests run; others hidden |
| `Linker/` | **Disabled** | `config.suffixes = []` — HLSL Change |
| `LTO/` | **Active** | Link-Time Optimization tests (ARM/, X86/) |
| `MC/` | **Disabled** | `config.unsupported = True` — HLSL Change |
| `Object/` | **Disabled** | `config.unsupported = True` — HLSL Change |
| `Other/` | **Disabled** | `config.unsupported = True` — HLSL Change |
| `SymbolRewriter/` | **Disabled** | `config.suffixes = []` — HLSL Change |
| `TableGen/` | **Active** | TableGen parser/codegen tests |
| `Transforms/` | **Partially Active** | Mostly disabled, but `Reassociate/` is enabled for HLSL |
| `Unit/` | **Active** | GoogleTest unit test discovery config |
| `Verifier/` | **Active** | LLVM IR verifier tests |
| `YAMLParser/` | **Active** | YAML parser tests |
| `tools/` | **Partially Active** | Only `llvm-lit/` enabled; other tool tests disabled |

### Key Files

- **`test/lit.cfg`** (448 lines) — Root LIT configuration. Defines `config.suffixes = ['.ll', '.txt', '.td', '.test']` (HLSL Change, reduced from upstream). Disables many LLVM tools via substitution comments.
- **`test/CMakeLists.txt`** — Defines `check-llvm` target, test dependencies (`llvm-as`, `opt`, `FileCheck`, etc.), and `llvm-test-depends`.
- **`test/TestRunner.sh`** / **`test/Makefile.tests`** — Legacy test runner scripts.

### HLSL-Specific Content in `test/`

- `test/HLSL/opt/help.ll` — Verifies `opt -help` output contains expected options.
- `test/HLSL/passes/dxil_o0_legalize/` — DXIL O0 legalization pass tests.
- `test/HLSL/passes/dxil_remove_unstructured_loop_exits/` — Loop structurization tests.
- `test/HLSL/passes/dxilgen/` — DXIL generation pass tests.
- `test/HLSL/passes/indvars/`, `instcombine/`, `multi_dim_one_dim/`, `reassociate/` — LLVM pass tests relevant to HLSL.

### File Counts
- **~4,091** total files
- **~3,650** `.ll` files (LLVM IR assembly tests)
- **~321** `.test` files (generic LIT tests)
- Many are inactive due to HLSL-directed disabling.

---

## Directory: `unittests/` — C++ Unit Tests

### Location
`D:/DirectXShaderCompiler/unittests`

### Description
This directory contains **GoogleTest**-based C++ unit tests for LLVM/DXC libraries. The build system aggregates them into the `UnitTests` target. Several upstream LLVM unit test directories are excluded because HLSL does not use the corresponding subsystems (e.g., CPU code generation, DWARF debug info).

### Subdirectories

| Subdirectory | Framework | Status | Description |
|--------------|-----------|--------|-------------|
| `ADT/` | GoogleTest | **Active** | Abstract Data Types (SmallVector, DenseMap, StringRef, etc.) — 36+ test files |
| `Analysis/` | GoogleTest | **Active** | LLVM analysis passes (AliasAnalysis, CallGraph, CFG, etc.) |
| `AsmParser/` | GoogleTest | **Active** | LLVM assembly parser tests |
| `Bitcode/` | GoogleTest | **Active** | Bitcode reader/writer tests |
| `CodeGen/` | GoogleTest | **Active** | Limited codegen tests (DIEHash) |
| `DebugInfo/` | GoogleTest | **Active** | PDB API tests (DWARF disabled for HLSL) |
| `DxcSupport/` | GoogleTest | **Active** | **HLSL-specific**: `WinAdapterTest.cpp` — tests Windows API compatibility shim on non-Windows platforms |
| `DxilHash/` | GoogleTest | **Active** | **HLSL-specific**: `DxilHashTest.cpp` — tests DXIL container hashing |
| `IR/` | GoogleTest | **Active** | LLVM IR data structures, instructions, types, metadata, pass manager |
| `Linker/` | GoogleTest | **Active** | LLVM module linker tests |
| `MC/` | GoogleTest | **Active** | Machine Code layer tests (limited) |
| `Option/` | GoogleTest | **Active** | Command-line option parsing tests |
| `ProfileData/` | GoogleTest | **Active** | Instrumented profiling data tests |
| `Support/` | GoogleTest | **Active** | Support library tests (MemoryBuffer, raw_ostream, CommandLine, etc.) |
| `Transforms/` | GoogleTest | **Active** | IPO and Utils transform tests |

### Excluded Directories (HLSL Change)

From `unittests/CMakeLists.txt`:
- `CodeGen` — "HLSL doesn't codegen..." (commented out, but actually added back partially)
- `DebugInfo` — "HLSL doesn't generate dwarf" (partially present for PDB)
- `ExecutionEngine` — HLSL Change removed
- `LineEditor` — HLSL Change removed
- `MC` — "HLSL doesn't codegen..." (partially present)

### Key Files

- **`unittests/CMakeLists.txt`** (30 lines) — Defines `UnitTests` target and `add_llvm_unittest()` helper. Lists active subdirectories.
- **`unittests/Makefile.unittest`** — Legacy Makefile support.

### File Counts
- **131** `.cpp` test files
- **20** `CMakeLists.txt` / support files

---

## Directory: `tools/clang/test/` — Clang & HLSL Regression Tests

### Location
`D:/DirectXShaderCompiler/tools/clang/test`

### Description
This is the **most active HLSL/DXIL test area**. It contains Clang frontend tests, HLSL semantic analysis, DXIL code generation, DXC driver tests, SPIR-V codegen, and TAEF-based integration tests. The directory is driven by LIT with custom substitutions for `%dxc`, `%dxv`, and `%hlsl_headers`.

### Key Subdirectories

#### HLSL/DXIL-Specific Directories

| Subdirectory | Files | Status | Description |
|--------------|-------|--------|-------------|
| `HLSLFileCheck/` | ~2,210 | **Hidden from lit** | Main HLSL FileCheck test corpus. `lit.local.cfg` sets `config.suffixes = []` because these are tested by **TAEF** (CompilerTest, DxilContainerTest, LinkerTest). Contains `hlsl/`, `dxil/`, `validation/`, `shader_targets/`, `pix/`, `rewriter/`, `samples/`, `passes/`, etc. |
| `HLSLFileCheckLit/` | ~24 | **Active** | Lit-enabled subset of HLSLFileCheck tests. Mirrors `hlsl/` and `passes/` structure. |
| `CodeGenDXIL/` | ~135 | **Active** | DXIL code generation tests (ByteAddressBuffer, StructuredBuffer, templates, reflection, operators, literals, hlsl subdirs) |
| `CodeGenHLSL/` | ~105 | **Hidden from lit** | HLSL code generation tests. `lit.local.cfg` disables because they run under TAEF. |
| `SemaHLSL/` | ~261 | **Active** | HLSL semantic analysis tests — type checking, conversions, intrinsics, diagnostics, shader attributes, raytracing, wave operations, templates |
| `DXC/` | ~153 | **Active** | DXC compiler driver tests (`dxc` command-line tool). Tests batch compile, PSV dumping, root signatures, SPIR-V output, Metal output, disassembly, diagnostics, etc. |
| `DXILValidation/` | — | **Hidden from lit** | TAEF-driven DXIL validation tests (`DxilValidation`). Hidden by `lit.local.cfg`. |
| `LitDXILValidation/` | ~35 | **Active** | DXIL validation tests that run directly via LIT. Tests opcode validation, shader stage validation, group shared memory, wave operations, SER (Shader Execution Reordering), hit objects, etc. |
| `HLSL/` | ~6 | **Active** | Basic HLSL syntax tests (`cpp-errors.hlsl`, `system-values.hlsl`, rewriter tests) |
| `HLSLDisabled/` | — | **Active** | Tests for disabled HLSL features |
| `PIX/` | ~1 | **Active** | PIX debugging integration tests |

#### Standard Clang Directories (Partially Active)

| Subdirectory | Status | Description |
|--------------|--------|-------------|
| `CodeGenCUDA/` | **Disabled** | `config.suffixes = []` — HLSL Change |
| `CodeGenSPIRV/` | **Active** | ~1,573 files — SPIR-V code generation tests |
| `CoverageMapping/` | **Disabled** | HLSL Change |
| `Frontend/` | **Active** | Frontend driver tests |
| `Integration/` | **Disabled** | HLSL Change |
| `Lexer/` | **Active** | Lexer/tokenizer tests |
| `Parser/` | **Active** | C/C++/HLSL parser tests |
| `Preprocessor/` | **Active** | Preprocessor tests |
| `Sema/` | **Active** | C semantic analysis |
| `SemaCXX/` | **Active** | C++ semantic analysis |
| `SemaCUDA/` | **Active** | CUDA semantic analysis |
| `SemaTemplate/` | **Active** | C++ template tests |
| `TableGen/` | **Active** | Clang TableGen tests |
| `Tooling/` | **Active** | Clang tooling/libclang tests |

#### Test Runner Configurations

| Subdirectory | Description |
|--------------|-------------|
| `taef/` | LIT config for **TAEF** (Test Authoring and Execution Framework). Runs `ClangHLSLTests.dll` on Windows only. Sets `HlslDataDir` parameter. |
| `taef_exec/` | LIT config for TAEF **execution tests** (runs compiled shaders on GPU via WARP). |
| `Unit/` | LIT config for **ClangUnitTests** (GoogleTest). |

### Key Files

- **`tools/clang/test/lit.cfg`** — Clang LIT configuration. Defines `config.suffixes = ['.ll', '.hlsl', '.test']` (HLSL Change). Adds `%dxc`, `%dxv`, `%hlsl_headers` substitutions. Handles `DXC_DXIL_DLL_PATH` for external validator testing.
- **`tools/clang/test/CMakeLists.txt`** — Defines `check-clang` target, `clang-test-depends`, and DXIL backward-compatibility targets (`check-dxilcompat-dxc_2025_07_14`, etc.) that test against released DXC binaries.
- **`tools/clang/test/taef/lit.cfg`** — TAEF test runner. Only active on Windows. Invokes `te.exe ClangHLSLTests.dll` with architecture and priority filters.

### Sample Test Patterns

**HLSL FileCheck test** (`tools/clang/test/HLSLFileCheck/Readme.md`):
```hlsl
// RUN: %dxc -E main -T vs_6_0 -Zi %s | FileCheck %s
// CHECK: foo
void main() {}
```

**DXC driver test** (`tools/clang/test/DXC/basic_smoke.test`):
```
// RUN: %dxc /T ps_6_0 %S/Inputs/smoke.hlsl /Fc %t
// RUN: FileCheck --input-file=%t %s --check-prefix=FC
// FC:define void @main()
```

**SemaHLSL test** (`tools/clang/test/SemaHLSL/`):
```hlsl
// RUN: %clang_cc1 -fsyntax-only -Wno-unused-value -ffreestanding -HV 2018 -verify %s
// expected-error {{expansion is unsupported in HLSL}}
```

---

## Directory: `projects/dxilconv/test/` — DXBC to DXIL Conversion Tests

### Location
`D:/DirectXShaderCompiler/projects/dxilconv/test`

### Description
Tests for the **DXBC to DXIL converter** (dxilconv). Uses TAEF via LIT (`projects/dxilconv/test/taef/`). Tests compare converted DXIL output against `.ref` reference files.

### Structure
- `dxbc2dxil/` — Conversion test cases (`.dxbc` input, `.hlsl` source, `.ref` expected output)
- `taef/` — LIT configuration for `dxilconv-tests.dll`

---

## Test Categories and Frameworks

### 1. HLSL Tests

Tests specific to the HLSL language frontend and compiler behavior.

- **Semantic Analysis**: `tools/clang/test/SemaHLSL/` (261 files)
  - Type checking, conversions, operator overloading, intrinsics, shader attributes, raytracing diagnostics
- **Code Generation**: `tools/clang/test/CodeGenHLSL/` (105 files, TAEF), `tools/clang/test/CodeGenDXIL/` (135 files, lit)
  - Root signatures, resources, groupshared, mesh shaders, library shaders, debug info
- **FileCheck Regression**: `tools/clang/test/HLSLFileCheck/` (2,210 files, TAEF), `tools/clang/test/HLSLFileCheckLit/` (24 files, lit)
  - Full HLSL language coverage: classes, control flow, diagnostics, entry points, intrinsics, lifetimes, linker, objects, operators, payload qualifiers, preprocessor, resource binding, semantics, signatures, templates, types, workgraphs
- **DXC Driver**: `tools/clang/test/DXC/` (153 files)
  - Command-line interface, batch compilation, PSV/reflect metadata, SPIR-V/Metal output, validator selection
- **Shader Targets**: `tools/clang/test/HLSLFileCheck/shader_targets/`
  - Vertex, pixel, geometry, hull, mesh, raytracing, compute, library, node shaders

### 2. DXIL Tests

Tests for the DXIL (DirectX Intermediate Language) IR and validation.

- **DXIL CodeGen**: `tools/clang/test/CodeGenDXIL/` (135 files)
  - ByteAddressBuffer, StructuredBuffer, operators, literals, templates, reflection, passes
- **DXIL Validation (Lit)**: `tools/clang/test/LitDXILValidation/` (35 files)
  - Opcode legality, shader stage restrictions, integer width, vector validation, group shared memory, wave operations, SER validation
- **DXIL Validation (TAEF)**: `tools/clang/test/DXILValidation/` (hidden)
  - Comprehensive validator regression tests
- **DXIL Passes**: `test/HLSL/passes/dxil_*/` and `tools/clang/test/HLSLFileCheck/passes/`
  - `dxil_o0_legalize`, `dxil_remove_unstructured_loop_exits`, `dxilgen`
- **DXIL Backward Compatibility**: CMake targets `check-dxilcompat-*`
  - Tests CodeGenDXIL, DXC, and HLSLFileCheckLit against released `dxil.dll` validators

### 3. LLVM Tests

Core LLVM infrastructure tests, mostly disabled for HLSL but retaining some coverage.

- **Active**: `test/FileCheck/`, `test/TableGen/`, `test/Verifier/`, `test/Unit/`, `test/LTO/`, some `test/Transforms/`, `test/Integer/`, `test/HLSL/`
- **Disabled**: Assembler, Bitcode, CodeGen, Feature, Instrumentation, Linker, MC, Object, Other, SymbolRewriter, most Analysis
- **Framework**: LIT + FileCheck

### 4. Clang Tests

Standard Clang frontend tests (C/C++ parser, sema, codegen) retained from upstream.

- **Active**: `Lexer/`, `Parser/`, `Preprocessor/`, `Sema/`, `SemaCXX/`, `SemaTemplate/`, `Frontend/`, `Tooling/`, `TableGen/`, `CodeGenSPIRV/`
- **Disabled**: `CodeGenCUDA/`, `CoverageMapping/`, `Integration/`, `Layout/`, `VFS/`
- **Framework**: LIT + FileCheck

### 5. SPIR-V Tests

- **Location**: `tools/clang/test/CodeGenSPIRV/` (~1,573 files)
- **Description**: Extensive SPIR-V backend code generation tests for HLSL compiled to Vulkan SPIR-V

### 6. Unit Tests

- **Framework**: GoogleTest (via `gtest/gtest.h`)
- **Runner**: LIT `GoogleTest` format (`test/Unit/lit.cfg`)
- **HLSL-specific**: `DxcSupport/WinAdapterTest.cpp`, `DxilHash/DxilHashTest.cpp`
- **LLVM core**: ADT, Analysis, IR, Support, Bitcode, Linker, Option, ProfileData, Transforms, AsmParser

### 7. TAEF Tests (Windows Only)

- **Framework**: TAEF (Test Authoring and Execution Framework) via `te.exe`
- **Test DLLs**: `ClangHLSLTests.dll`, `dxilconv-tests.dll`
- **Runner**: LIT `TaefTest` format
- **Coverage**: CompilerTest, DxilContainerTest, LinkerTest, ValidationTest, DxilValidation — these drive the bulk of the ~2,210 HLSLFileCheck tests

---

## Summary

| Aspect | Details |
|--------|---------|
| **Primary Test Runner** | LIT (LLVM Integrated Tester) |
| **Pattern Matching** | FileCheck |
| **C++ Unit Testing** | GoogleTest |
| **Windows Integration** | TAEF (Test Authoring and Execution Framework) |
| **Total Test Files (approx.)** | ~9,000+ across all directories |
| **HLSL/DXIL-Specific Tests** | ~2,800+ files (SemaHLSL, CodeGenDXIL, HLSLFileCheck, HLSLFileCheckLit, DXC, LitDXILValidation, CodeGenHLSL) |
| **Most Active HLSL Suite** | `tools/clang/test/HLSLFileCheck/` (2,210 files, TAEF-driven) |
| **Lit-Enabled HLSL Suites** | `SemaHLSL/`, `CodeGenDXIL/`, `DXC/`, `LitDXILValidation/`, `HLSLFileCheckLit/` |

### Key Architectural Decisions

1. **HLSL disables most LLVM tests**: Because DXC does not target CPU architectures, most LLVM backend tests (Assembler, Bitcode, CodeGen, MC, Object) are hidden via `lit.local.cfg`.
2. **TAEF runs the bulk of HLSL tests**: The `HLSLFileCheck/` and `CodeGenHLSL/` directories are explicitly hidden from LIT because they are executed more efficiently via TAEF's batch mode against `ClangHLSLTests.dll`.
3. **Lit mirrors for cross-platform validation**: `HLSLFileCheckLit/`, `LitDXILValidation/`, and `SemaHLSL/` provide lit-native HLSL coverage for non-Windows builds.
4. **External DXIL validator testing**: CMake can download released DXC binaries and run `CodeGenDXIL`, `DXC`, and `HLSLFileCheckLit` against historical `dxil.dll` versions to ensure backward compatibility.
5. **SPIR-V is a first-class backend**: With ~1,573 tests, `CodeGenSPIRV/` is one of the largest active test directories, reflecting DXC's role as a Vulkan shading language compiler.
