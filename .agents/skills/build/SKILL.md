---
name: build
description: Build the DirectX Shader Compiler (DXC) using build.py. Use when asked to build, compile, or configure DXC, or when the user mentions build.py, CMake configuration, or build types (Release/Debug).
---

# DXC Build Skill

Use `build.py` at the repo root to configure and build DXC with CMake.

## Quick Commands

```bash
# Release build (default)
python build.py

# Debug build
python build.py --build-type Debug

# Custom build type
python build.py --build-type RelWithDebInfo

# Specific targets only
python build.py --targets dxc,dxcompiler
```

## Argument Reference

### Build Type

| Arg | Default | Choices | Description |
|-----|---------|---------|-------------|
| `--build-type` | `Release` | `Release`, `Debug`, `RelWithDebInfo`, `MinSizeRel` | CMake build type. |

### Paths & Generator

| Arg | Default | Description |
|-----|---------|-------------|
| `--build-dir` | `build` | Build directory relative to repo root. |
| `--generator` | `Visual Studio 17 2022` (Win) / `Ninja` (other) | CMake generator. |
| `--vs-version` | `latest` | Visual Studio version to use on Windows (`2019`, `2022`, `latest`). |
| `--jobs` / `-j` | (unlimited) | Number of parallel build jobs. |

### Build Control

| Arg | Default | Description |
|-----|---------|-------------|
| `--targets` | `dxc,dxcompiler,dxv,dxilconv` | Comma-separated CMake targets. |
| `--clean` | `false` | Remove build dir before configuring. |

### Feature Flags

| Arg | Default | Description |
|-----|---------|-------------|
| `--enable-spirv-codegen` / `--disable-spirv-codegen` | enabled | SPIR-V codegen toggle. |
| `--spirv-build-tests` | `false` | Build SPIR-V tests (requires extra deps). |
| `--coverage` | `false` | Code coverage instrumentation. |
| `--werror` | `false` | Treat warnings as errors. |
| `--clang` | `auto` | Use Clang. `auto` uses it if found, `on` requires it, `off` disables it. On Windows this selects `clang-cl.exe` and switches the generator to Ninja. |

### Linker & Sanitizer (Ninja / non-Windows)

| Arg | Default | Description |
|-----|---------|-------------|
| `--use-lld` | `false` | Use LLD linker. |
| `--sanitizer` | (none) | Enable sanitizers, e.g. `Address;Undefined`. |
| `--split-dwarf` | `false` | Split DWARF for faster linking. |
| `--enable-libcxx` | `false` | Use libc++ instead of libstdc++. |

### Ninja Parallel Limits

| Arg | Default | Description |
|-----|---------|-------------|
| `--parallel-link-jobs` | (unlimited) | Max concurrent link jobs. |
| `--parallel-compile-jobs` | (unlimited) | Max concurrent compile jobs. |

## Build Output

Binaries land in `<build-dir>/<build-type>/bin/`:

| Target | Output |
|--------|--------|
| `dxc` | `dxc.exe` |
| `dxv` | `dxv.exe` |
| `dxcompiler` | `dxcompiler.dll` |
| `dxilconv` | `dxilconv.dll` |

After building, the script verifies that each requested target's binary exists and reports size or missing status.

## Common Patterns

**Iterative dev loop** (no clean, just rebuild changed files):
```bash
python build.py --build-type Debug
```

**Full clean rebuild**:
```bash
python build.py --clean
```

**Build only the compiler DLL**:
```bash
python build.py --targets dxcompiler
```

**Release with sanitizer on Linux**:
```bash
python build.py --sanitizer "Address;Undefined"
```

**Build with clang-cl on Windows (Debug)**:
```bash
python build.py --build-type Debug --clang=on
```

The `--clang=on` form fails if Clang/`clang-cl.exe` is not on `PATH`. Use `--clang=auto` to use it only when available.
