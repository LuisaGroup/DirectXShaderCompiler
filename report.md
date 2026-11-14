# Performance-oriented features in the recent DXC changes

## Scope and method

This report reviews the **35 commits ending at `8e1d641c3`** (from
`9fae1f3426dc40f27f12bc79e98b8bfc6673c121` through
`8e1d641c3323ba29bf851e1b687fca1b958bd713`, inclusive). It also uses the
current `docs/ReleaseNotes.md`, `docs/SPIR-V.rst`,
`examples/spirv-extensions/README.md`, the feature examples, and
`SUBMODULES.md`.

The recent work is predominantly SPIR-V/Vulkan functionality. The useful
performance distinction is between:

- **Runtime opportunities:** fewer instructions, less synchronization, better
  memory locality, specialized hardware, or smaller working sets.
- **Indirect benefits:** smaller modules, fewer shader variants, less binding
  overhead, or better optimizer/toolchain behavior.
- **Enabling or incomplete work:** a new encoding or API that may enable a
  future optimization but does not itself establish a speedup.

No GPU benchmark was run. The repository's tests primarily check generated
SPIR-V and validation; several examples explicitly say that no CI driver
executes the feature. Actual gains therefore depend on the device, driver,
host setup, shader shape, and measurement.

## Submodule update performed first

The URLs in `.gitmodules` were applied with `git submodule sync --recursive`.
The LuisaGroup redirects were preserved intentionally; they were not replaced
with KhronosGroup or Microsoft URLs. Each tracked submodule was fetched from
its configured `origin/main` and checked out at that remote revision.

| Submodule | Remote used | Latest revision checked out | Change from the repository pin |
|---|---|---|---|
| `external/DirectX-Headers` | `https://github.com/LuisaGroup/DirectX-Headers` | `61c7718954ec73dbdd43c723240fe1a0452a3724` | Already the latest; restored the worktree to the intended pin |
| `external/SPIRV-Headers` | `https://github.com/LuisaGroup/SPIRV-Headers` | `6efe5ae6b7c6ad29da3f2cc3f164b9c3d72b78b1` | Already the latest; restored the worktree to the intended pin |
| `external/SPIRV-Tools` | `https://github.com/LuisaGroup/SPIRV-Tools` | `c6bbc3aa899353b7cab3978b9098f9c78677d437` | Advanced from `3eb9e88ee15c391811318eaadb08e1aeb044e9fc`; the new gitlink is staged |

`git submodule status` reports all three without a leading `+` or `-`, and
ancestry checks confirm that each checked-out revision is reachable from its
LuisaGroup `origin/main`. `SUBMODULES.md` was updated with the new SPIRV-Tools
pin and current fork comparison.

`external/googletest` remains on `https://github.com/google/googletest`, as
required by the repository guidance. It is declared in `.gitmodules` but is not
a tracked gitlink in this checkout (the directory is ignored by `external/*`),
so it is not one of the three submodules reported by `git submodule status` or
updated as a parent-repository pin.

The SPIRV-Tools update also brings in upstream optimizer work, including
`9292223b` (a uniform-buffer-to-push-constant pass) and local optimization
fixes. Those are dependency capabilities, not evidence that DXC automatically
runs a new pass or gets a runtime speedup; no corresponding DXC pass-pipeline
change was found in the 35 reviewed commits.

## Highest-value candidates to try first

For a performance investigation, the most concrete starting points are:

1. **`VK_KHR_maintenance9` narrow bitwise operations** and
   **`SPV_VALVE_mixed_float_dot_product`** for direct instruction-count and
   temporary-value reductions.
2. **Split barriers** and **multiple wait queues** for compute shaders whose
   bottleneck is synchronization or memory latency rather than arithmetic.
3. **Invocation reordering** and **opacity micromaps** for divergent or
   alpha-tested ray-tracing workloads.
4. **QCOM tile shading** and **image-processing3 gathers** for tile-resident
   post-processing and filter kernels on supporting Adreno devices.
5. **Cooperative vectors/matrices and reduced-precision types** for ML or
   other bandwidth-/matrix-heavy kernels, provided the target device exposes
   the exact type/layout/feature combination.

The rest of this report explains the mechanism and the limits of each
candidate.

## 1. Direct shader-runtime opportunities

### Reduce arithmetic, address, and synchronization work

- **`VK_KHR_maintenance9` — native narrow and 64-bit bitwise operations
  (`412b1d301`).** With `-fspv-enable-maintenance9`, `reversebits` and
  `countbits` can use the operand's natural width instead of emulation. The
  documentation gives a 16-bit reversal as a widen/reverse/shift/truncate
  sequence versus one `OpBitReverse`, a 64-bit reversal as nine instructions
  versus one, and 64-bit `countbits` as six instructions versus one. This is
  one of the clearest potential ALU and instruction-issue wins in the review.
  It is opt-in and requires the host's `VK_KHR_maintenance9` feature. The
  ordinary HLSL intrinsics do not expose every legal 8-bit form, and
  `firstbitlow`/`firstbithigh` are not helped; retain the default path for
  devices without the feature.

- **`SPV_VALVE_mixed_float_dot_product` — fused `dot2add`
  (`64e7cb8e7`).** `dot2add(half2, half2, float)` changes from an
  `OpFMul`/`OpFConvert`/component-extract/`OpFAdd` sequence to one
  `OpFDot2MixAcc32VALVE`. The example describes this as six instructions to
  one, avoiding materialization of the FP32 operand copies and reducing
  rounding as well as instruction work. It requires 16-bit types and the
  vendor-specific `VK_VALVE_shader_mixed_float_dot_product` device feature.
  The single-rounding result is numerically different from the old lowering,
  so validate accuracy as well as speed.

- **`SPV_KHR_fma` — core 32-bit fused multiply-add (`9fae1f342`).** With
  `-fspv-extension=SPV_KHR_fma`, 32-bit HLSL `mad()` uses `OpFmaKHR` rather
  than the `GLSL.std.450` `Fma` extended instruction. A core FMA can map more
  directly to an implementation's fused arithmetic path while preserving one
  rounding. This is **not** a new contraction of ordinary `a * b + c`: the
  change applies to the existing fused `mad()` operation, and half/double
  paths are not covered. The host must support `VK_KHR_shader_fma` and the
  float32 feature; measure against the existing extended-instruction form.

- **`SPV_EXT_split_barrier` — arrive/wait separation (`4fc083e8a`).**
  `vk::SplitBarrierArrive()` and `vk::SplitBarrierWait()` let a compute
  invocation publish its work, perform independent work, and wait only after
  that work. This can hide the latency of the slowest invocation and reduce
  idle time compared with an immediately blocking
  `GroupMemoryBarrierWithGroupSync()`. The work placed between the two calls
  must not depend on other invocations' published data. Pairing, scopes, and
  acquire/release ordering are the shader author's responsibility, and the
  extension reserves some shared memory. Use
  `-fspv-extension=SPV_EXT_split_barrier` and check the device properties.

- **`SPV_QCOM_multiple_wait_queues` — memory-latency loop hint
  (`caf87e769`).** `[[vk::multiple_wait_queues]]` or
  `[[vk::multiple_wait_queues(N)]]` on a loop permits the implementation to
  keep several memory fills in flight instead of relying on unrolling. This
  can improve latency hiding while avoiding the register pressure and code
  growth of a large unroll, especially in loops of cooperative-matrix
  multiply-adds or streamed loads. It is only a hint: a driver may ignore it,
  it supplies no memory ordering, and the best queue count is a tuning
  parameter. Enable `SPV_QCOM_multiple_wait_queues` and honor
  `maxShaderWaitQueues`.

- **Partitioned wave operations through `SPV_EXT_shader_subgroup_partitioned`
  (`766502b02`).** The commit adds the standardized EXT extension spelling;
  the underlying `WaveMatch`/`WaveMultiPrefix*` instruction stream is shared
  with the NV spelling. Where those operations replace a shared-memory
  reduction, they can eliminate explicit loops and barriers and allow
  independent partitions of a wave to proceed without serializing the whole
  group. The example specifically uses independent sum and product scans.
  This is an enabling/selection improvement rather than a newly invented
  opcode in this commit; it requires SPIR-V 1.3 or later and the corresponding
  EXT or NV device feature.

### Texture, tile, and memory-locality work

- **`SPV_QCOM_image_processing3` — mode-selected hardware gathers
  (`f11f8057b`).** `OpImageGatherQCOM` provides 4x1, diamond, H2, and V2
  footprints. On the Adreno implementations for which it was designed, a
  matching four-tap filter can use one dedicated gather instead of four taps
  or a reprogrammed ordinary gather. This can reduce texture instruction
  count and improve locality for sharpening, upscaling, and similar kernels.
  These are gathers, not weighted filters: the shader still performs its own
  arithmetic and must respect each mode's lane order. It requires a combined
  image-processing sampler, the appropriate QCOM feature, and SPIR-V 1.4 or
  newer (`-fspv-target-env=vulkan1.1spirv1.4` or later).

- **`SPV_QCOM_tile_shading` — direct on-chip tile-memory access
  (`121a02c82`).** Tile attachments let fragment and compute shaders access
  attachment data within the current tile, allowing resolve and post-process
  work to stay in on-chip tile memory instead of making a system-memory round
  trip. `TileShadingRateQCOM` also supports per-tile compute dispatch, and
  `NonCoherentTileAttachmentReadQCOM` can trade rasterization ordering for a
  faster implementation when that relaxed ordering is acceptable. The host
  must create the appropriate tile-shading render pass/dispatch and enable the
  exact feature bits; coherence and apron limits are not compiler-checkable.

### Ray-tracing traversal and shading

- **`SPV_EXT_shader_invocation_reorder` — improve traversal coherence
  (`c7251e087`).** Reorder hints allow an implementation to group invocations
  with similar hit objects so that a reordered wave is more likely to traverse
  related acceleration-structure nodes and geometry. The intended benefit is
  better cache locality and fewer divergent memory accesses, particularly for
  many short, divergent shadow/AO/GI rays. Reordering is a request, not a
  semantic guarantee. The current HLSL landing still cannot trace into a hit
  object or record one from a ray query, so a full traced-hit workflow is not
  exposed yet; treat this as a promising but incomplete optimization surface,
  not a turnkey speedup for every ray tracer.

- **`SPV_KHR_opacity_micromap` — resolve fine-grained opacity during traversal
  (`6a9439513`).** Per-micro-triangle opacity state lets the traversal unit
  resolve opaque/transparent regions that would otherwise require alpha-test
  any-hit shader invocations. For foliage, fences, and similar geometry this
  can remove substantial any-hit shading work and its associated divergence.
  The acceleration structure must actually contain micromaps, and the host
  must enable the feature and the relevant pipeline/ray-query options. The
  compiler change emits the execution mode; it does not build the micromap or
  guarantee a traversal speedup.

- **`SPV_NV_linear_swept_spheres` — analytic sphere/LSS geometry
  (`44fadd01f`).** Spheres and linear swept spheres can be intersected
  analytically instead of being tessellated into triangles. For particles,
  point clouds, hair, and curves this can reduce geometry/memory footprint,
  acceleration-structure build work, and triangle traversal overhead, while
  also avoiding tessellated-normal interpolation in shading. The host must
  build sphere/LSS acceleration structures; merely using the new ray-query
  accessors cannot create those savings. Some array-returning and hit-object
  accessors remain unexposed.

- **`SPV_NV_cluster_acceleration_structure` — cache-friendly hit grouping
  (`9a4b6e3e3`).** A cluster ID is shared by the triangles in a cluster, so a
  material/LOD/shading table indexed by it can be smaller and more cache
  friendly than a per-primitive-index scheme. This is an indirect shading and
  memory-locality benefit, not a claim that every cluster acceleration
  structure traverses faster. The host must build and reference clustered
  geometry, and the result is undefined for ordinary triangle geometry.

## 2. ML, matrix, vector, and reduced-precision opportunities

- **`SPV_NV_cooperative_vector` — implementation-managed matrix-vector work
  (`fcc1e7573`).** The opaque vector plus `MatrixMul`, `MatrixMulAdd`, and
  training accumulators lets the implementation choose the vector register
  layout and stream weight matrices instead of requiring the shader to spell
  out a per-component layout. This is aimed at ML inference/training and can
  replace manual vector/matrix loops with specialized operations. Inputs and
  matrices currently need suitable array storage, commonly staged through
  `groupshared`; that staging and the required host-queried type/layout/shape
  limits can outweigh the benefit if used for tiny or unfriendly workloads.
  No CI driver executes the example, so benchmark on the target device.

- **`SPV_KHR_bfloat16` dot product and cooperative matrix support
  (`b83829185`).** `bfloat16_t` provides float-like exponent range with a
  16-bit storage footprint, reducing weight/activation bandwidth relative to
  float32. The new `OpDot` and bfloat16 cooperative-matrix capabilities make
  it possible to keep supported dot/MMA operations in that format rather than
  widening every operand to float first. General arithmetic is not defined
  for the type, results have reduced precision, and stage I/O is restricted;
  the host must enable the individual type/dot/matrix features and support
  the requested matrix shape.

- **`SPV_EXT_float8` — one-byte E4M3/E5M2 storage (`0469f953f`).**
  `float8_e4m3_t` and `float8_e5m2_t` use one-byte elements with one-byte
  buffer strides. For suitable weights, activations, or other bounded data,
  this can halve storage versus FP16 and quarter it versus FP32, reducing
  memory traffic and cache pressure. These are storage/conversion types, not
  general arithmetic types: operations require conversion to a wider type,
  and float8 cooperative matrices are not implemented. The performance win is
  therefore primarily a bandwidth/working-set win, and conversion cost and
  precision must be measured.

- **`SPV_EXT_ocp_microscaling_types` — packed sub-byte values and extraction
  (`55990b53b`).** E2M1, E3M2, E2M3, and E8M0 formats allow very compact
  micro-scaled representations; `OpBitcastExtractEXT` reads values from packed
  integer words. This can reduce storage and bandwidth for quantized/ML data
  when the packed representation is retained through the memory system.
  Four-/six-bit values are not directly addressable buffer element types, so
  the shader must load packed words, extract, widen, and apply scaling itself.
  Block-scale arithmetic, tensors, and MMA are not implemented; this is not by
  itself a hardware micro-scaled matrix-multiply optimization.

- **`SPV_ARM_cooperative_matrix_layouts` — native blocked/interleaved storage
  (`4e3a8f173`).** The Arm row/column blocked-interleaved layouts match the
  64-byte-block form used by some Arm matrix implementations. Using the
  native layout can avoid manual packing/reformatting and make cooperative
  matrix loads/stores more efficient, particularly when a producer and
  consumer share the layout. It is device-specific, has strict shape and
  stride rules, and requires the producer to write exactly the same layout;
  the classic row-/column-major path remains the portable fallback.

- **`SPV_ARM_graph` + `SPV_ARM_tensors` + TOSA (`791477e8f`, `5aec80b99`,
  `9451f1a02`).** Together these describe dataflow over complete tensors and
  allow a host to create an Arm data-graph pipeline executed by an accelerator,
  rather than launching equivalent work as per-invocation shader code. TOSA
  supplies the tensor operations, while the graph/tensor extensions supply the
  execution structure and I/O. This can expose operator-level scheduling and
  specialized tensor hardware that ordinary scalar/vector lowering cannot
  express. It requires host-side tensor/graph creation and implementation
  support; only 47 of TOSA's 66 operations are declared, tensor shapes and
  standalone tensor resources have limitations, and the tests validate
  encodings rather than numeric execution.

- **`SPV_EXT_long_vector` — retain wide values as one vector
  (`a0041bdd3`).** `LongVector<T,N>` avoids manually representing an
  8-/16-component value as an array or several `float4`s. The implementation
  chooses how the wide value is executed, so there is potential for better
  backend register/instruction selection and less composite bookkeeping.
  The current HLSL surface is deliberately only construction and element
  access (`Concat`, `Get`, `Set`); arithmetic still happens on ordinary
  vectors, buffer layout support is incomplete, and the device component limit
  applies. Treat this as a backend/code-shape opportunity, not a guaranteed
  wide-arithmetic speedup.

- **`SPV_EXT_cooperative_matrix_maintenance1` — keep values in matrix form
  (`e357215fb`).** `ConvertUse` changes an accumulator's cooperative-matrix
  role without touching its values, which can avoid storing and reloading a
  tile between stages of a chained GEMM. That is the useful performance case
  in the example. `Reduce` and `PerElementOp` could also replace manual
  reductions/element processing, but their compiler-synthesized callback
  bodies currently return `OpUndef`; they are encoding demonstrations, not
  usable numeric optimizations yet. Matrix shapes, uses, and device support
  remain mandatory checks for the host.

## 3. Indirect performance and deployment benefits

- **`SPV_KHR_constant_data` — smaller constant-array modules (`dcbcaafc0`).**
  `-fspv-constant-data[=<threshold>]` emits one packed `OpConstantDataKHR`
  instead of per-element constants plus `OpConstantComposite`. The documented
  256-entry `uint` example shrinks from 5,860 to 1,816 bytes with the default
  pipeline (and from 6,128 to 2,084 bytes with `-fcgl`). Smaller modules can
  reduce shader upload/parse overhead, disk and cache footprint, and
  distribution size; this is not evidence of fewer arithmetic instructions at
  runtime. The option is off by default, has an element threshold and a
  65,532-word instruction limit, and requires `SPV_KHR_constant_data` on the
  host.

- **`SPV_NV_push_constant_bank` — more root-descriptor data without extra
  descriptor sets (`03e59baeb`).** Bank and offset decorations let an NVIDIA
  descriptor-heap application spread push data over hardware banks. This can
  reduce descriptor-set/pipeline-binding work or the need for additional
  descriptor-set-per-shader arrangements when the host is designed around
  that mapping. It does not automatically make a shader's arithmetic faster;
  bank count, size, API placement, and shader decorations must agree.

- **Unsized uniform-buffer arrays (`dd37b74bc`).**
  `-fspv-enable-uniform-buffer-unsized-array` permits a trailing runtime array
  in a `ConstantBuffer`, allowing one shader to serve different data-set sizes.
  The likely benefit is fewer shader variants, recompiles, and pipeline-cache
  entries, plus less duplication of uniform layouts—not a direct execution
  speedup. The application supplies the effective length and descriptor range;
  block copies, `OpArrayLength`, and several other uses are intentionally
  rejected.

- **64-bit indexing (`be412bcb5`) is a range feature, not a general
  optimization.** It can avoid application workarounds for storage buffers
  larger than 4 GiB, but the documentation explicitly warns that 64-bit
  indexing can cost performance on some implementations. Keep a 32-bit variant
  for hot shaders that do not need the range, and use
  `-fspv-enable-64bit-indexing` only when the address-space requirement
  justifies it.

## 4. Not counted as current performance wins

The following were reviewed but should not be presented as established
optimizations:

- **`SPV_NV_cooperative_matrix_decode_vector` (`849aa1434`).** Vector decoding
  could eventually reduce decode-callback invocations by filling several
  adjacent matrix elements per call. In this landing, however, the synthesized
  decode functions return `OpUndef`, so only the encoding is defined. It is
  not a usable performance implementation yet.
- **`VK_KHR_maintenance8` (`4b2bd49c0`).** This fixes validation of dynamic
  image offsets and signed remainder; it adds no module instruction or new
  runtime optimization.
- **`VK_KHR_maintenance12` (`e88ae509f`).** This documents and tests the
  existing `NonUniform` machinery for push-constant indexing. It improves
  expressiveness and can avoid source-level workarounds, but does not itself
  change the generated algorithm or guarantee a speedup.
- **`SPV_KHR_abort` (`efa24c25d`).** This is a device-fault/debugging feature,
  not a performance feature; an abort can lose the device.
- **The submodule revert/re-land, Linux compatibility shim, and example-index
  commits (`8f2689c14`, `a1c961abe`, `8e1d641c3`, `ee24c4715`, `c9c577a87`).**
  These are dependency, build, or documentation changes. They matter for
  reproducibility and for making the other features buildable, but are not
  independent shader optimizations.

## Practical evaluation guidance

1. Start with a shader whose bottleneck is known: instruction issue, barrier
   stalls, memory latency, texture traffic, traversal divergence, matrix
   throughput, or module size. Select the matching feature rather than
   enabling every extension globally.
2. Compile paired variants with the feature off and on, preserving the
   portable fallback. Inspect the SPIR-V to confirm that the intended opcode,
   execution mode, layout, or loop control actually survives optimization.
3. Check device extensions, feature bits, limits, host resource layouts, and
   pipeline flags before measuring. A successful DXC compile cannot validate
   those host-side conditions.
4. Measure GPU time, memory traffic/cache behavior where available, register
   pressure, shared-memory use, and module/upload size. For reduced precision
   and fused operations, also compare numerical results; several paths change
   rounding or require explicit conversions.
5. Treat hints and encoding-only landings as experiments. In particular, do
   not use the `OpUndef` decode/reduction callbacks as evidence of a correct or
   faster kernel.

## Build and smoke-test verification

The updated dependency set was verified as follows:

- `cmake --build build/Release --target dxc --parallel 2`, run through the
  installed Visual Studio `vcvars64.bat`, completed successfully (`1301/1301`,
  exit code 0). The plain-shell attempt was not a valid verification because
  it lacked the MSVC standard-library environment; the vcvars run is the
  result recorded here.
- The rebuilt `build/Release/bin/dxc.exe` compiled and validated the
  `ext-split-barrier.hlsl`, `khr-maintenance9.hlsl`, and
  `khr-shader-fma.hlsl` examples with their documented options. All three
  exited 0 and produced non-empty SPIR-V files (1,984, 2,720, and 1,692 bytes,
  respectively).
- `git ls-remote` matched the three checked-out hashes above, all submodule
  worktrees were clean, `git submodule status` had no `+`/`-` markers, and
  `git diff --check` passed. These are compile/validation checks, not GPU
  execution benchmarks.

## Sources

- The 35 commit messages and changed-file inventory in the range listed above.
- `docs/ReleaseNotes.md`, **Upcoming Release / SPIR-V** entries for the new
  extensions and options.
- `docs/SPIR-V.rst`, especially **Fused multiply-add**, **Split barriers**,
  **Multiple wait queues**, **Tile shading**, **Long vectors**, **Cooperative
  vectors**, **Opacity micromaps**, **Cluster acceleration structures**,
  **Linear swept spheres**, **Invocation reordering**, **Narrow integer
  bitwise operations**, **BFloat16**, **Float8**, **OCP micro-scaling types**,
  **Image gather modes**, **Constant data arrays**, **Arm cooperative matrix
  memory layouts**, **Cooperative matrix maintenance**, **Arm tensors**, and
  **Arm data graphs**.
- `examples/spirv-extensions/README.md` and the corresponding self-checking
  HLSL examples, which record compile flags, generated encodings, host
  requirements, and feature-specific limitations.
- `.gitmodules` and `SUBMODULES.md` for the remote-selection and pin-update
  rules.
