# Build System & Utilities Analysis

## Overview

This report analyzes the build system configuration and utility scripts in the DirectX Shader Compiler (DXC) project, which is based on LLVM 3.7. The project uses CMake as its primary build system generator, with extensive customizations for HLSL/DXIL compilation. The `utils/` directory contains a mix of LLVM legacy tools, DXC-specific build helpers, testing infrastructure, and code generation scripts.

---

## Directory: `cmake/` - CMake Build System Configuration

The `cmake/` directory contains all CMake-related configuration files, modules, platform toolchains, and caching presets for the DXC project.

### Subdirectories

| Subdirectory | Description |
|--------------|-------------|
| `caches/` | CMake cache preset files for predefined build configurations |
| `modules/` | Reusable CMake modules (functions, macros, find scripts) |
| `platforms/` | Cross-compilation toolchain files for Android and iOS |

### Key Files

#### `cmake/README`
- Simple redirect to `docs/CMake.html` for LLVM CMake build instructions.

#### `cmake/config-ix.cmake` (~100+ lines)
- **Platform Detection**: Defines `PURE_WINDOWS` for Windows builds (excluding Cygwin).
- **Header/Library Checks**: Uses CMake's `CheckIncludeFile`, `CheckLibraryExists`, `CheckSymbolExists`, and `CheckCXXSourceCompiles` to detect system capabilities.
- **Checks for**: `dirent.h`, `dlfcn.h`, `pthread.h`, `stdint.h`, `malloc.h`, `zlib.h`, `fenv.h`, `cxxabi.h`, and many other POSIX/Unix headers.
- **Library Checks**: Tests for `libpthread` on non-Windows platforms, with Android fallback to libc.
- **Custom Macros**: `add_cxx_include()` and `check_type_exists()` helpers for compile-time type detection.

#### `cmake/caches/PredefinedParams.cmake`
- **Purpose**: Pre-configured cache variables for building DXC on *nix platforms. Passed to CMake via the `-C` flag.
- **Key Settings**:
  - `LLVM_DEFAULT_TARGET_TRIPLE="dxil-ms-dx"` — targets DXIL instead of native hardware.
  - `LLVM_ENABLE_EH=ON`, `LLVM_ENABLE_RTTI=ON` — exception handling and RTTI enabled (required for DXC).
  - `LLVM_TARGETS_TO_BUILD="None"` — no native backends; DXC is a cross-compiler.
  - `ENABLE_SPIRV_CODEGEN=ON`, `SPIRV_BUILD_TESTS=ON` — SPIR-V backend support.
  - `HLSL_INCLUDE_TESTS=ON` — enables HLSL-specific tests.
  - `LIBCLANG_BUILD_STATIC=ON` — static libclang build.
  - `LLVM_APPEND_VC_REV=ON` — appends version control revision info.
  - `LLVM_OPTIMIZED_TABLEGEN=OFF` — disables optimized tablegen (DXC doesn't need it).

#### `cmake/platforms/Android.cmake`
- Android NDK cross-compilation toolchain configuration.
- Sets `CMAKE_SYSTEM_NAME=Linux`, compilers to `clang`/`clang++`, and sysroot flags for `arm-linux-androideabi`.
- Enables PIE (`-pie`) for executable linking.

#### `cmake/platforms/iOS.cmake`
- iOS cross-compilation toolchain configuration.
- Detects `SDKROOT` via `xcodebuild`, sets `CMAKE_OSX_SYSROOT`.
- Uses `xcrun` to find `clang`, `clang++`, `ar`, and `ranlib`.
- Sets iOS minimum target version flags.

### CMake Modules (`cmake/modules/`)

| Module | Purpose |
|--------|---------|
| `AddLLVM.cmake` | Core LLVM target helpers: `llvm_update_compile_flags()`, symbol exports, library linking. Contains HLSL-specific changes for iterator debug level (`_ITERATOR_DEBUG_LEVEL=0`). |
| `AddLLVMDefinitions.cmake` | Simple wrapper macro `add_llvm_definitions()` to track compiler definitions globally. |
| `CheckAtomic.cmake` | Detects atomic operations support. |
| `ChooseMSVCCRT.cmake` | Allows user selection of MSVC C Runtime (`/MT`, `/MD`, `/MTd`, `/MDd`) per build type. |
| `CrossCompile.cmake` | Creates native/cross-target build directories; handles `llvm_create_cross_target()`. |
| `FindD3D12.cmake` | Locates Windows 10 SDK and D3D12 headers/libraries (`d3d12.h`, `dxgi1_4.h`, `d3d12.lib`, `dxgi.lib`). |
| `FindDiaSDK.cmake` | Locates the DIA SDK (`dia2.h`, `diaguids.lib`) via registry, `vswhere.exe`, or `CMAKE_GENERATOR_INSTANCE`. Supports x64, ARM, ARM64, and x86. |
| `FindTAEF.cmake` | Locates the Test Authoring and Execution Framework (TAEF) for Windows testing. Finds `te.exe`, `Wex.Common.h`, and platform-specific libraries. Supports x86, x64, ARM, and ARM64. |
| `FindSphinx.cmake`, `FindOCaml.cmake` | Find modules for documentation generation tools. |
| `GetHostTriple.cmake` | Detects host target triple for LLVM configuration. |
| `GetSVN.cmake` | Legacy Subversion support. |
| `HandleLLVMOptions.cmake` | **Critical module**: validates compiler versions (GCC >= 4.7, Clang >= 3.1, MSVC >= 2013), handles assertion flags (`_DEBUG`/`NDEBUG`), disables `-funswitch-loops` for GCC 13, manages EH/RTTI flags, and applies HLSL-specific compile flags. |
| `HandleLLVMStdlib.cmake` | Manages C++ standard library selection (libstdc++ vs libc++). |
| `HCT.cmake` | **DXC-specific**: Defines the `add_hlsl_hctgen()` CMake function for generating HLSL/DXIL source files from `hctgen.py`. Handles `clang-format`, line-ending normalization (`HLSL_AUTOCRLF`), source copying/verification, and the `HCTGen` custom target. |
| `LLVM-Config.cmake` | Public API for mapping LLVM components to library names (`llvm_map_components_to_libnames()`, `explicit_llvm_config()`). |
| `LLVMConfig.cmake.in` / `LLVMConfigVersion.cmake.in` | Templates for generating `LLVMConfig.cmake` for build and install trees. |
| `LLVMProcessSources.cmake` | Source file processing utilities. |
| `TableGen.cmake` | **TableGen integration**: `tablegen()` function runs `llvm-tblgen` on `.td` files, `add_tablegen()` creates tablegen targets, `add_public_tablegen_target()` exports dependencies. Supports cross-compilation via `LLVM_USE_HOST_TOOLS`. |
| `VersionFromVCS.cmake` | Extracts version info from Git/SVN. DXC-specific modification uses `git describe --tags --always --dirty` to produce versions like `3.7-<hash>`. |

#### `cmake/modules/CMakeLists.txt`
- Generates `LLVMConfig.cmake`, `LLVMConfigVersion.cmake`, and `LLVMExports.cmake` for both the build tree and install tree.
- Installs CMake modules and exports for downstream consumers.

---

## Directory: `utils/` - Build Utilities, Scripts, and Tools

The `utils/` directory is a large collection of LLVM legacy utilities, DXC-specific build/test tools, code generators, and helper scripts.

### Subdirectories

| Subdirectory | Description |
|--------------|-------------|
| `FileCheck/` | LLVM FileCheck testing utility (CMake + C++ source) |
| `KillTheDoctor/` | Windows utility to kill Dr. Watson crash handler (CMake + C++) |
| `PerfectShuffle/` | LLVM perfect shuffle table generator (CMake + C++) |
| `TableGen/` | **llvm-tblgen**: LLVM's domain-specific language processor for generating code from `.td` files. Contains ~30 C++ source files for emitting instructions, registers, intrinsics, disassemblers, etc. |
| `asan/` | AddressSanitizer suppression files for Linux |
| `buildit/` | GNUmakefile-based build scripts for LLVM |
| `count/` | `count` utility for testing (CMake + C source) |
| `crosstool/` | Cross-compilation snapshot scripts |
| `fpcmp/` | Floating-point comparison utility for testing |
| `git/` | Git helper scripts including code formatting (`code-format-helper.py`, `code-format-save-diff.py`) |
| `git-svn/` | Git-SVN bridge scripts (`git-svnrevert`, `git-svnup`) |
| `hct/` | **HLSL Console Tools** — DXC's primary Windows build/test automation suite |
| `jedit/` | jEdit syntax highlighting for TableGen |
| `kate/` | Kate editor syntax highlighting for LLVM |
| `lint/` | Python-based linting tools (`cpp_lint.py`, `generic_lint.py`) |
| `lit/` | **LLVM lit**: Lightweight integrated testing framework (Python) |
| `llvm-build/` | Legacy LLVM build tool wrapper |
| `llvm-lit/` | lit driver wrapper (CMake + Makefile) |
| `not/` | `not` utility for inverting test results (CMake + C++) |
| `release/` | Release engineering scripts (`export.sh`, `merge.sh`, `tag.sh`, `test-release.sh`, regression finders) |
| `testgen/` | Machine code bundling test generators |
| `textmate/` | TextMate bundle for LLVM |
| `unittest/` | Google Test integration for LLVM unit tests |
| `valgrind/` | Valgrind suppression files for Linux x86/x64 |
| `version/` | DXC version generation scripts and data |
| `yaml-bench/` | YAML benchmark utility (CMake + C++) |

### Key Files

#### DXC-Specific HCT Tools (`utils/hct/`)

| File | Description |
|------|-------------|
| `hctstart.cmd` | **Entry point**: Sets up the HLSL console environment. Sets `HLSL_SRC_DIR`, `HLSL_BLD_DIR`, `BUILD_ARCH`, installs `doskey` aliases (`hctbuild`, `hcttest`, `hctclean`, etc.), finds CMake, Python, TAEF/MinTe, Git, and validates the Windows SDK version (requires >= 10.0.26100.0 with d3d12.h). |
| `hctbuild.cmd` | **Main build script**: Configures and builds DXC using CMake + MSBuild/Visual Studio. Supports `-official`, `-fv` (fixed version), `-analyze`, `-alldef`, `-spirv`, `DXILCONV`, multiple architectures, and custom install directories. Defaults to VS 2022 generator. |
| `hcttest.cmd` | **Test runner**: Executes TAEF-based and LIT-based tests. Supports test filtering, SPIRV tests, execution tests, DXIL converter tests, parallel execution, and Agility SDK integration. Removes `dxil.dll` from PATH to avoid loading wrong DLLs. |
| `hctclean.cmd` | Deletes the `HLSL_BLD_DIR` build directory. |
| `hcthelp.cmd` | Prints reference for all `hct*` console aliases. |
| `hctgen.py` | **Code generator**: Generates HLSL/DXIL source files (headers, tables, documentation) from `gen_intrin_main.txt` and the DXIL database. Modes include `HLSLIntrinsicOp`, `DxilConstants`, `DxilInstructions`, `DxilShaderModel`, `DxilValidation`, `HLSLOptions`, `DxcOptimizer`, etc. Integrates with `clang-format` and handles CRLF/LF line endings. |
| `hctdb.py` | **DXIL database**: Python module defining DXIL shader stages, instruction overload types, enum representations, and the core DXIL instruction database. |
| `hctdb_instrhelp.py` | Helper module for `hctdb.py` to generate instruction documentation and helper functions. |
| `hctdb_test.py` | Test harness for the DXIL database. |
| `hcttrace.cmd` / `hcttracei.py` | Execution tracing utilities for DXC. |
| `hctbins.cmd`, `hctcopy.cmd`, `hctlabverify.cmd`, `hctspeak.js`, `hctshortcut.js`, `hcttodo.js`, `hctvs.cmd` | Miscellaneous helper scripts for shortcuts, notifications, VS launch, and lab verification. |
| `gen_intrin_main.txt` | Source-of-truth for HLSL intrinsic definitions consumed by `hctgen.py`. |
| `hlsl_intrinsic_opcodes.json` | Maps intrinsic opcode names to stable numeric values (424 intrinsics). |
| `CMakeLists.txt` | Generates `hlsl_intrinsic_opcodes.json` via `add_hlsl_hctgen()`. |
| `CodeTags.py` | `CODE_TAG` processing for generated source files. |
| `ExtractIRForPassTest.py` | Extracts LLVM IR for pass testing. |
| `VerifierHelper.py` | Helper for DXIL verifier tests. |
| `query.py` | Query utilities for the HCT database. |

#### Version Generation (`utils/version/`)

| File | Description |
|------|-------------|
| `gen_version.py` | Generates version resource definitions (`RC_FILE_VERSION`, `RC_PRODUCT_VERSION`, etc.) from Git metadata and `latest-release.json`. Supports **official**, **dev**, and **fixed version** build modes. |
| `latest-release.json` | Metadata for the latest DXC official release (version major/minor/rev, SHA, toolname). |
| `version.inc` | Fixed version override file for `-fv` builds. |

#### LLVM Legacy & General Utilities

| File | Description |
|------|-------------|
| `GetCommitInfo.py` | Queries Git for commit hash and count, writes a C++ namespace with `kGitCommitCount` and `kGitCommitHash` constants. |
| `GetRepositoryPath` / `GetSourceVersion` | Shell scripts returning repository path and version string. |
| `UpdateCMakeLists.pl` | Perl script that scans for `.cpp`/`.c` files and auto-updates `CMakeLists.txt` source lists for LLVM targets. |
| `GenLibDeps.pl` | Generates library dependency graphs (HTML/DOT) from binary archives using `nm`. |
| `llvm-compilers-check` | Python script for building and testing multiple LLVM flavors in parallel (debug, release, paranoid). |
| `llvmgrep` | Greps LLVM source tree with predefined patterns. |
| `llvmdo` | Runs commands across LLVM subdirectories. |
| `makellvm` | Convenience script for building LLVM targets. |
| `codegen-diff` | Diff utility for LLVM code generation output. |
| `findmisopt` / `findoptdiff` | Scripts for finding optimization miscompiles/differences. |
| `DSAextract.py` | Extracts named nodes from DSA (Data Structure Analysis) DOT graph output. |
| `sort_includes.py` | Sorts C++ `#include` directives. |
| `shuffle_fuzz.py` | Fuzzing script for shuffle vector instructions. |
| `prepare-code-coverage-artifact.py` | Prepares code coverage artifacts. |
| `update_llc_test_checks.py` | Updates `llc` test expected output. |
| `update_spirv_deps.sh` | Updates SPIR-V-related Git submodules (excludes `re2`, `effcee`, `DirectX-Headers`). |
| `lldbDataFormatters.py` | LLDB data formatters for LLVM types. |
| `llvm.natvis` | Visual Studio native visualizer definitions for LLVM data structures. |

---

## Key Build Configurations

### DXC-Specific CMake Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LLVM_DEFAULT_TARGET_TRIPLE` | `dxil-ms-dx` | Target triple for DXIL bytecode generation |
| `LLVM_ENABLE_EH` | `ON` | Enables C++ exception handling (required by DXC front-end) |
| `LLVM_ENABLE_RTTI` | `ON` | Enables Run-Time Type Information |
| `LLVM_TARGETS_TO_BUILD` | `None` | No native targets; DXC is a cross-compiler |
| `ENABLE_SPIRV_CODEGEN` | `ON` | Enables SPIR-V code generation backend |
| `SPIRV_BUILD_TESTS` | `ON` | Builds SPIR-V test suite |
| `HLSL_INCLUDE_TESTS` | `ON` | Includes HLSL-specific tests |
| `HLSL_COPY_GENERATED_SOURCES` | `Off` | Copies generated sources back to source tree |
| `HLSL_DISABLE_SOURCE_GENERATION` | `Off` | Disables in-tree source generation |
| `HLSL_ENABLE_DEBUG_ITERATORS` | undefined | Controls `_ITERATOR_DEBUG_LEVEL` (default 0) |
| `DXC_COVERAGE` | — | Enables instrumented coverage build |

### Build Modes (via `hctbuild.cmd`)

| Mode | Flag | Description |
|------|------|-------------|
| Standard | (none) | Development build; version format: `major.minor.0.<commit_count>` |
| Official | `-official` | Release build; version based on latest release + commits since |
| Fixed Version | `-fv` / `-fvloc` | Uses fixed version from `version.inc` |
| SPIR-V | `-spirv` | Enables SPIR-V code generation |
| Analysis | `-analyze` | Enables static analysis during build |

### Cross-Compilation Support

- **Android**: Uses standalone NDK toolchain with `arm-linux-androideabi` target.
- **iOS**: Uses Xcode toolchain with `iphoneos` SDK; auto-detects compilers via `xcrun`.
- **Native TableGen**: When cross-compiling, `TableGen.cmake` supports building a host-native `llvm-tblgen` first via `LLVM_USE_HOST_TOOLS`.

### Windows SDK & TAEF Requirements

- **Minimum Windows SDK**: `10.0.26100.0` with `d3d12.h` present.
- **TAEF**: Test Authoring and Execution Framework from WDK/Windows SDK, required for running `hcttest`.
- **DIA SDK**: Required for debug information processing; located via `vswhere.exe` or generator instance.

### Source Generation Pipeline

```
gen_intrin_main.txt
       +
  hctdb.py / hctdb_instrhelp.py
       |
       v
  hctgen.py --mode <MODE> --output <file>
       |
       v
  clang-format -i <file>
       |
       v
  [copy_if_different to source tree]
       |
       v
  <generated .h/.cpp/.inl files>
```

The `HCTGen` CMake target orchestrates this pipeline. Generated artifacts include:
- `HlslIntrinsicOp.h`
- `DxilConstants.h`
- `DxilInstructions.h`
- `DxilShaderModel.h`
- `DxilValidation.inc`
- `HLSLOptions.cpp`
- `DxcOptimizer.cpp`
- And many more.

---

## Summary

The DXC project's build system is a sophisticated extension of LLVM's CMake infrastructure, heavily customized for HLSL/DXIL and SPIR-V compilation. Key observations:

1. **CMake-Centric**: The `cmake/` directory provides comprehensive modules for compiler detection, platform abstraction, Windows SDK/D3D12/TAEF discovery, and DXC-specific code generation via `HCT.cmake`.

2. **HCT Automation**: The `utils/hct/` suite (`hctstart`, `hctbuild`, `hcttest`) provides a polished Windows command-line workflow that manages environment setup, CMake configuration, building, testing with TAEF/LIT, and version generation.

3. **Code Generation**: A significant portion of the build system (`hctgen.py`, `hctdb.py`, `TableGen.cmake`) is dedicated to generating C++ source files from declarative definitions (`gen_intrin_main.txt`, `.td` files), ensuring consistency across the compiler's intrinsic tables, DXIL operations, and validation rules.

4. **Multi-Platform Support**: While primarily Windows-focused (requiring Windows SDK, D3D12, TAEF), the project supports cross-compilation to Android and iOS, and builds on Linux with predefined cache parameters.

5. **Testing Infrastructure**: The project integrates LLVM `lit` for cross-platform testing and TAEF for Windows-native execution tests, with `hcttest.cmd` providing a unified test runner.

6. **Version Management**: Three distinct versioning schemes (official, dev, fixed) are managed through `gen_version.py`, integrating Git metadata and release tracking.

7. **Legacy LLVM Tools**: Many utilities (`llvm-build`, `GenLibDeps.pl`, `UpdateCMakeLists.pl`, `FileCheck`, `TableGen`) are inherited from upstream LLVM 3.7 and remain functional within the DXC fork.

---

*Report generated from analysis of `D:/DirectXShaderCompiler/cmake/` and `D:/DirectXShaderCompiler/utils/`*
