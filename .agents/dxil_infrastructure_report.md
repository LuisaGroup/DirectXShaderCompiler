# DXIL Infrastructure Analysis

This report analyzes the DXIL infrastructure libraries in the DirectX Shader Compiler project. These libraries form the core foundation for the DXIL container format, validation, root signatures, hashing, and PDB information handling.

---

## Directory: lib/DxilContainer

**Purpose:** Implements the DXIL container format — the binary packaging standard for compiled DXIL shaders. The container is analogous to the older DXBC format but designed for the LLVM-based DXIL intermediate representation.

**Files:**
| File | Purpose |
|------|---------|
| `DxilContainer.h` (include) | Core container format definitions: headers, FourCC codes, program headers, signatures, source info, and helper functions |
| `DxilContainerAssembler.h` (include) | Interfaces for writing/serializing DXIL container parts |
| `DxilContainerReader.h` (include) | `DxilContainerReader` class for parsing existing containers |
| `DxcContainerBuilder.h` (include) | `DxcContainerBuilder` COM class implementing `IDxcContainerBuilder` |
| `DxilContainer.cpp` | Container validation (`IsValidDxilContainer`), part lookup (`GetDxilPartByType`), iterator support |
| `DxilContainerAssembler.cpp` | Serialization of modules into containers: signature writers, PSV writer, RDAT writer, feature info writer, `SerializeDxilContainerForModule` |
| `DxilContainerReader.cpp` | Implementation of `DxilContainerReader::Load`, `GetPartContent`, `FindFirstPartKind` |
| `DxcContainerBuilder.cpp` | Implementation of `IDxcContainerBuilder` — load, add/remove parts, serialize with optional validation |
| `DxilRDATBuilder.cpp` | Runtime Data (RDAT) table builder for shader reflection and subobjects |
| `DxilRuntimeReflection.cpp` | Runtime reflection support (includes `DxilRuntimeReflection.inl`) |
| `DxilPipelineStateValidation.cpp` | Pipeline State Validation (PSV) data structures and helpers |
| `D3DReflectionDumper.cpp` | Reflection data dumper utilities |
| `D3DReflectionStrings.cpp` | Reflection string utilities |
| `RDATDumper.cpp` | RDAT content dumper |
| `RDATDxilSubobjects.cpp` | RDAT subobject loading |

**Key Structures:**
- `DxilContainerHeader` — container header with FourCC (`DXBC`), hash, version, size, part count
- `DxilPartHeader` — individual part header with FourCC and size
- `DxilProgramHeader` / `DxilBitcodeHeader` — DXIL program/bitcode headers
- `DxilShaderHash` / `DxilContainerHash` — hash structures
- `DxilSourceInfo` — source names, contents, and compilation args embedding
- `DxilShaderPDBInfo` — PDB info header with compression support

**Key Classes/Functions:**
- `DxilContainerReader` — parses and enumerates container blobs
- `DxcContainerBuilder` — COM-based builder for modifying containers (add/remove debug info, root signatures, private data)
- `DxilPartWriter` / `DxilContainerWriter` — abstract interfaces for part serialization
- `SerializeDxilContainerForModule()` — main entry point for shader container serialization
- `NewPSVWriter()`, `NewRDATWriter()`, `NewProgramSignatureWriter()` — part writer factories

**FourCC Part Types:**
| FourCC | Description |
|--------|-------------|
| `DXBC` | Container identifier |
| `DXIL` | DXIL program bitcode |
| `PSV0` | Pipeline State Validation data |
| `RDAT` | Runtime reflection data |
| `ISG1` | Input signature |
| `OSG1` | Output signature |
| `PSG1` | Patch constant / primitive signature |
| `RDEF` | Resource definitions |
| `STAT` | Shader statistics / feature info |
| `RTS0` | Root signature |
| `HASH` | Shader hash |
| `PDBI` | PDB information |
| `SRCI` | Source information |
| `VERS` | Compiler version |
| `ILDB` / `ILDN` | Debug info / debug name |

---

## Directory: lib/DxilValidation

**Purpose:** Validates DXIL modules and containers to ensure correctness, conformance to shader models, and consistency between container parts and the DXIL module. This is the core of the DXIL validator.

**Files:**
| File | Purpose |
|------|---------|
| `DxilValidation.h` (include) | Public validation API: `ValidateDxilContainer`, `ValidateLoadModule`, `PrintDiagnosticContext` |
| `DxilValidation.cpp` | Core DXIL module validation: instructions, signatures, resources, shader model constraints |
| `DxilContainerValidation.cpp` | Container-level validation: verifies container parts match module data (signatures, PSV, RDAT, feature info) |
| `DxilValidationUtils.h` | `ValidationContext`, `EntryStatus`, and utility emit functions |
| `DxilValidationUtils.cpp` | Implementation of validation utilities |

**Key Classes:**
- `ValidationContext` — central context holding the LLVM module, `DxilModule`, diagnostic state, resource maps, and entry status maps. Provides `EmitError`, `EmitInstrError`, `EmitFormatError`, etc.
- `EntryStatus` — per-entry-function state tracking output writes, coverage, ViewID usage, domain location size
- `PrintDiagnosticContext` — captures LLVM diagnostics into a printer stream

**Validation Areas:**
1. **Module Loading** — `ValidateLoadModule()`, `ValidateLoadModuleFromContainer()` validate LLVM bitcode can be loaded
2. **Instruction Validation** — opcode correctness, operand ranges, signature access (`LoadInput`, `StoreOutput`), resource coordinate/offset validation, sampler mode checks
3. **Signature Validation** — row/column bounds, semantic validation, interpolation mode checks
4. **Resource Validation** — handle creation, resource class/kind matching, UAV/SRV/CBuffer/sampler consistency
5. **Shader Model Constraints** — derivative ops in CS/MS/AS require SM 6.6+, mesh/amplification shader opcode restrictions
6. **Container Part Validation** — ensures signature blobs, PSV0, RDAT, feature info, and compiler version parts match the module

**Key Functions:**
- `ValidateDxilModule()` — comprehensive module validation
- `ValidateDxilContainerParts()` — validates all container parts against the module
- `ValidateDxilContainer()` — full container validation including module validation
- `VerifySignatureMatches()` — signature blob verification
- `VerifyPSVMatches()` — PSV0 content verification
- `VerifyRDATMatches()` — RDAT content verification

---

## Directory: lib/DxilRootSignature

**Purpose:** Implements parsing, serialization, deserialization, conversion, and validation of HLSL root signatures. Root signatures define how shader resources are bound to the graphics pipeline.

**Files:**
| File | Purpose |
|------|---------|
| `DxilRootSignature.h` (include) | Root signature structures, enums, `RootSignatureHandle`, and public API |
| `DxilRootSignature.cpp` | `RootSignatureHandle` implementation, printing, memory management |
| `DxilRootSignatureConvert.cpp` | Version conversion (1.0 ↔ 1.1) |
| `DxilRootSignatureSerializer.cpp` | Binary serialization of root signatures to blobs |
| `DxilRootSignatureValidator.cpp` | Root signature validation: overlap detection, descriptor table verification, static sampler checks, shader PSV binding verification |
| `DxilRootSignatureHelper.h` | Internal helper templates for flag manipulation |

**Key Structures:**
- `DxilRootSignatureDesc` / `DxilRootSignatureDesc1` — root signature descriptors (versions 1.0 and 1.1)
- `DxilRootParameter` / `DxilRootParameter1` — root parameters: descriptor tables, constants, root descriptors
- `DxilDescriptorRange` / `DxilDescriptorRange1` — descriptor ranges with optional flags
- `DxilStaticSamplerDesc` — static sampler description
- `DxilVersionedRootSignatureDesc` — union holding either v1.0 or v1.1 descriptor

**Key Classes:**
- `RootSignatureHandle` — manages either an in-memory description or a serialized blob, with lazy deserialization
- `RootSignatureVerifier` — validates root signatures for correctness:
  - Detects overlapping register ranges across visibility types
  - Validates descriptor table consistency (no mixing samplers with resources)
  - Validates root descriptor flags
  - Verifies shader resource bindings against PSV data
- `DescriptorTableVerifier` — validates descriptor ranges within tables
- `StaticSamplerVerifier` — validates static sampler state

**Key Functions:**
- `SerializeRootSignature()` — serializes a root signature to an `IDxcBlob`
- `DeserializeRootSignature()` — deserializes a blob to a descriptor
- `ConvertRootSignature()` — upconverts/downconverts between versions
- `VerifyRootSignature()` / `VerifyRootSignatureWithShaderPSV()` — standalone validation
- `printRootSignature()` — outputs root signature in HLSL-like textual form

**Root Signature Versions:**
- Version 1.0 — basic descriptor tables, root descriptors, constants, static samplers
- Version 1.1 — adds descriptor range flags and root descriptor flags for volatile/static data behavior

---

## Directory: lib/DxilHash

**Purpose:** Computes cryptographic hashes for DXIL/DXBC containers. Uses a customized MD5-based algorithm. Not intended for security purposes.

**Files:**
| File | Purpose |
|------|---------|
| `DxilHash.h` (include) | Hash function prototype (`HASH_FUNCTION_PROTO`) and exported hash functions |
| `DxilHash.cpp` | MD5-derived hash implementation: `ComputeHashRetail` and `ComputeHashDebug` |

**Key Functions:**
- `ComputeHashRetail(const BYTE *pData, UINT32 byteCount, BYTE *pOutHash)` — retail hash with specific padding constants
- `ComputeHashDebug(const BYTE *pData, UINT32 byteCount, BYTE *pOutHash)` — debug hash with different padding constants

**Hash Size:** 16 bytes (128 bits)

**Note:** The implementation explicitly warns against using these routines for secure functionality. They are derived from the RSA MD5 Message-Digest Algorithm but with custom padding and initialization differences between retail and debug builds. The hash covers container data starting from the `Version` field in the container header.

---

## Directory: lib/DxilPdbInfo

**Purpose:** Provides helper functionality for writing compressed PDB information into DXIL container parts. This supports shader debugging by embedding source info, compilation arguments, and other metadata into a dedicated PDB container part.

**Files:**
| File | Purpose |
|------|---------|
| `DxilPdbInfoWriter.h` (include) | `WritePdbInfoPart()` function declaration |
| `DxilPdbInfoWriter.cpp` | Writes a valid `hlsl::DxilShaderPDBInfo` part with zlib compression |

**Key Function:**
- `WritePdbInfoPart(IMalloc *pMalloc, const void *pUncompressedPdbInfoData, size_t size, std::vector<char> *outBuffer)`
  - Creates a `DxilShaderPDBInfo` header with version and compression type (currently hardcoded to Zlib)
  - Compresses the input data using `ZlibCompressAppend`
  - Writes the header followed by compressed data to `outBuffer`

**Data Format:**
The resulting blob starts with a `DxilShaderPDBInfo` header:
- `Version` — `DxilShaderPDBInfoVersion`
- `CompressionType` — currently `Zlib`
- `SizeInBytes` — size of the compressed data following the header
- `UncompressedSizeInBytes` — original uncompressed size

This replaces the older `DxilSourceInfo` format and uses the RDAT reflection format for the actual PDB content.

---

## Key Files and Their Purposes

| Directory | File | Role |
|-----------|------|------|
| `lib/DxilContainer` | `DxilContainer.h` | **Format specification** — defines the binary layout of DXIL containers |
| `lib/DxilContainer` | `DxilContainerAssembler.cpp` | **Serialization engine** — converts LLVM modules and metadata into container parts |
| `lib/DxilContainer` | `DxcContainerBuilder.cpp` | **Container modification** — implements the public COM API for adding/removing container parts |
| `lib/DxilContainer` | `DxilContainerReader.cpp` | **Container parsing** — reads and enumerates parts from existing containers |
| `lib/DxilContainer` | `DxilRDATBuilder.cpp` | **Reflection data builder** — constructs runtime data tables for shader reflection |
| `lib/DxilValidation` | `DxilValidation.cpp` | **Module validator** — checks DXIL instructions, signatures, and shader model compliance |
| `lib/DxilValidation` | `DxilContainerValidation.cpp` | **Container validator** — verifies container parts are consistent with the module |
| `lib/DxilValidation` | `DxilValidationUtils.h` | **Validation framework** — `ValidationContext` and diagnostic infrastructure |
| `lib/DxilRootSignature` | `DxilRootSignature.h` | **Root signature API** — public structures and functions for root signature manipulation |
| `lib/DxilRootSignature` | `DxilRootSignatureValidator.cpp` | **Root signature validator** — overlap detection and shader binding verification |
| `lib/DxilRootSignature` | `DxilRootSignatureSerializer.cpp` | **Root signature serialization** — binary format encoding |
| `lib/DxilHash` | `DxilHash.cpp` | **Container hashing** — MD5-derived retail/debug hash functions |
| `lib/DxilPdbInfo` | `DxilPdbInfoWriter.cpp` | **PDB part writer** — compresses and writes PDB info into containers |

---

## Component Interactions

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DXIL Container Format                         │
│  (lib/DxilContainer: DxilContainer.h, DxilContainerAssembler.cpp)   │
└─────────────────────────────────────────────────────────────────────┘
                                ▲
                                │ reads/writes
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌──────────────┐      ┌─────────────────┐      ┌──────────────┐
│  Container   │      │   Container     │      │   Container  │
│   Builder    │      │     Reader      │      │  Validation  │
│(DxcContainer │      │(DxilContainer   │      │(DxilContainer│
│   Builder)   │      │     Reader)     │      │ Validation)  │
└──────────────┘      └─────────────────┘      └──────────────┘
        │                       ▲                       ▲
        │ uses                  │ uses                  │ validates
        ▼                       │                       │
┌──────────────┐                │                       │
│  DxilHash    │◄───────────────┘                       │
│(ComputeHash  │ computes container hash                │
│ Retail/Debug)│                                        │
└──────────────┘                                        │
                                                        │
┌───────────────────────────────────────────────────────┘
│
▼
┌─────────────────────────────────────────────────────────────────────┐
│                         DXIL Validation                              │
│  (lib/DxilValidation: DxilValidation.cpp, DxilContainerValidation.cpp)│
│  - Validates DXIL instructions, signatures, resources               │
│  - Validates container parts (PSV, RDAT, signatures) match module   │
└─────────────────────────────────────────────────────────────────────┘
                                ▲
                                │ validates
                                │
┌───────────────────────────────┴─────────────────────────────────────┐
│                         DXIL Module / LLVM IR                        │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ generates/uses
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       Root Signature Handling                          │
│  (lib/DxilRootSignature: DxilRootSignature.cpp,                      │
│   DxilRootSignatureValidator.cpp, DxilRootSignatureSerializer.cpp)   │
│  - Defines root signature descriptors                                │
│  - Serializes/deserializes root signatures                           │
│  - Validates root signature bindings against shader PSV              │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ writes
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       PDB / Source Info                              │
│  (lib/DxilPdbInfo: DxilPdbInfoWriter.cpp)                            │
│  - Compresses and writes PDB info parts using zlib                   │
└─────────────────────────────────────────────────────────────────────┘
```

**Interaction Details:**

1. **Container Builder ↔ Hash:** `DxcContainerBuilder` calls `ComputeHashRetail` or `ComputeHashDebug` (from `DxilHash`) after serializing a container to compute the container hash stored in the header.

2. **Container Assembler ↔ Root Signature:** `DxilContainerAssembler` creates root signature writer parts via `NewRootSignatureWriter()` and validates root signatures against shader PSV data during container serialization.

3. **Validation ↔ Container:** `DxilContainerValidation` uses `DxilContainerReader` and part writer factories from `DxilContainerAssembler` to regenerate expected container parts from the module and compare them against the actual container blobs.

4. **Validation ↔ Root Signature:** `DxilRootSignatureValidator` is used to verify that root signatures embedded in containers are valid and that shader resource bindings (from PSV) are fully covered by the root signature.

5. **Container ↔ PDB:** `DxilPdbInfoWriter` produces `PDBI` container parts that are added to the container by the assembler or builder.

6. **PSV ↔ RDAT:** Both are container parts generated by `DxilContainerAssembler`. PSV tracks pipeline state (signatures, resource bindings, thread counts), while RDAT tracks runtime reflection data (subobjects, function tables, etc.).

---

## Summary

The DXIL infrastructure libraries provide the complete lifecycle support for DXIL shader binaries:

| Concern | Library | Responsibility |
|---------|---------|---------------|
| **Format** | `lib/DxilContainer` | Defines and implements the DXIL container binary format — a structured archive of shader parts (bitcode, signatures, PSV, RDAT, debug info, etc.) |
| **Validation** | `lib/DxilValidation` | Ensures DXIL modules and containers are correct, conformant, and internally consistent. This is critical for runtime security and correctness |
| **Root Signatures** | `lib/DxilRootSignature` | Manages the descriptor binding model for DirectX 12 shaders: parsing, serialization, conversion, and validation |
| **Hashing** | `lib/DxilHash` | Provides container integrity hashing (MD5-derived) used to validate container contents have not been tampered with |
| **Debug Info** | `lib/DxilPdbInfo` | Supports shader debugging by writing compressed PDB metadata into containers |

These libraries are tightly coupled through the container format but are layered logically:
- **DxilHash** is a low-level utility used by the container builder.
- **DxilRootSignature** operates independently but its serialized form is a container part.
- **DxilContainer** provides the packaging layer that assembles all parts into a final binary.
- **DxilValidation** sits above all of them, verifying both the module semantics and the container structural integrity.
- **DxilPdbInfo** provides optional debug metadata that enhances the container with source-level information.

Together, these components enable the DirectX Shader Compiler to produce validated, portable, and debuggable DXIL shader binaries for the DirectX 12 runtime.
