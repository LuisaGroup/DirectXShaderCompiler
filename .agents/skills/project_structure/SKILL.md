---
name: project_structure
description: Analyzes and navigates the DirectX Shader Compiler (DXC) project structure. Use when asked about DXC codebase organization, directory purposes, component interactions, data flow, build system, testing infrastructure, or when onboarding new developers to the DXC repository.
---

# DXC Project Structure Skill

This skill provides structured knowledge about the DirectX Shader Compiler (DXC) codebase.

## Quick Reference

DXC is a fork of LLVM 3.7 + Clang, modified to compile HLSL → DXIL (and optionally SPIR-V).

### Architecture Layers

| Layer | Directories |
|-------|-------------|
| Frontend | `tools/clang/lib/{Lex,Parse,AST,Sema,CodeGen,SPIRV}` |
| High-Level IR | `lib/HLSL/`, `include/dxc/HLSL/` |
| Low-Level IR (DXIL) | `lib/DXIL/`, `include/dxc/DXIL/` |
| LLVM Core | `lib/IR/`, `lib/Analysis/`, `lib/Transforms/`, `lib/CodeGen/` |
| DXIL Infrastructure | `lib/DxilContainer/`, `lib/DxilValidation/`, `lib/DxilRootSignature/` |
| Debug / PIX | `lib/DxilDia/`, `lib/DxilPIXPasses/`, `lib/DxrFallback/` |
| Tools | `tools/clang/tools/{dxc,dxcompiler,...}`, `tools/{opt,llvm-dis,...}` |
| Build & Test | `cmake/`, `utils/hct/`, `test/`, `unittests/` |

### Key Concepts

- **HLModule**: High-level IR attached to `llvm::Module` during frontend codegen. Tracks matrices, vectors, HL intrinsics.
- **DxilModule**: Canonical low-level DXIL representation after `DxilGenerationPass`. Managed by `lib/DXIL/`.
- **DXIL Container**: Binary archive (FourCC `DXBC` header) with parts for bitcode, signatures, PSV, RDAT, debug info, etc.
- **Two-Module IR**: Frontend produces HLModule → passes lower → DxilGenerationPass creates DxilModule.

## Usage

When asked about DXC project structure:
1. Reference the architecture layers above.
2. For detailed directory listings, data flow diagrams, glossary, and build/test info, load `references/project_structure.md`.
3. For per-target executive summaries, load `references/summaries.md`.

## Files

- `references/project_structure.md` — Comprehensive project structure document (directory tree, architecture, data flow, build system, testing, glossary).
- `references/summaries.md` — Executive summaries for each major component area.
