# Optimization Summary — Quick Reference

> **Audience:** Quick lookup for common optimization tasks.
> **Last Updated:** Auto-generated from DXC source analysis.

---

## Quick Reference: Optimization Levels

| Level | DXIL Pipeline | SPIR-V Pipeline |
|-------|--------------|-----------------|
| `-O0` | Minimal: HLSL lowering + finalization only | No optimization; legalization + trimming only |
| `-O1` | HLSL lowering + standard LLVM scalar opts | `RegisterPerformancePasses()` (1 iteration if converged) |
| `-O2` | O1 + Aggressive Dxil Opt (fixed-point, 5 iters max) | Same as O1 |
| `-O3` | O2 + extra loop unrolling | Same as O1 |
| `-Od` | Same as `-O0` | Same as `-O0` |

---

## Quick Reference: Key Flags

### General Optimization Flags

| Flag | Effect |
|------|--------|
| `-O0` / `-O1` / `-O2` / `-O3` | Optimization level |
| `-Od` | Disable optimizations |
| `-opt_dump` | Print optimizer configuration |
| `-ftime-report` | Print timing report |
| `-ftime-trace=<file>` | Chrome-compatible trace output |

### DXIL-Specific Flags

| Flag | Effect |
|------|--------|
| `-Oconfig_dxil <pass1,pass2,...>` | Custom aggressive optimizer pass list |
| `-dxil_opt_max_iterations <N>` | Max fixed-point iterations (default 5) |
| `-dxil_opt_print_each` | Print IR after each aggressive iteration |
| `-dxil_opt_validate_each` | Validate IR after each iteration |
| `-opt_enable <toggle>` | Enable specific optimization toggle |
| `-opt_disable <toggle>` | Disable specific optimization toggle |
| `-memdep_block_scan_limit <N>` | DSE scan limit |
| `-res_may_alias` | Resources may alias (enables GVN hoisting) |
| `-enable_lifetime_markers` | Enable lifetime intrinsics |
| `-force_zero_store_lifetimes` | Force zero store lifetimes |
| `-Gfa` | Avoid flow control |
| `-Gfp` | Prefer flow control |
| `-Ges` | Enable strict mode |
| `-Gis` | IEEE strict mode |

### SPIR-V-Specific Flags

| Flag | Effect |
|------|--------|
| `-Oconfig=<flags>` | Custom SPIRV-Tools optimization flags (comma-separated) |
| `-fspv-preserve-bindings` | Preserve all binding numbers during optimization |
| `-fspv-preserve-interface` | Preserve interface variables |
| `-fspv-flatten-resource-arrays` | Flatten resource arrays (triggers legalization) |
| `-fspv-reduce-load-size` | Reduce load sizes (triggers legalization) |
| `-fspv-print-all` | Dump SPIR-V before/after each pass |
| `-fspv-target-env=<env>` | Target SPIR-V environment |
| `-fspv-max-id=<N>` | Maximum result ID bound |
| `-fspv-use-legacy-buffer-layout` | Use legacy buffer matrix layout |
| `-fspv-signature-packing` | Enable signature packing |
| `-Vd` | Disable validation |

---

## Quick Reference: Common Tasks

### Reduce Binary Size

1. Ensure `-O2` or `-O3` is used
2. For DXIL: try `-dxil_opt_max_iterations 10` for more aggressive convergence
3. For SPIR-V: ensure `-fspv-flatten-resource-arrays` if using arrays
4. Consider `-opt_enable enable_aggressive_reassociation`

### Debug a Misoptimization (Bisect Passes)

1. Start at `-O0` to confirm the issue is optimization-related
2. For DXIL: use `-opt_dump` to see all passes, then `-opt_disable <toggle>` to narrow down
3. Use `-print_before=<pass>` and `-print_after=<pass>` to inspect IR state
4. For SPIR-V: use `-fcgl` to inspect raw emitted code, then add `-Oconfig` passes incrementally

### Speed Up Compilation

1. Use `-O1` instead of `-O2`/`-O3`
2. Disable aggressive optimization: `-dxil_opt_max_iterations 0`
3. Disable vectorization (not applicable to DXIL)
4. Use `-T` target profile for faster codegen

### Enable Extra Optimizations

1. `-opt_enable enable_aggressive_reassociation` — Extra reassociate+GVN pass
2. `-opt_enable gvn` — Ensure GVN is enabled (it is by default)
3. `-opt_enable sink` — Enable instruction sinking
4. `-opt_enable structurize_loop_exits_for_unroll` — Better loop unrolling
5. For SPIR-V: use `-Oconfig` to add custom passes

---

## Available Optimization Toggles

These can be used with `-opt_enable <name>` / `-opt_disable <name>`:

| Toggle Name | Default | Description |
|-------------|---------|-------------|
| `gvn` | ON | Global Value Numbering |
| `sink` | ON | Instruction sinking |
| `structurize_loop_exits_for_unroll` | OFF | Structurize loop exits for unrolling |
| `debug_nops` | OFF | Insert debug NOPs |
| `lifetime_markers` | OFF | Lifetime intrinsics |
| `partial_lifetime_markers` | OFF | Partial lifetime markers |
| `enable_aggressive_reassociation` | OFF | Extra reassociation after GVN |

---

## Key Files Map

| What | Where |
|------|-------|
| Optimization routing | `tools/clang/lib/CodeGen/BackendUtil.cpp:319-371` |
| DXIL pass pipeline | `lib/Transforms/IPO/PassManagerBuilder.cpp:211-736` |
| DXIL aggressive optimizer | `lib/HLSL/DxilAggressiveOptimize.cpp` |
| SPIR-V optimize entry | `tools/clang/lib/SPIRV/SpirvEmitter.cpp:960-1045` |
| SPIR-V optimize impl | `tools/clang/lib/SPIRV/SpirvEmitter.cpp:16789-16847` |
| SPIR-V legalize impl | `tools/clang/lib/SPIRV/SpirvEmitter.cpp:16849-16919` |
| Optimization toggles | `include/dxc/Support/HLSLOptions.h:239` |
| SPIR-V options | `include/dxc/Support/SPIRVOptions.h` |
| dxopt tool | `tools/clang/tools/dxopt/dxopt.cpp` |
| IDxcOptimizer impl | `lib/HLSL/DxcOptimizer.cpp` |
