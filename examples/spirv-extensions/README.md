# HLSL examples for Vulkan / SPIR-V extensions

One self-checking example per Vulkan extension feature implemented in this tree. Every
file starts with a `// RUN:` line that compiles it with the flags it needs (this is a
compile-and-validate check, not a FileCheck test — the golden-output tests live in
`tools/clang/test/CodeGenSPIRV/`).

Compile any example directly:

```
dxc -T cs_6_0 -E main -spirv -fspv-extension=SPV_KHR_shader_fma khr-shader-fma.hlsl -Fo out.spv
```

or run all of them at once (the runner substitutes `%dxc`/`%s`, and a passing compile
also means SPIRV-Tools accepted the module, because DXC validates everything it emits
unless `-Vd` is passed):

```
python .kimix_cache/tools/run_spirv_tests.py examples/spirv-extensions/*.hlsl
```

Each example's header comment names the Vulkan extension, the device feature bit the
host has to enable, and the SPIR-V encoding that the compiler produces. That host side is
outside the compiler's reach: no compiler test can prove that a driver honours these
features.

| Example | Feature | Compile flags of interest |
|---|---|---|
| `khr-shader-fma.hlsl` | `VK_KHR_shader_fma` → `OpFmaKHR` for a 32-bit fused multiply-add | `-fspv-extension=SPV_KHR_fma` |
| `ext-split-barrier.hlsl` | `VK_EXT_shader_split_barrier` → `OpControlBarrierArriveEXT`/`WaitEXT` | `-fspv-extension=SPV_EXT_split_barrier` |
| `ext-shader-subgroup-partitioned.hlsl` | `VK_EXT_shader_subgroup_partitioned` (EXT spelling of the partitioned-wave capability) | `-fspv-extension=SPV_EXT_shader_subgroup_partitioned` |
| `qcom-multiple-wait-queues.hlsl` | `VK_QCOM_shader_multiple_wait_queues` → `MultipleWaitQueuesQCOM` loop control | `-fspv-extension=SPV_QCOM_multiple_wait_queues` |
| `nv-push-constant-bank.hlsl` | `VK_NV_push_constant_bank` → `BankNV`/`MemberOffsetNV` decorations | `-fspv-extension=SPV_NV_push_constant_bank` |
| `ext-shader-64bit-indexing.hlsl` | `VK_EXT_shader_64bit_indexing` → a storage buffer range larger than 4 GiB: `Shader64BitIndexingEXT` execution mode + capability, 64-bit runtime-array index operands | `-fspv-enable-64bit-indexing` |
| `ext-uniform-buffer-unsized-array.hlsl` | `VK_EXT_shader_uniform_buffer_unsized_array` → runtime array as last `Block` member | `-fspv-enable-uniform-buffer-unsized-array` |
| `khr-bfloat16.hlsl` | `VK_KHR_shader_bfloat16` → `bfloat16_t` storage, `OpDot` with `BFloat16DotProductKHR`, bfloat16 cooperative matrix | `-HV 2021 -enable-16bit-types` |
| `valve-mixed-float-dot-product.hlsl` | `VK_VALVE_shader_mixed_float_dot_product` → `OpFDot2MixAcc32VALVE` for `dot2add` | `-fspv-extension=SPV_VALVE_mixed_float_dot_product` |
| `ext-shader-float8.hlsl` | `VK_EXT_shader_float8` → `float8_e4m3_t` / `float8_e5m2_t` | `-HV 2021` |
| `arm-cooperative-matrix-layouts.hlsl` | `VK_ARM_cooperative_matrix_layouts` → blocked-interleaved cooperative matrix layouts | `-fspv-target-env=vulkan1.3 -HV 2021` |
| `ext-cooperative-matrix-maintenance1.hlsl` | `VK_EXT_cooperative_matrix_maintenance1` → convert-use / reduce / per-element / get-coordinate | `-fspv-target-env=vulkan1.3 -HV 2021` |
| `ext-long-vector.hlsl` | `VK_EXT_shader_long_vector` → `OpTypeVector` with 8/16 components, `OpCompositeConstruct`/`Extract`/`Insert` | `-fspv-target-env=vulkan1.1 -fspv-extension=SPV_EXT_long_vector` |
| `khr-constant-data.hlsl` | `VK_KHR_shader_constant_data` → `OpConstantDataKHR` for a lookup table | `-fspv-constant-data -fspv-extension=SPV_KHR_constant_data` |
| `khr-shader-abort.hlsl` | `VK_KHR_shader_abort` → `OpAbortKHR` | `-fspv-extension=SPV_KHR_abort` |
| `khr-opacity-micromap.hlsl` | `VK_KHR_opacity_micromap` → `OpacityMicromapIdKHR` execution mode | `-fspv-extension=SPV_KHR_opacity_micromap` |
| `ext-invocation-reorder.hlsl` | `VK_EXT_ray_tracing_invocation_reorder` → `OpTypeHitObjectEXT` + `OpReorderThread*EXT` | `-fspv-target-env=vulkan1.2 -fspv-extension=SPV_EXT_shader_invocation_reorder` |
| `nv-cluster-acceleration-structure.hlsl` | `VK_NV_cluster_acceleration_structure` → `OpRayQueryGetIntersectionClusterIdNV` | `-fspv-extension=SPV_NV_cluster_acceleration_structure` |
| `nv-linear-swept-spheres.hlsl` | `VK_NV_ray_tracing_linear_swept_spheres` → sphere/LSS ray-query accessors | `-fspv-extension=SPV_NV_linear_swept_spheres` |
| `qcom-image-processing3.hlsl` | `VK_QCOM_image_processing3` → `OpImageGatherQCOM` | `-fspv-extension=SPV_QCOM_image_processing3` |
| `qcom-tile-shading.hlsl` | `VK_QCOM_tile_shading` → the `TileAttachmentQCOM` storage class, the `TileOffsetQCOM`/`TileDimensionQCOM`/`TileApronSizeQCOM` built-ins and the `TileShadingRateQCOM`/`NonCoherentTileAttachmentReadQCOM` execution modes | `-fspv-extension=SPV_QCOM_tile_shading` |
| `nv-cooperative-vector.hlsl` | `VK_NV_cooperative_vector` → `OpTypeVectorIdEXT`, `OpCooperativeVector{Load,Store,MatrixMul}NV` | `-fspv-extension=SPV_NV_cooperative_vector` |
| `nv-cooperative-matrix-decode-vector.hlsl` | `VK_NV_cooperative_matrix_decode_vector` → the `DecodeVectorFunc` bit of `TensorAddressingOperands` on `OpCooperativeMatrixLoadTensorNV`, plus `OpTypeTensorLayoutNV`/`OpCreateTensorLayoutNV` | `-fspv-target-env=vulkan1.3 -fspv-extension=SPV_NV_cooperative_matrix_decode_vector -fspv-extension=SPV_NV_cooperative_matrix2 -fspv-extension=SPV_NV_tensor_addressing -fspv-extension=SPV_KHR_physical_storage_buffer` |
| `tosa.hlsl` | TOSA 1.0 rev 1 (`TOSA.001000.1` extended instruction set) → `OpExtInstImport "TOSA.001000.1"` + `OpExtInst` over `OpTypeTensorARM`; Arm data-graph ecosystem, no Vulkan extension and no flag | `-HV 2021` |
| `khr-maintenance8.hlsl` | `VK_KHR_maintenance8` (dynamic image offsets; no module surface) | — |
| `khr-maintenance9.hlsl` | `VK_KHR_maintenance9` (narrow-integer bitwise ops) | `-fspv-enable-maintenance9` |
| `khr-maintenance12.hlsl` | `VK_KHR_maintenance12` (non-uniform push-constant indexing) | — |
| `ext-descriptor-heap.hlsl` | `VK_EXT_descriptor_heap` + `SPV_KHR_untyped_pointers` → `ResourceDescriptorHeap` / `SamplerDescriptorHeap` heaps | `-fspv-use-descriptor-heap` |
| `arm-tensors.hlsl` | `VK_ARM_tensors` → `OpTypeTensorARM` + `OpTensorReadARM`/`WriteARM`/`QuerySizeARM`; a tensor *resource* is not expressible from HLSL yet | `-HV 2021 -fspv-extension=SPV_ARM_tensors` |
| `arm-data-graph.hlsl` | `VK_ARM_data_graph` → `OpGraphARM` / `OpGraphEntryPointARM` / `OpGraphInputARM` / `OpGraphSetOutputARM` / `OpGraphEndARM` around a TOSA body; the module keeps its (empty) shader entry point, and the host creates a graph pipeline, not a compute pipeline | `-fspv-extension=SPV_ARM_graph -fspv-extension=SPV_ARM_tensors` |

One already-supported feature is not covered here: `SPV_QCOM_cooperative_matrix_conversion` is
raw-intrinsic only (`__builtin_spv_BitCastArrayQCOM`,
`__builtin_spv_CompositeExtractCoopMatQCOM`, `__builtin_spv_ExtractSubArrayQCOM`) and has no
declared HLSL surface, so there is nothing idiomatic to show; see its tests and `docs/SPIR-V.rst`.
