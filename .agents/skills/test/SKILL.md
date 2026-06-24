---
name: test
description: Run and write DXC tests. Use when asked to run tests, write new tests, debug test failures, understand the test infrastructure, or find the right test suite for a change (LIT, GoogleTest, TAEF, SPIR-V, HLSL, DXIL).
---

# DXC Test Skill

DXC uses a multi-layered test infrastructure inherited from LLVM and extended with HLSL/DXIL-specific suites.

## Decision Tree

| User asks about... | Action |
|---|---|
| Running tests after a change | → **Quick Commands** below |
| Writing a new HLSL→SPIR-V test | → **CodeGenSPIRV Tests** (LIT) |
| Writing a new HLSL→DXIL test | → **CodeGenDXIL Tests** (LIT) |
| Writing a unit test for SPIR-V internals | → **SPIR-V Unit Tests** (GoogleTest) |
| Running the full Clang LIT suite | `ninja check-clang` |
| SPIR-V validation tests | → **SPIR-V Unit Tests** |
| Sema / type-checking tests | → `tools/clang/test/SemaHLSL/` (LIT) |
| Driver / CLI tests | → `tools/clang/test/DXC/` (LIT) |
| Debugging a LIT test failure | → **LIT Test Debugging** |
| Debugging a TAEF test failure | → **TAEF Tests** |

---

## Quick Commands

```bash
# Build with SPIR-V tests enabled (one-time configure)
python build.py --spirv-build-tests --clean

# Run all Clang/HLSL LIT tests
ninja -C build check-clang

# Run only SPIR-V codegen LIT tests
ninja -C build check-clang-spirv-codegen
# Or directly with lit:
python utils/lit/lit.py tools/clang/test/CodeGenSPIRV

# Run only DXIL codegen LIT tests
ninja -C build check-clang-codegendxil

# Run only SemaHLSL LIT tests
ninja -C build check-clang-semahlsl

# Run SPIR-V unit tests (GoogleTest)
./build/bin/ClangSPIRVTests --spirv-test-root tools/clang/test/CodeGenSPIRV

# Run a single LIT test file
python utils/lit/lit.py tools/clang/test/CodeGenSPIRV/some-test.hlsl

# Run a single LIT test with verbose output
python utils/lit/lit.py -v tools/clang/test/CodeGenSPIRV/some-test.hlsl
```

---

## Test Frameworks

### LIT (LLVM Integrated Tester)

The primary test runner. Tests are files (`.hlsl`, `.ll`, `.test`) with embedded `// RUN:` directives. Output is verified via `FileCheck` patterns.

- **Config:** `tools/clang/test/lit.cfg` (substitutions like `%dxc`, `%dxv`, `%FileCheck`)
- **Runner:** `utils/lit/lit.py`
- **Substitutions available in tests:**
  - `%dxc` — path to the built `dxc` binary
  - `%dxv` — path to `dxv` (DXIL validator)
  - `%dxa` — path to `dxa` (DXIL assembler)
  - `%dxopt` — path to `dxopt`
  - `%dxr` — path to `dxr` (DXIL disassembler)
  - `%FileCheck` — FileCheck pattern matcher

### FileCheck

Pattern-matching utility for verifying compiler output. Used in `RUN:` lines with `| FileCheck %s`.

```hlsl
// RUN: %dxc -T ps_6_0 -E main %s | FileCheck %s

// CHECK: OpCapability Shader
// CHECK-NOT: VariablePointers
// CHECK: OpFunction
```

**Common directives:** `CHECK`, `CHECK-NOT`, `CHECK-SAME`, `CHECK-NEXT`, `CHECK-LABEL`, `CHECK-DAG`, `CHECK-COUNT`.

### GoogleTest

C++ unit tests for library-level testing. Located in `unittests/` (LLVM core) and `tools/clang/unittests/` (Clang/HLSL/SPIRV).

- **SPIR-V unit tests:** `tools/clang/unittests/SPIRV/` → `ClangSPIRVTests` executable
- **HLSL unit tests:** `tools/clang/unittests/HLSL/` → `ClangHLSLTests` (shared lib for TAEF on Windows)

### TAEF (Windows Only)

Test Authoring and Execution Framework from WDK. Runs the largest HLSL test corpus (`HLSLFileCheck/`, `CodeGenHLSL/`). Driven via `tools/clang/test/taef/lit.cfg`.

```bash
# Direct TAEF execution (Windows)
te.exe ClangHLSLTests.dll /p:HlslDataDir=tools/clang/test/HLSL
```

---

## Test Directory Layout

| Directory | Framework | Count | Description |
|-----------|-----------|-------|-------------|
| `tools/clang/test/CodeGenSPIRV/` | LIT | ~1,573 | SPIR-V backend codegen tests. `.hlsl` files with `// RUN:` + `CHECK:` |
| `tools/clang/test/CodeGenDXIL/` | LIT | ~135 | DXIL codegen tests |
| `tools/clang/test/SemaHLSL/` | LIT | ~261 | HLSL semantic analysis (type checking, attributes, intrinsics) |
| `tools/clang/test/DXC/` | LIT | ~153 | DXC driver/CLI option tests |
| `tools/clang/test/LitDXILValidation/` | LIT | ~35 | DXIL validation tests |
| `tools/clang/test/HLSLFileCheckLit/` | LIT | varies | Lit-native subset of HLSL filecheck tests |
| `tools/clang/test/HLSLFileCheck/` | TAEF | ~2,210 | Largest HLSL corpus. Hidden from LIT; run via TAEF. |
| `tools/clang/test/CodeGenHLSL/` | TAEF | varies | HLSL codegen tests. Hidden from LIT. |
| `tools/clang/unittests/SPIRV/` | GoogleTest | 9 files | SPIR-V library unit tests (types, constants, blocks) |
| `tools/clang/unittests/HLSL/` | GoogleTest | ~20 files | HLSL library unit tests |
| `unittests/` | GoogleTest | varies | LLVM core unit tests (ADT, Support, IR, Analysis) |

---

## LIT Test Anatomy

A typical SPIR-V codegen test (`tools/clang/test/CodeGenSPIRV/`):

```hlsl
// RUN: %dxc -T cs_6_9 -E main -spirv -fspv-target-env=vulkan1.3 -HV 2021 %s | FileCheck %s

// CHECK: OpCapability Shader
// CHECK: OpMemoryModel Logical GLSL450
// CHECK: OpEntryPoint GLCompute %main "main"

RWStructuredBuffer<float> buf : register(u0);

[numthreads(64, 1, 1)]
void main() {
  // CHECK: OpStore
  buf[0] = 1.0;
}
```

### Key Conventions

1. **First line is always `// RUN:`** — specifies how to compile and what to check.
2. **`%s`** is replaced by LIT with the test file path.
3. **`| FileCheck %s`** pipes stdout through FileCheck, using the same file for CHECK patterns.
4. **CHECK lines** can appear anywhere in the file — before, within, or after HLSL code.
5. **SPIR-V tests** typically use `-fspv-target-env=vulkan1.3` and `-HV 2021`.
6. **SM 6.9+ features** (cooperative vectors, long vectors) require `-T cs_6_9` or similar.

### Features (Conditional Tests)

Tests can be gated on available features defined in `lit.cfg`:

```hlsl
// REQUIRES: spirv
// REQUIRES: dxil-1-8
// UNSUPPORTED: system-windows
```

Active DXC features: `spirv`, `metal`, `dxil-1-{0..8}`, `system-windows`, `system-darwin`, `asserts`, `asan`, `ubsan`.

---

## GoogleTest Unit Test Anatomy

Example SPIR-V unit test:

```cpp
#include "LibTestFixture.h"
namespace {
using clang::spirv::LibTest;
using ::testing::ContainsRegex;

TEST_F(LibTest, SourceCodeWithoutFilePath) {
  const std::string command(R"(// RUN: %dxc -T ps_6_0 -E PSMain)");
  const std::string code = command + R"(
float4 PSMain(float4 color : COLOR) : SV_TARGET { return color; }
)";
  std::string spirv = compileCodeAndGetSpirvAsm(code);
  EXPECT_THAT(spirv, ContainsRegex("%PSMain = OpFunction"));
}
} // namespace
```

**Key test fixtures:**
- `LibTest` (`LibTestFixture.h`) — Compiles HLSL to SPIR-V and returns disassembly for assertions.
- `compileCodeAndGetSpirvAsm()` — Takes HLSL string (first line must be `// RUN:`) and returns SPIR-V assembly.

---

## Configuring for Tests

Tests are **OFF by default** in `build.py`. To enable:

```bash
# Full test configuration
python build.py --spirv-build-tests --clean
```

The `PredefinedParams.cmake` cache sets:
- `HLSL_INCLUDE_TESTS=ON`
- `SPIRV_BUILD_TESTS=ON`

`build.py` overrides all test flags to `OFF` unless `--spirv-build-tests` is passed (which only sets `SPIRV_BUILD_TESTS=ON`).

### CMake flags for manual configuration:

| Flag | Purpose |
|------|---------|
| `HLSL_INCLUDE_TESTS` | HLSL-specific TAEF tests |
| `SPIRV_BUILD_TESTS` | SPIR-V unit tests (`ClangSPIRVTests`) |
| `CLANG_INCLUDE_TESTS` | Clang LIT test suite |
| `LLVM_INCLUDE_TESTS` | LLVM core tests |

---

## LIT Test Debugging

```bash
# Run a single failing test with verbose output
python utils/lit/lit.py -v tools/clang/test/CodeGenSPIRV/failing-test.hlsl

# Show exact command executed
python utils/lit/lit.py -a tools/clang/test/CodeGenSPIRV/failing-test.hlsl

# Run and don't delete temporary files
python utils/lit/lit.py --no-cleanup tools/clang/test/CodeGenSPIRV/failing-test.hlsl

# Manually reproduce the RUN command
D:\DirectXShaderCompiler\build\bin\dxc.exe -T cs_6_9 -E main -spirv test.hlsl | FileCheck test.hlsl
```

---

## Writing a New Test

### For a SPIR-V codegen change:

1. Create `tools/clang/test/CodeGenSPIRV/<feature>.hlsl`
2. Write the `// RUN:` line with appropriate dxc flags
3. Add `// CHECK:` patterns for the SPIR-V output you expect
4. Run: `python utils/lit/lit.py tools/clang/test/CodeGenSPIRV/<feature>.hlsl`

### For a SPIR-V library change:

1. Add a `TEST_F(LibTest, ...)` in `tools/clang/unittests/SPIRV/CodeGenSpirvTest.cpp` (or a new file)
2. Build with `--spirv-build-tests`
3. Run: `./build/bin/ClangSPIRVTests`

### For a SemaHLSL change:

1. Create `tools/clang/test/SemaHLSL/<feature>.hlsl`
2. Write `// RUN:` + `// CHECK:` for expected diagnostics/errors
3. Run: `python utils/lit/lit.py tools/clang/test/SemaHLSL/<feature>.hlsl`

---

## Test Data Directory

SPIR-V unit tests reference input files from `tools/clang/test/CodeGenSPIRV/` via:

```cpp
// Set via --spirv-test-root flag or SPIRV_TEST_DATA_DIR macro
clang::spirv::testOptions::inputDataDir
```

---

## Common Patterns

**"I changed LowerTypeVisitor.cpp, what tests should I run?"**
```bash
# LIT codegen tests
python utils/lit/lit.py tools/clang/test/CodeGenSPIRV
# SPIR-V unit tests
./build/bin/ClangSPIRVTests --spirv-test-root tools/clang/test/CodeGenSPIRV
```

**"I changed CapabilityVisitor.cpp, what tests?"**
```bash
python utils/lit/lit.py tools/clang/test/CodeGenSPIRV
# Focus on capability-related tests
python utils/lit/lit.py tools/clang/test/CodeGenSPIRV | grep -i capab
```

**"Run all tests after a change"**
```bash
ninja -C build check-clang                   # All LIT tests
./build/bin/ClangSPIRVTests                  # SPIR-V unit tests
```

**Quick smoke-test a single HLSL file without LIT:**
```bash
./build/bin/dxc.exe -T ps_6_0 -E main -spirv test.hlsl
```
