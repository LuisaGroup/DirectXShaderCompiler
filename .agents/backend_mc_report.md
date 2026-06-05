# Backend & Machine Code Analysis

## Overview

This report analyzes the backend and machine code libraries in the DirectX Shader Compiler (DXC) project, which is based on LLVM 3.7. The directories examined are:

- `lib/MC` — Machine Code layer (assembly, object files, disassembly)
- `lib/Target` — Target abstraction and code generation interface
- `lib/LTO` — Link-Time Optimization support
- `lib/ExecutionEngine` — Just-In-Time (JIT) compilation and execution

These libraries form the lower half of the LLVM compiler infrastructure, bridging the gap from LLVM IR down to executable machine code.

---

## 1. lib/MC — Machine Code Layer

### Directory Structure

```
lib/MC/
├── ConstantPools.cpp
├── ELFObjectWriter.cpp
├── MachObjectWriter.cpp
├── MCAsmBackend.cpp
├── MCAsmInfo*.cpp          (COFF, Darwin, ELF variants)
├── MCAsmStreamer.cpp
├── MCAssembler.cpp
├── MCCodeEmitter.cpp
├── MCCodeGenInfo.cpp
├── MCContext.cpp
├── MCDisassembler/         (Disassembler C API & implementation)
│   ├── Disassembler.cpp
│   ├── MCDisassembler.cpp
│   ├── MCExternalSymbolizer.cpp
│   └── MCRelocationInfo.cpp
├── MCDwarf.cpp
├── MCELFObjectTargetWriter.cpp
├── MCELFStreamer.cpp
├── MCExpr.cpp
├── MCInst.cpp
├── MCInstPrinter.cpp
├── MCInstrAnalysis.cpp
├── MCInstrDesc.cpp
├── MCLabel.cpp
├── MCLinkerOptimizationHint.cpp
├── MCMachObjectTargetWriter.cpp
├── MCMachOStreamer.cpp
├── MCNullStreamer.cpp
├── MCObjectFileInfo.cpp
├── MCObjectStreamer.cpp
├── MCObjectWriter.cpp
├── MCParser/               (Assembly parser)
│   ├── AsmLexer.cpp
│   ├── AsmParser.cpp
│   ├── COFFAsmParser.cpp
│   ├── DarwinAsmParser.cpp
│   ├── ELFAsmParser.cpp
│   ├── MCAsmLexer.cpp
│   ├── MCAsmParser.cpp
│   ├── MCAsmParserExtension.cpp
│   └── MCTargetAsmParser.cpp
├── MCRegisterInfo.cpp
├── MCSchedule.cpp
├── MCSection*.cpp          (COFF, ELF, MachO variants)
├── MCStreamer.cpp
├── MCSubtargetInfo.cpp
├── MCSymbol.cpp
├── MCSymbolELF.cpp
├── MCSymbolizer.cpp
├── MCTargetOptions.cpp
├── MCValue.cpp
├── MCWin64EH.cpp
├── MCWinEH.cpp
├── StringTableBuilder.cpp
├── SubtargetFeature.cpp
├── WinCOFFObjectWriter.cpp
├── WinCOFFStreamer.cpp
└── YAML.cpp
```

### Key Files and Their Purposes

| File | Purpose |
|------|---------|
| **MCInst.h / MCInst.cpp** | Core machine instruction representation (`MCInst`, `MCOperand`). `MCOperand` is a discriminated union holding registers, immediates, FP immediates, expressions, or sub-instructions. |
| **MCStreamer.h / MCStreamer.cpp** | Abstract interface for emitting machine code. Provides callbacks for directives, labels, data emission, and instructions. Multiple implementations exist: `MCAsmStreamer` (text `.s` files), `MCObjectStreamer` (binary `.o` files), and `MCNullStreamer` (no-op for timing). |
| **MCAssembler.h / MCAssembler.cpp** | The actual assembler engine. Manages `MCFragment` objects (data, align, fill, relaxable, etc.), performs layout, relaxation, fixup evaluation, and writes object files via `MCObjectWriter`. |
| **MCContext.h / MCContext.cpp** | Central context/allocator for the MC layer. Owns all sections, symbols, and Dwarf line tables. Provides uniquing for ELF/MachO/COFF sections and manages temporary/local symbols. |
| **MCAsmInfo.h / MCAsmInfo*.cpp** | Target-specific assembly syntax information (comment strings, directive names, alignment behaviors, etc.). Variants for COFF, Darwin, and ELF. |
| **MCObjectWriter.cpp / ELFObjectWriter.cpp / MachObjectWriter.cpp / WinCOFFObjectWriter.cpp** | Format-specific object file writers. Take the assembled fragments and emit the final binary object file. |
| **MCDisassembler/** | Disassembly infrastructure. `MCDisassembler` is the abstract base; target-specific backends implement `getInstruction()`. The C API (`Disassembler.cpp`) wraps this for external consumers (e.g., `llvm::objdump`). |
| **MCParser/** | Assembly language parser. `AsmLexer` tokenizes, `AsmParser` builds MC constructs, and target-specific parsers (`MCTargetAsmParser`) handle target directives and operands. |
| **MCCodeEmitter.cpp** | Encodes `MCInst` objects into target-specific machine code bytes. Typically auto-generated from TableGen. |
| **MCExpr.h / MCExpr.cpp** | Machine code expressions representing relocatable values (symbol references, binary expressions, constants). |
| **MCSymbol.h / MCSymbol.cpp** | Represents symbols (labels) in assembly/object files. Tracks fragments, offsets, and linkage attributes. |
| **MCSection*.cpp** | Target object format section representations for ELF, Mach-O, and COFF/PE. |

### Main Classes and Responsibilities

- **`MCInst`** — A single low-level machine instruction, composed of an opcode and a vector of `MCOperand`s.
- **`MCOperand`** — Discriminated union representing a register, immediate, FP immediate, expression, or nested instruction.
- **`MCStreamer`** — Abstract base for code emission. Key subclasses:
  - `MCAsmStreamer`: Emits human-readable assembly.
  - `MCObjectStreamer`: Emits binary object files via `MCAssembler`.
  - `MCNullStreamer`: No-op streamer for benchmarking.
- **`MCAssembler`** — The integrated assembler. Lays out fragments, evaluates fixups, relaxes instructions, and coordinates the `MCAsmBackend` and `MCObjectWriter`.
- **`MCFragment`** — Base class for pieces of a section. Types include:
  - `MCDataFragment` — raw data with fixups.
  - `MCRelaxableFragment` — instruction that may need relaxation.
  - `MCAlignFragment` — alignment padding.
  - `MCFillFragment` — repeated fill values.
  - `MCLEBFragment` — ULEB/SLEB128 encoded values.
  - `MCDwarfLineAddrFragment` / `MCDwarfCallFrameFragment` — DWARF debug info.
- **`MCContext`** — Factory and owner for `MCSymbol`, `MCSection`, and Dwarf tables. Uses a bump-pointer allocator for efficiency.
- **`MCDisassembler`** — Abstract interface for decoding bytes into `MCInst`. Target backends override `getInstruction()`.

### Component Interactions

```
Frontend / CodeGen
       │
       ▼
   MCInst (instruction representation)
       │
       ├──► MCCodeEmitter ──► bytes + fixups
       │
       ▼
  MCStreamer (abstract emission API)
       │
       ├──► MCAsmStreamer ──► formatted_raw_ostream ──► .s file
       │
       └──► MCObjectStreamer ──► MCAssembler ──► MCObjectWriter ──► .o file
                │
                ├──► MCContext (owns symbols, sections, allocator)
                ├──► MCAsmBackend (fixup/relaxation logic)
                └──► MCExpr (relocatable values)
```

---

## 2. lib/Target — Target Abstraction Layer

### Directory Structure

```
lib/Target/
├── CMakeLists.txt
├── LLVMBuild.txt
├── README.txt
├── Target.cpp
├── TargetIntrinsicInfo.cpp
├── TargetLoweringObjectFile.cpp
├── TargetMachine.cpp
├── TargetMachineC.cpp
├── TargetRecip.cpp
└── TargetSubtargetInfo.cpp
```

### Key Files and Their Purposes

| File | Purpose |
|------|---------|
| **TargetMachine.h / TargetMachine.cpp** | Core target abstraction. `TargetMachine` holds the `DataLayout`, target triple, CPU, feature string, and `MCCodeGenInfo`. It provides the interface for adding code-generation passes (`addPassesToEmitFile`, `addPassesToEmitMC`). `LLVMTargetMachine` extends this for targets using the standard code generator. |
| **TargetLoweringObjectFile.h / .cpp** | Determines which object file section a global variable or function belongs to. Classifies globals into `SectionKind` categories (Text, Data, BSS, ReadOnly, ThreadLocal, etc.) and maps them to `MCSection` objects. |
| **TargetSubtargetInfo.cpp** | Represents target-specific subtarget information (CPU features, scheduling models). |
| **TargetIntrinsicInfo.cpp** | Maps target-specific intrinsics to their names/IDs. |
| **TargetRecip.cpp** | Target reciprocal estimation controls. |
| **Target.cpp** | Basic target registry and intrinsic info utilities. |

### Main Classes and Responsibilities

- **`TargetMachine`** — Primary interface to the complete machine description:
  - Holds `DataLayout`, target triple, CPU, feature string.
  - Manages `MCAsmInfo`, `MCRegisterInfo`, `MCInstrInfo`, `MCSubtargetInfo`.
  - Provides `addPassesToEmitFile()` to drive the entire code-generation pipeline.
  - Provides `addPassesToEmitMC()` for JIT-oriented MC emission.
  - Determines TLS model, relocation model, code model, and optimization level.
- **`LLVMTargetMachine`** — Standard implementation used by most in-tree targets. Creates `TargetPassConfig` and wires up the default pass pipeline.
- **`TargetLoweringObjectFile`** — Bridges IR-level `GlobalValue` objects to MC-level sections:
  - `getKindForGlobal()` classifies a global into `SectionKind`.
  - `SectionForGlobal()` returns the `MCSection` where the global should be emitted.
  - Handles special cases like string constants, jump tables, and COMDATs.
- **`TargetSubtargetInfo`** — Per-function subtarget information (ISA features, scheduling, instruction costs).

### Component Interactions

```
LLVM IR Module
      │
      ▼
TargetMachine (target description)
      │
      ├──► TargetSubtargetInfo (per-function CPU/features)
      ├──► TargetLoweringObjectFile ──► MCSection assignments
      │
      └──► addPassesToEmitFile() ──► Pass pipeline
                │
                ├──► Instruction Selection (ISel)
                ├──► Register Allocation
                ├──► Prolog/Epilog insertion
                └──► MC layer emission (MCStreamer)
```

---

## 3. lib/LTO — Link-Time Optimization

### Directory Structure

```
lib/LTO/
├── CMakeLists.txt
├── LLVMBuild.txt
├── LTOCodeGenerator.cpp
└── LTOModule.cpp
```

### Key Files and Their Purposes

| File | Purpose |
|------|---------|
| **LTOCodeGenerator.h / .cpp** | Driver for the IPO (Inter-Procedural Optimization) and Post-IPO stages. Merges bitcode modules, applies scope restrictions/internalization, runs LTO passes, and generates a single native object file. |
| **LTOModule.h / .cpp** | Wrapper around an LLVM bitcode module for LTO consumption. Parses symbols from the module (defined/undefined), handles ObjC metadata, and provides the symbol table interface expected by linkers. |

### Main Classes and Responsibilities

- **`LTOCodeGenerator`** — The main LTO driver:
  - `addModule()` / `setModule()` — Links bitcode modules into a single merged module.
  - `determineTarget()` — Creates the `TargetMachine` from the module triple.
  - `applyScopeRestrictions()` — Internalizes symbols that are not in the "must preserve" list.
  - `optimize()` — Runs the LTO pass pipeline (IPSCCP, GlobalOpt, Inliner, GVN, etc.).
  - `compile()` / `compileOptimized()` — Emits a native object file via `TargetMachine::addPassesToEmitFile()`.
  - `writeMergedModules()` — Writes the merged (but not yet optimized) bitcode to a file.
- **`LTOModule`** — LTO module abstraction:
  - `createFromFile()` / `createFromBuffer()` — Parses bitcode into an `LTOModule`.
  - `parseSymbols()` — Builds symbol tables of defined and undefined symbols.
  - Handles special ObjC symbol synthesis (`.objc_class_name_*`) for Darwin.
  - Stores symbol attributes (visibility, linkage, type) for the linker.

### Component Interactions

```
Linker
  │
  ├──► LTOModule (bitcode parsing + symbol extraction)
  │
  └──► LTOCodeGenerator
          │
          ├──► Linker (IRLinker) ──► merged Module
          ├──► TargetMachine ──► target-specific codegen
          │
          ├──► optimize() ──► PassManagerBuilder::populateLTOPassManager()
          │
          └──► compile() ──► TargetMachine::addPassesToEmitFile()
                                    │
                                    └──► native object file (.o)
```

---

## 4. lib/ExecutionEngine — JIT and Runtime Execution

### Directory Structure

```
lib/ExecutionEngine/
├── ExecutionEngine.cpp
├── ExecutionEngineBindings.cpp
├── GDBRegistrationListener.cpp
├── IntelJITEvents/       (Intel VTune profiling integration)
├── Interpreter/          (LLVM IR interpreter)
│   ├── Execution.cpp
│   ├── ExternalFunctions.cpp
│   ├── Interpreter.cpp
│   └── Interpreter.h
├── MCJIT/                (MC-based Just-In-Time compiler)
│   ├── MCJIT.cpp
│   ├── MCJIT.h
│   └── ObjectBuffer.h
├── OProfileJIT/          (OProfile profiling integration)
├── Orc/                  (On-Request Compilation / next-gen JIT)
│   ├── ExecutionUtils.cpp
│   ├── IndirectionUtils.cpp
│   ├── NullResolver.cpp
│   ├── OrcMCJITReplacement.cpp
│   ├── OrcMCJITReplacement.h
│   └── OrcTargetSupport.cpp
├── RuntimeDyld/          (Runtime dynamic linker)
│   ├── RTDyldMemoryManager.cpp
│   ├── RuntimeDyld.cpp
│   ├── RuntimeDyldChecker.cpp
│   ├── RuntimeDyldCOFF.cpp / .h
│   ├── RuntimeDyldELF.cpp / .h
│   ├── RuntimeDyldImpl.h
│   ├── RuntimeDyldMachO.cpp / .h
│   └── Targets/          (target-specific stub generators)
│       ├── RuntimeDyldCOFFX86_64.h
│       ├── RuntimeDyldMachOAArch64.h
│       ├── RuntimeDyldMachOARM.h
│       ├── RuntimeDyldMachOI386.h
│       └── RuntimeDyldMachOX86_64.h
├── SectionMemoryManager.cpp
└── TargetSelect.cpp
```

### Key Files and Their Purposes

| File | Purpose |
|------|---------|
| **ExecutionEngine.h / .cpp** | Abstract base class for all execution engines. Manages global address mappings, module lists, and provides `runFunction()`. Contains `EngineBuilder` for configuring and creating the desired engine (JIT or Interpreter). |
| **MCJIT.h / MCJIT.cpp** | MC-based JIT compiler. Uses the standard code generator to emit object files into memory, then loads them via `RuntimeDyld`. Supports `ObjectCache` for caching compiled objects. |
| **RuntimeDyld.h / RuntimeDyld.cpp** | Runtime dynamic linker. Loads object files into memory, resolves relocations, and manages symbol tables. Supports ELF, Mach-O, and COFF formats via backend subclasses. |
| **RuntimeDyldELF.cpp / RuntimeDyldCOFF.cpp / RuntimeDyldMachO.cpp** | Format-specific relocation handling and section loading. |
| **SectionMemoryManager.cpp** | Default `RTDyldMemoryManager` that allocates RWX memory for JIT code and data using the OS memory APIs. |
| **Interpreter/** | LLVM IR interpreter. Executes IR instructions directly without native code generation. Supports external function calls via function pointers. |
| **Orc/** | Next-generation JIT infrastructure (Orc). `OrcMCJITReplacement` provides an Orc-based drop-in replacement for MCJIT. Supports lazy compilation and modular JIT design. |
| **GDBRegistrationListener.cpp** | Registers JIT-compiled code with GDB so that debuggers can see symbolic information for JIT frames. |

### Main Classes and Responsibilities

- **`ExecutionEngine`** — Abstract execution engine:
  - Manages a list of `Module`s.
  - Maintains global symbol → address mappings (`ExecutionEngineState`).
  - `runFunction()` — Executes a function with given arguments.
  - `getPointerToFunction()` / `getFunctionAddress()` — Triggers JIT compilation if needed.
  - `addGlobalMapping()` — Allows external symbols to be resolved.
- **`EngineBuilder`** — Factory for creating the right execution engine:
  - `selectTarget()` — Chooses target based on module triple.
  - `create()` — Instantiates MCJIT, OrcMCJITReplacement, or Interpreter.
- **`MCJIT`** — The standard JIT implementation:
  - `generateCodeForModule()` — Runs codegen passes to emit an in-memory object.
  - `emitObject()` — Uses `TargetMachine::addPassesToEmitMC()` to produce a `MemoryBuffer` containing the object file.
  - `findSymbol()` — Resolves symbols across modules and archives; triggers on-demand compilation.
  - `finalizeObject()` — Resolves relocations, registers EH frames, and marks memory executable.
- **`RuntimeDyld`** — The runtime linker:
  - `loadObject()` — Parses an `ObjectFile`, allocates sections via `MemoryManager`, and records relocations.
  - `resolveRelocations()` — Applies all pending relocations by looking up symbol addresses.
  - `registerEHFrames()` / `deregisterEHFrames()` — Manages exception handling metadata.
  - `MemoryManager` (abstract) — Allocates code/data sections and applies page permissions.
  - `SymbolResolver` (abstract) — Resolves external symbol names to addresses.
- **`SectionMemoryManager`** — Default memory manager using `sys::Memory` to allocate RWX pages.
- **`Interpreter`** — Executes IR directly:
  - `Execution.cpp` — Core interpreter loop for LLVM instructions.
  - `ExternalFunctions.cpp` — Handles calls to external native functions.
- **`OrcMCJITReplacement`** — Orc-based JIT that mimics the MCJIT API for compatibility while providing more flexibility.

### Component Interactions

```
Client Application
       │
       ▼
  EngineBuilder
       │
       ├──► MCJIT
       │      │
       │      ├──► TargetMachine::addPassesToEmitMC()
       │      │           │
       │      │           └──► MCStreamer ──► in-memory object file
       │      │
       │      ├──► RuntimeDyld::loadObject()
       │      │           │
       │      │           ├──► MemoryManager::allocateCodeSection/DataSection()
       │      │           └──► record relocations
       │      │
       │      ├──► RuntimeDyld::resolveRelocations()
       │      │           └──► SymbolResolver::findSymbol()
       │      │
       │      └──► finalizeMemory() ──► RWX permissions ──► executable code
       │
       └──► Interpreter
              └──► direct IR interpretation
```

---

## Component Interactions (Cross-Directory)

### Full Backend Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CODE GENERATION PIPELINE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   LLVM IR                                                                    │
│      │                                                                       │
│      ▼                                                                       │
│   lib/Target                                                                 │
│      ├── TargetMachine ──► addPassesToEmitFile() / addPassesToEmitMC()       │
│      │   ├── TargetSubtargetInfo (CPU/features)                              │
│      │   └── TargetLoweringObjectFile ──► section assignment                 │
│      │                                                                       │
│      ▼                                                                       │
│   CodeGen Passes (lib/CodeGen)                                               │
│      ├── Instruction Selection                                               │
│      ├── Scheduling & Register Allocation                                    │
│      └── AsmPrinter ──► MCStreamer                                           │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                              MC LAYER                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   lib/MC                                                                     │
│      ├── MCInst / MCOperand (instruction representation)                     │
│      ├── MCCodeEmitter ──► encoded bytes                                     │
│      ├── MCExpr ──► relocatable expressions                                  │
│      ├── MCContext ──► symbol & section ownership                            │
│      │                                                                       │
│      ├── MCAsmStreamer ──► .s assembly text                                  │
│      └── MCObjectStreamer ──► MCAssembler ──► .o binary object               │
│              │                                                               │
│              ├── MCFragment layout & relaxation                              │
│              ├── MCFixup evaluation                                          │
│              └── MCObjectWriter (ELF/MachO/COFF)                             │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                         JIT / EXECUTION PATH                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   lib/ExecutionEngine                                                        │
│      ├── MCJIT ──► emit object to MemoryBuffer                               │
│      │       └──► RuntimeDyld::loadObject()                                  │
│      │               ├── RuntimeDyldELF / COFF / MachO                       │
│      │               ├── SectionMemoryManager (allocate RWX)                 │
│      │               └── resolveRelocations()                                │
│      │                                                                       │
│      ├── OrcMCJITReplacement (next-gen JIT)                                  │
│      └── Interpreter (direct IR execution)                                   │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                         LTO PATH                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   lib/LTO                                                                    │
│      ├── LTOModule ──► parse bitcode symbols                                 │
│      └── LTOCodeGenerator                                                    │
│              ├── IRLinker ──► merge modules                                  │
│              ├── optimize() ──► IPO passes                                   │
│              └── compile() ──► TargetMachine ──► native object               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Summary

| Directory | Primary Role | Key Abstractions |
|-----------|-------------|------------------|
| **lib/MC** | Assembly and object file generation/disassembly | `MCInst`, `MCStreamer`, `MCAssembler`, `MCContext`, `MCDisassembler` |
| **lib/Target** | Target-independent code generation interface | `TargetMachine`, `TargetLoweringObjectFile`, `TargetSubtargetInfo` |
| **lib/LTO** | Link-time optimization for whole-program optimization | `LTOCodeGenerator`, `LTOModule` |
| **lib/ExecutionEngine** | JIT compilation and direct IR execution | `ExecutionEngine`, `MCJIT`, `RuntimeDyld`, `Interpreter`, `Orc` |

### Notable Design Patterns

1. **Streamer Pattern** — `MCStreamer` abstracts over both assembly text and binary object emission, allowing the same codegen path to produce either output.
2. **Fragment-Based Assembly** — `MCAssembler` uses a fragment graph per section rather than a simple byte stream, enabling late-stage relaxation and fixup resolution.
3. **Bump-Pointer Allocation** — `MCContext` uses a `BumpPtrAllocator` for all symbols and sections, making assembly/object generation very fast and cache-friendly.
4. **Pluggable JIT Stack** — `EngineBuilder` lets clients choose between MCJIT, Orc, and Interpreter without changing their calling code.
5. **Runtime Linker Abstraction** — `RuntimeDyld` isolates object loading and relocation from memory management and symbol resolution, enabling remote/target execution scenarios.
6. **SectionKind Classification** — `TargetLoweringObjectFile` uses a rich `SectionKind` taxonomy to make target-independent decisions about where to place globals.

### DXC Context

In DXC, the **MC layer** is heavily used for DXIL (LLVM IR) validation and for emitting DXIL container objects. The **Target** layer provides the target machine abstraction used by the HLSL compiler backend. While **LTO** and **ExecutionEngine** (JIT/Interpreter) are present in the codebase, they are less central to the DXC shader compiler path, which primarily compiles HLSL to DXIL byte code rather than native machine code or JIT execution. However, these components remain part of the underlying LLVM infrastructure that DXC inherits.
