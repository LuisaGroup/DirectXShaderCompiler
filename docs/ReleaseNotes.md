# DirectX Shader Compiler Redistributable Package

This package contains a copy of the DirectX Shader Compiler redistributable and its associated development headers.

For help getting started, please see:

<https://github.com/microsoft/DirectXShaderCompiler/wiki>

## Licenses

The included licenses apply to the following files:

| License file | Applies to |
|---|---|
|LICENSE-MIT.txt    |d3d12shader.h|
|LICENSE-LLVM.txt   |all other files|

## Changelog

### Upcoming Release
### Upcoming Release
#### SPIR-V
- Added support for `SPV_ARM_tensors` (`VK_ARM_tensors`): the tensor type and the
  three operations that read, write and measure one. Tensors are a new kind of
  resource - a handle to a multi-dimensional array of one scalar element type that
  the host creates and binds, like an image or an acceleration structure with a rank
  and an element type instead of a format and a dimensionality. The new
  `<vk/arm/tensors.h>` header provides `vk::arm::Tensor<ElementType, Rank>` (which
  lowers to `OpTypeTensorARM`, 4163, with the element type and the rank as operands),
  `vk::arm::Coordinates<Rank>` and `vk::arm::MakeCoordinates` (the coordinate operand
  is an `OpTypeArray` of integers whose length equals the rank, built with
  `OpCompositeConstruct`), `TensorRead` (`OpTensorReadARM`, 4164), `TensorWrite`
  (`OpTensorWriteARM`, 4165 - no result id, the value is an ordinary operand) and
  `TensorSize<dimension>` (`OpTensorQuerySizeARM`, 4166). `SPV_ARM_tensors` is now a
  registered, enabled-by-default `FeatureManager` extension, so
  `-fspv-extension=SPV_ARM_tensors` is accepted, the extension is emitted from the
  tensor type through the same `CapabilityVisitor` path as every other extension, and
  an explicit `-fspv-extension` list that omits it is a compile error. A non-scalar
  element type, a rank outside 1..4 (Vulkan only guarantees a `maxTensorDimensionCount`
  of 4), a tensor in stage input/output and a tensor as a member of a uniform, storage
  buffer or push constant block - which is what an HLSL global of tensor type becomes,
  `$Globals` - are diagnosed instead of producing SPIR-V that SPIRV-Tools accepts and
  no host can bind. Not provided: a tensor *resource*, because HLSL has no
  resource-object spelling for a descriptor type; a tensor value currently comes from
  a TOSA operation or an uninitialized local. See `docs/SPIR-V.rst` ("Arm tensors")
  and `examples/spirv-extensions/arm-tensors.hlsl`.
- Added support for the `TOSA.001000.1` extended instruction set: TOSA (Tensor
  Operator Set Architecture) is Arm's operator set for the tensor graphs of the
  ARM data-graph ecosystem, and it is an extended instruction *set* rather than a
  Vulkan extension - it has no extension string, no capability and no
  `-fspv-extension` value. The new `<vk/arm/tosa.h>` header declares 47 of the
  set's 66 operations as `[[vk::ext_instruction(<opcode>, "TOSA.001000.1")]]`
  functions over `vk::arm::tosa::Tensor<ElementType>`, which lowers to
  `OpTypeTensorARM` (4163) and so brings `OpCapability TensorsARM` (4174) and
  `OpExtension "SPV_ARM_tensors"` with it; a call emits `OpExtInst` and nothing
  else, and the import appears only when an operation is used. Operand order is
  the instructions' - `MAXIMUM` takes `nan_mode` first, `TRANSPOSE` its
  permutation first, `MUL`/`NEGATE`/`MATMUL` their attribute operands last - and
  the import string pins TOSA 1.0 rev 1, so a wrong version or an out-of-range
  opcode is refused. Not expressible: the tensor *shape* (only the rank is), a
  constant tensor, a tensor resource, and a data-graph entry point, so a module
  that uses these operations is a compute shader that happens to contain TOSA
  instructions until `SPV_ARM_graph` is implemented. See `docs/SPIR-V.rst`
  ("TOSA tensor operations") and `examples/spirv-extensions/tosa.hlsl`.
- Added support for `SPV_NV_cooperative_matrix_decode_vector`
  (`VK_NV_cooperative_matrix_decode_vector`): the extension adds the
  `DecodeVectorFunc` bit (`0x0004`) to the `TensorAddressingOperands`
  operand of `OpCooperativeMatrixLoadTensorNV` (5367), so a cooperative
  matrix block load can name a function that decodes a vector of
  block-adjacent elements per call instead of the single element
  `DecodeFunc` decodes. The new `<vk/nv/cooperative_matrix_decode_vector.h>`
  header provides `vk::nv::TensorLayout<dim, clampMode>`
  (`OpTypeTensorLayoutNV`, 5370), `vk::nv::CreateTensorLayout`
  (`OpCreateTensorLayoutNV`, 5372) and the block load itself,
  `vk::nv::__builtin_spv_CooperativeMatrixLoadTensorNV<vectorLength>`.
  SPIR-V has no operand form that names an HLSL function, so CodeGen
  synthesizes the `DecodeFunc`/`DecodeVectorFunc` pair with the signature
  SPIRV-Tools requires - the matrix component type (or a 2/4/8-component
  vector of it), a `PhysicalStorageBuffer` pointer, and two arrays of 32-bit
  integers as long as the tensor rank - and passes their ids; only the
  encoding is defined, because the synthesized bodies return `OpUndef`. A
  module declares `CooperativeMatrixDecodeVectorNV` (5447) together with its
  prerequisite `CooperativeMatrixBlockLoadsNV` (5434) and the two tensor
  addressing capabilities, and its memory model becomes `OpMemoryModel
  PhysicalStorageBuffer64 Vulkan`, so the target environment is `vulkan1.3`,
  as for every cooperative matrix feature. The decode-vector extension is
  opt-in (`-fspv-extension=SPV_NV_cooperative_matrix_decode_vector`), while
  `SPV_NV_cooperative_matrix2` and `SPV_NV_tensor_addressing` are now
  registered allow-list entries too; a wrong decode-vector length, a pointer
  operand that is not an array, a tensor rank outside 1..5, an invalid clamp
  mode and a `bfloat16_t` component are diagnostics rather than invalid
  SPIR-V. See `docs/SPIR-V.rst` and
  `examples/spirv-extensions/nv-cooperative-matrix-decode-vector.hlsl`.
- Added support for `SPV_NV_cooperative_vector` (`VK_NV_cooperative_vector`): the
  new `<vk/nv/cooperative_vector.h>` header provides
  `vk::nv::CooperativeVector<T, N>` - an opaque SPIR-V vector whose length and
  component type are part of its type, lowered to `OpTypeVectorIdEXT` (5288) with
  the component count as a 32-bit integer constant - and the extension's six
  instructions as `[[vk::ext_instruction]]` entry points: `Load`
  (`OpCooperativeVectorLoadNV`, 5302), `Store` (5303), `MatrixMul` (5289),
  `MatrixMulAdd` (5292), and the training half's `OuterProductAccumulate` (5290)
  and `ReduceSumAccumulate` (5291). Capabilities are selected per instruction:
  `CooperativeVectorNV` (5394) for the type and the inferencing instructions,
  `CooperativeVectorTrainingNV` (5435) for the two training instructions, so a
  module that only infers stays acceptable on a device that does not implement the
  training half. Both and `OpExtension "SPV_NV_cooperative_vector"` are emitted by
  SPIR-V CodeGen from the type and the instruction, so
  `-fspv-extension=SPV_NV_cooperative_vector` can select and refuse the extension;
  it is opt-in because a driver without `VK_NV_cooperative_vector` rejects the
  module. There is no target-environment gate: the extension carries no SPIR-V
  version requirement, so it also validates at the default `vulkan1.0`. The
  interpretation, `M`, `K`, `MemoryLayout` and `Transpose` operands have to be
  compile-time constants (the extension requires each of them to name a constant
  instruction), and the pointer operands have to address an array in workgroup
  memory, so matrices and accumulators are `groupshared` arrays; a run-time layout,
  a wrong component type, a scalar pointer operand and a `groupshared` cooperative
  vector are diagnostics rather than invalid SPIR-V. This is a SPIR-V-only surface:
  it adds no DXIL opcode and no HLSL type, and it is unrelated to the cooperative
  vector DXIL feature that LinAlg replaced. See `docs/SPIR-V.rst` and
  `examples/spirv-extensions/nv-cooperative-vector.hlsl`.
- Added support for `SPV_EXT_long_vector` (`VK_EXT_shader_long_vector`): the
  new `<vk/ext/long_vector.h>` header provides `vk::ext::LongVector<T, N>`, a
  SPIR-V vector with more than four components, lowered to a single
  `OpTypeVector` with N components instead of an array or a struct of
  `float4`s. A module that contains one declares `OpCapability LongVectorEXT`
  (5425) and `OpExtension "SPV_EXT_long_vector"`; both are emitted from the type
  itself, so `-fspv-extension=SPV_EXT_long_vector` can select and refuse the
  extension, and the extension is opt-in because a driver without
  `VK_EXT_shader_long_vector` rejects the module. The target environment must emit
  SPIR-V 1.3 or later (`-fspv-target-env=vulkan1.1`), because the extension is
  specified as modifications to SPIR-V 1.3. The header is a type plus element
  access, not an arithmetic system: `vk::ext::Concat` builds a value out of
  ordinary vectors with `OpCompositeConstruct`, `vk::ext::Get<index>` reads a
  component with `OpCompositeExtract` and `vk::ext::Set<index>` writes one with
  `OpCompositeInsert`, since HLSL's operators and swizzles are defined on ordinary
  vectors only. A component count of four or less, a component count that is not a
  compile-time constant, a long vector in stage input/output and a target
  environment older than SPIR-V 1.3 are all diagnostics rather than invalid
  SPIR-V. `OpTypeVectorIdEXT` (5288) is not provided by this header - it is the
  cooperative vector type of `SPV_NV_cooperative_vector`, above - and
  per-storage-class buffer layout is not implemented. See `docs/SPIR-V.rst` and
  `examples/spirv-extensions/ext-long-vector.hlsl`.
- Added support for `SPV_EXT_float8` (`VK_EXT_shader_float8`): the HLSL types
  `float8_e4m3_t` and `float8_e5m2_t` lower to `OpTypeFloat 8` with the
  `Float8E4M3EXT` (4214) and `Float8E5M2EXT` (4215) encodings, declare
  `OpCapability Float8EXT` (4212) and emit `OpExtension "SPV_EXT_float8"`.
  Both are storage and conversion types: `OpFConvert` to and from
  `float`/`double`/`half`, integer conversions, and storage in buffers and
  constants with a one-byte element stride. SPV_EXT_float8 defines no
  arithmetic, comparison or bitwise operation on them, so any such operation is
  rejected; the conversion model is widening only and E4M3 and E5M2 never mix
  implicitly. The two encodings are not allowed in shader stage input/output.
  Cooperative-matrix float8 (`Float8CooperativeMatrixEXT`) is not implemented.
  See `docs/SPIR-V.rst` and `examples/spirv-extensions/ext-shader-float8.hlsl`.
- Added support for `SPV_EXT_cooperative_matrix_maintenance1`
  (`VK_EXT_cooperative_matrix_maintenance1`). Four new members of
  `vk::khr::CooperativeMatrix` in `<vk/khr/cooperative_matrix.h>` emit the
  extension's four instructions, each with its own capability and with
  `OpExtension "SPV_EXT_cooperative_matrix_maintenance1"`:
  `ConvertUse<use>()` emits `OpCooperativeMatrixConvertUseEXT` (5293) and
  `CooperativeMatrixConversionsEXT` (5429) to reinterpret a matrix with a
  different `CooperativeMatrixUse` (accumulator to A/B or back, same component
  type, scope, rows and columns); `Reduce<rows, columns, mode>()` emits
  `OpCooperativeMatrixReduceEXT` (5366) and `CooperativeMatrixReductionsEXT`
  (5430) for `Row`, `Column`, `Row | Column` and `2x2` reductions;
  `PerElementOp()` emits `OpCooperativeMatrixPerElementOpEXT` (5369) and
  `CooperativeMatrixPerElementOperationsEXT` (5432); and `GetCoordinate(index)`
  emits `OpCooperativeMatrixGetCoordinateEXT` (5363) and
  `CooperativeMatrixGetCoordinateEXT` (5438) to map an element index to a
  `uint2` coordinate. The reduce mode and the result shape are template
  arguments, because the `CooperativeMatrixReduce` operand is a literal bit mask
  and a run-time mode cannot be encoded; a run-time mode, a result shape that
  does not match the mode, a non-accumulator matrix, and an A to B use
  conversion are compile-time errors instead of SPIR-V that `spirv-val` rejects.
  The two instructions that name a function operand (`Reduce`,
  `PerElementOp`) get a compiler-synthesized `__coopmat_combine` /
  `__coopmat_perelem` function whose body is `OpUndef`, so only their encoding is
  defined so far - the same limitation the `SPV_NV_cooperative_matrix2`
  spellings have. The extension is enabled by default, because every instruction
  it gates needs an entry point that did not exist before it; an explicit
  `-fspv-extension` list still acts as an allow-list.
  `-fspv-extension=SPV_EXT_cooperative_matrix_maintenance1` is accepted. See the
  "Cooperative matrix maintenance" section of `docs/SPIR-V.rst` and
  `examples/spirv-extensions/ext-cooperative-matrix-maintenance1.hlsl`.
- Added support for `SPV_ARM_cooperative_matrix_layouts`
  (`VK_ARM_cooperative_matrix_layouts`): naming
  `vk::CooperativeMatrixLayoutRowBlockedInterleavedARM` (4202) or
  `...ColumnBlockedInterleavedARM` (4203) as the `MemoryLayout` of a cooperative
  matrix load or store now emits `OpCapability CooperativeMatrixLayoutsARM` (4201)
  and `OpExtension "SPV_ARM_cooperative_matrix_layouts"` for the instruction that
  uses it. The two layouts arrange a matrix in 64-byte blocks that are ordered
  row-major or column-major and interleaved at a 4-byte granularity in groups of
  *Stride* blocks; for them `Stride` is therefore not a byte stride but the
  interleaving group size, and the extension restricts it to 1, 2 or 4 and
  requires it to come from a constant instruction. Because HLSL lowers every
  function argument to a pointer and reads it back with `OpLoad`, the layouts are
  reached through `LoadBlockedInterleaved`/`StoreBlockedInterleaved` in
  `<vk/arm/cooperative_matrix_layouts.h>`, which take the stride as a template
  argument, and an unsupported combination - a stride outside 1/2/4, a
  `Rows`/`Columns` pair that does not tile into whole blocks and whole
  interleaving groups, or an Arm layout handed to the ordinary `Load`/`Store`
  entry points - is a compile-time error instead of SPIR-V that `spirv-val`
  rejects. The classic `RowMajorKHR`/`ColumnMajorKHR` path is unchanged. The
  extension is enabled by default, because there is no alternative lowering to
  fall back to; `-fspv-extension=SPV_ARM_cooperative_matrix_layouts` is accepted
  and is only needed with an explicit allow-list. The host must enable
  `VK_ARM_cooperative_matrix_layouts` and find a
  `VkCooperativeMatrixPropertiesKHR` that reports the layout; the compiler cannot
  check that, nor what the producer wrote into the buffer. See the "Arm
  cooperative matrix memory layouts" section of `docs/SPIR-V.rst` and
  `examples/spirv-extensions/arm-cooperative-matrix-layouts.hlsl`.

- Added support for `SPV_KHR_abort` (`VK_KHR_shader_abort`): with
  `-fspv-extension=SPV_KHR_abort`, a `vk::Abort(message)` call (the entry point is
  declared in `<vk/ext/abort.h>`) lowers to a single `OpAbortKHR` (5121) guarded by
  `OpCapability AbortKHR` (5120) and
  `OpExtension "SPV_KHR_abort"`. The instruction has no result; its two `IdRef`
  operands are the *message type* (a type id) and the *message* (the id of a value
  whose type must logically match it), and DXC emits the message value's own type
  for the first one and the single `uint` argument for the second, so a message is
  four bytes of data handed to the client API. `OpAbortKHR` is a block terminator,
  so the statement ends the block and any code written after it is unreachable and
  is not emitted - which is what makes "only instructions executed before the abort
  have side effects" hold - and the instruction is accepted in every shader stage
  and inside helper functions. The extension is opt-in: an abort is not a recovery
  point, and `VK_KHR_shader_abort` makes a shader abort lose the device, so without
  the flag every call is a compile error and a shader that does not abort is
  unchanged. The `OpConstantDataKHR` message form of the extension (a bundled
  format string and its arguments, laid out with scalar rules) is not emitted: HLSL
  has no equivalent of that GLSL front-end convention, and the dependent
  `ConstantDataKHR` capability is only added if such a message reaches the backend
  by other means. The host must enable
  `VkPhysicalDeviceShaderAbortFeaturesKHR::shaderAbort` and collect the message
  through `VK_KHR_device_fault`; the compiler cannot check either. See the "Shader
  abort" section of `docs/SPIR-V.rst` and
  `examples/spirv-extensions/khr-shader-abort.hlsl`.
- Added support for `SPV_KHR_constant_data` (`VK_KHR_shader_constant_data`): with
  `-fspv-constant-data[=<threshold>]` and
  `-fspv-extension=SPV_KHR_constant_data`, an integer array constant whose elements
  are all known at compile time is declared by one `OpConstantDataKHR` (5147)
  instead of an `OpConstantComposite` over one `OpConstant` per element, guarded by
  `OpCapability ConstantDataKHR` (5146) and
  `OpExtension "SPV_KHR_constant_data"`. The operands after the result type and
  result id are the *literal words* of the data, packed with no padding between
  elements: 8-bit elements four per word, 16-bit two per word, 64-bit two words with
  the low word first, always with element 0 in the least significant bits and the
  final word zero-padded. The encoding is only used where the extension allows it
  (the result type must be an `OpTypeArray` of an integer scalar type and must not
  carry `ArrayStride`), never below the threshold (default 8 elements, because the
  instruction costs one word per element and only saves the per-element constants),
  and never for a data set larger than the 65532 words one instruction can hold. The
  option is off by default, so no module changes unless it is given, and it requires
  the extension to be allowed so that an explicit `-fspv-extension=` list can refuse
  it. For a 256-entry `uint` table the emitted module drops from 5860 to 1816 bytes
  with the default pipeline and from 6128 to 2084 bytes with `-fcgl`.
  `OpSpecConstantDataKHR` (5148) and the `UTFEncodedKHR` decoration (5145) are not
  emitted: HLSL has no array specialization surface (`[[vk::constant_id]]` applies
  to scalar globals only, and a specialization constant data array also has to
  specialize the array length). See the "Constant data arrays" section of
  `docs/SPIR-V.rst` and `examples/spirv-extensions/khr-constant-data.hlsl`.
- Added support for `VK_EXT_shader_uniform_buffer_unsized_array`: with
  `-fspv-enable-uniform-buffer-unsized-array`, the last member of a uniform buffer
  block may be an unsized array (a trailing `float values[];` in the struct used as
  the element type of a `ConstantBuffer`). The extension adds no SPIR-V instruction,
  no capability and no `OpExtension` string - it relaxes a rule of the Vulkan SPIR-V
  environment and reuses `OpTypeRuntimeArray` - so the relaxation is an opt-in flag
  instead of a `-fspv-extension` or `-fspv-target-env` value, and a module compiled
  without it is unchanged. The runtime array becomes the last member of the
  `Block`-decorated `Uniform` struct with the `Offset` and `ArrayStride` the active
  layout rule produces, is indexed at runtime through a dynamic `OpAccessChain`, and
  is validated by the shipped SPIRV-Tools without any extra validator option. The
  compiler rejects an unsized member that is not the last member, any use of the
  struct outside a `ConstantBuffer` (push constant blocks, shader record buffers,
  `TextureBuffer`/`StructuredBuffer` element types, local variables and function
  parameters), any copy of the block (a local `ConstantBuffer<T>` variable, a
  `ConstantBuffer<T>` parameter, a function returning one, or an array of blocks),
  and `.Length` on the member, because the extension prohibits `OpArrayLength`;
  the accessible length is
  `max((bufferObjectSize - offsetOfArray) / arrayStride, 0)` and has to be passed in
  by the application, which must also enable
  `VkPhysicalDeviceShaderUniformBufferUnsizedArrayFeaturesEXT::shaderUniformBufferUnsizedArray`
  on the device and size the descriptor range accordingly. See the "Unsized array as
  the last uniform buffer member" section of `docs/SPIR-V.rst` and
  `examples/spirv-extensions/ext-uniform-buffer-unsized-array.hlsl`.
- Added support for `SPV_QCOM_image_processing3`: with
  `-fspv-extension=SPV_QCOM_image_processing3`, the entry points in
  `<vk/qcom/image_processing3.h>` gather with a footprint chosen by a mode operand
  instead of the fixed 2x2 quad of `OpImageGather`, emitting `OpImageGatherQCOM`
  (4545) as `(Result Type, Result, Sampled Image, Coordinate, Component, Mode)`:
  `vk::qcom::ImageGather4x1()` (`Gather4x1QCOM`, four horizontally adjacent
  texels), `vk::qcom::ImageGatherD()` (`GatherDQCOM`, the four cardinal
  neighbours), `vk::qcom::ImageGatherH2()` (`GatherH2QCOM`, two 2x1 pairs) and
  `vk::qcom::ImageGatherV2()` (`GatherV2QCOM`, two 1x2 pairs) - plus `...Array`
  variants that take the array layer as the third coordinate component - with the
  gathered channel chosen by the template argument
  (`vk::qcom::ImageGatherD<2>(image, coord)` gathers blue). The capability is
  selected per call shape from the mode operand, because the two Vulkan feature
  bits behind it are independent: `ImageGatherLinearQCOM` (4543) for
  `Gather4x1QCOM` and `ImageGatherExtendedModesQCOM` (4544) for the other three.
  The component and the mode are constants in the module, which is what SPIRV-Tools
  requires of a Vulkan module; the extension is opt-in like the rest of the family,
  so without `-fspv-extension=SPV_QCOM_image_processing3` every call is a compile
  error, and the module also needs a SPIR-V 1.4 target environment
  (`-fspv-target-env=vulkan1.1spirv1.4` or newer). The surface is SPIR-V only -
  there is no DXIL instruction for a mode-selected gather - and covers combined
  image samplers (`vk::SampledTexture2D`), not a `Texture2D` plus a separate
  `SamplerState`. See the "Image gather modes" section of `docs/SPIR-V.rst` and
  `examples/spirv-extensions/qcom-image-processing3.hlsl`.
- Added support for `SPV_NV_linear_swept_spheres`: with
  `-fspv-extension=SPV_NV_linear_swept_spheres`, the accessors in
  `<vk/nv/linear_swept_spheres.h>` read the analytic geometry of a ray query
  intersection: `vk::nv::RayQueryGetCommittedIntersectionSpherePosition()` and
  `vk::nv::RayQueryGetCommittedIntersectionSphereRadius()` are emitted as
  `OpRayQueryGetIntersectionSpherePositionNV` (%v3float) and
  `OpRayQueryGetIntersectionSphereRadiusNV` (%float), and
  `vk::nv::RayQueryIsCommittedSphereHit()` as `OpRayQueryIsSphereHitNV` (%bool),
  so a ray query can shade spheres (particles, froxels, point clouds) and linear
  swept spheres (hair, fur) without tessellating them into triangles. The
  capability is selected per instruction - `RayTracingSpheresGeometryNV` for the
  sphere accessors, `RayTracingLinearSweptSpheresGeometryNV` for the
  linear-swept-sphere ones (`OpRayQueryGetIntersectionLSSHitValueNV`,
  `OpRayQueryIsLSSHitNV`) - because the two Vulkan feature bits are independent.
  The accessors are header-only free functions rather than `RayQuery` methods
  because DXR has no sphere geometry (the method table is shared with the DXIL
  backend), the two intersection selectors are exported as
  `vk::nv::SphereIntersectionCandidate` / `SphereIntersectionCommitted`, and
  `IsSphereHit` is the portable way to branch because the candidate/committed
  type enumerations only describe triangles and AABBs. The extension is opt-in
  (without the flag every call is a compile error), and the values are only
  defined for geometry built from spheres, which the compiler cannot check.
  `OpRayQueryGetIntersectionLSSPositionsNV` / `...LSSRadiiNV` are not exposed yet
  (array result types cannot be declared in a function template in this front
  end), and the hit object half of the extension needs
  `SPV_EXT_shader_invocation_reorder` support first.
- Added support for `SPV_NV_cluster_acceleration_structure`: with
  `-fspv-extension=SPV_NV_cluster_acceleration_structure`,
  `vk::nv::RayQueryGetCommittedIntersectionClusterId()` and
  `vk::nv::RayQueryGetCandidateIntersectionClusterId()` from
  `<vk/nv/cluster_as.h>` are emitted as
  `OpRayQueryGetIntersectionClusterIdNV` with the
  `RayTracingClusterAccelerationStructureNV` capability and the
  `SPV_NV_cluster_acceleration_structure` extension, so a ray query can read the
  cluster ID of a hit instead of deriving the material/LOD decision from the
  primitive index. The accessors are header-only free functions rather than
  `RayQuery` methods because DXR has no cluster acceleration structures (the
  method table is shared with the DXIL backend); the intersection operand must be
  a constant, so the header also exports `vk::nv::IntersectionCandidate` /
  `vk::nv::IntersectionCommitted`. The extension is opt-in (without the flag the
  accessors are compile errors) and a cluster ID is only meaningful for geometry
  built from a cluster acceleration structure, which the compiler cannot check.

- Added support for `SPV_KHR_fma`: with `-fspv-extension=SPV_KHR_fma`, a fused
  multiply-add on 32-bit float (`mad()`) is emitted as the `OpFmaKHR` core
  instruction with the `FMAKHR` capability instead of the `GLSL.std.450` `Fma`
  extended instruction. The extension is opt-in (modules using `OpFmaKHR` need
  `VK_KHR_shader_fma` and the `shaderFmaFloat32` feature), and without
  `-fspv-extension=SPV_KHR_fma` code generation is unchanged.
- Added support for `SPV_KHR_opacity_micromap`: with
  `-fspv-extension=SPV_KHR_opacity_micromap`, a shader whose ray queries opt in
  to opacity micromaps (`RayQuery<..., RAYQUERY_FLAG_ALLOW_OPACITY_MICROMAPS>` or
  a `RAY_FLAG_FORCE_OMM_2_STATE` ray flags argument) gets the
  `OpacityMicromapIdKHR` execution mode attached to the entry points that request
  it, emitted as `OpExecutionModeId %entry OpacityMicromapIdKHR %spec` with the
  `RayTracingOpacityMicromapExecutionModeKHR` capability (plus
  `RayTracingOpacityMicromapKHR` when the force-2-state ray flag is used),
  `OpExtension "SPV_KHR_opacity_micromap"`, and a boolean specialization
  constant decorated with `SpecId` (default true, id chosen with
  `-fvk-opacity-micromap-spec-id=N`) so that the host can specialize it. The
  extension is opt-in; without the flag the module is unchanged and a warning
  reports the ignored opt-in. See the "Opacity micromaps" section of
  docs/SPIR-V.rst.
- Added support for `SPV_EXT_split_barrier`: with
  `-fspv-extension=SPV_EXT_split_barrier`, `vk::SplitBarrierArrive()` and
  `vk::SplitBarrierWait()` from `<vk/ext/split_barrier.h>` are emitted as
  `OpControlBarrierArriveEXT` and `OpControlBarrierWaitEXT` with the
  `SplitBarrierEXT` capability and the `SPV_EXT_split_barrier` extension, so a
  compute shader can overlap independent work with a workgroup barrier instead
  of waiting at `GroupMemoryBarrierWithGroupSync()`. The entry points are
  compute-only and opt-in (without the flag they are compile errors). The
  arrive/wait pairing is not enforced by the compiler: the instructions carry
  no token, so an unmatched arrive or an un-arrived wait is undefined
  behavior.
- Added `SPV_EXT_shader_subgroup_partitioned` as a name for the extension that
  provides the partitioned wave operations (`WaveMatch()` and the
  `WaveMultiPrefix*()` family). With
  `-fspv-extension=SPV_EXT_shader_subgroup_partitioned` the module declares
  `OpExtension "SPV_EXT_shader_subgroup_partitioned"` instead of
  `"SPV_NV_shader_subgroup_partitioned"`, which is what a driver exposing
  `VK_EXT_shader_subgroup_partitioned` (`shaderSubgroupPartitioned` feature)
  expects. The two extensions name the same capability
  (`GroupNonUniformPartitionedEXT` = `GroupNonUniformPartitionedNV` = 5297), so
  the instruction stream is unchanged and only the `OpExtension` string
  differs. The NV spelling stays the default, so code generation without the
  flag is unchanged; `-fspv-extension=SPV_NV_shader_subgroup_partitioned` keeps
  it available. Naming neither spelling in an explicit `-fspv-extension` list
  is now a compile error instead of an invalid module.
  - Added support for `SPV_QCOM_multiple_wait_queues`:
    `[[vk::multiple_wait_queues]]` (or `[[vk::multiple_wait_queues(N)]]`) on a
    `for`, `while` or `do` statement sets the `MultipleWaitQueuesQCOM` loop
    control bit (`0x10000000`) on that loop's `OpLoopMerge`, together with the
    literal operand the enumerant carries - the maximum number of wait queues,
    `0` meaning all available - and the module declares
    `OpCapability MultipleWaitQueuesQCOM` (4539) and
    `OpExtension "SPV_QCOM_multiple_wait_queues"`. The bit is OR-ed with the
    loop control the loop already needs, so
    `[[vk::multiple_wait_queues]] [unroll]` encodes
    `Unroll|MultipleWaitQueuesQCOM`. The extension is opt-in
    (`-fspv-extension=SPV_QCOM_multiple_wait_queues`): without the flag an
    annotated loop is a compile error, and code generation without the
    attribute is unchanged. The annotation on a statement that is not a loop,
    and two copies of it on one statement, are compile errors. This is an
      encoding-level performance hint only - a driver may ignore it, it implies
      no memory ordering, and results are identical either way.
  - Added support for `SPV_NV_push_constant_bank`:
    `[[vk::push_constant_bank(N)]]` on a `[[vk::push_constant]]` block places the
    block in hardware push constant bank `N` (`OpDecorate %pc BankNV N`, 5397),
    and `[[vk::push_constant_bank_offset(N)]]` adds the base byte offset `N` to
    every member offset of the block (`OpDecorate %pc MemberOffsetNV N`, 5358;
    despite the name it decorates the variable, not a struct member). A module
    that uses either decoration declares `OpCapability PushConstantBanksNV`
    (5423) and `OpExtension "SPV_NV_push_constant_bank"`, and the "at most one
    push constant block" rule becomes "at most one block per bank" - the only
    rule change. The extension is opt-in
    (`-fspv-extension=SPV_NV_push_constant_bank`, driver side
    `VK_NV_push_constant_bank` plus the `pushConstantBank` feature): without the
    flag the attributes are compile errors, code generation without them is
    unchanged, and a second block in the same bank, a repeated attribute, a
    negative bank/offset and the attributes without `[[vk::push_constant]]` are
    compile errors. The bank count (`maxGraphicsPushConstantBanks` /
    `maxComputePushConstantBanks`) and the bank size
    (`maxPushConstantsSize`) are host facts the compiler cannot check.

- Added `-fvk-resource-heap-stride` and `-fvk-sampler-heap-stride`, which
  override the computed `ArrayStrideIdEXT` of the resource and sampler
  descriptor heaps with a literal `ArrayStride`. The value must be a power of
  two in `[8, 256]`. Both flags require `-spirv` and
  `-fspv-use-descriptor-heap` and are rejected otherwise.
- Added support for `VK_KHR_maintenance8`, the Vulkan maintenance extension whose
  `maintenance8` feature bit adopts two SPIR-V definitions that DXC already
  generated: the `Offset` image operand (0x0010) as an alternative to
  `ConstOffset` (0x0008) for texture sampling and fetch, and the
  `OpSRem`/`OpSMod` result for negative operands. HLSL needs no change - a
  non-constant texture offset has no encoding other than `Offset`, and HLSL `%`
  is truncating remainder, which is `OpSRem` - and the module is unchanged: the
  extension adds no instruction, capability, `OpExtension` or target environment,
  so there is no `SPV_KHR_maintenance8` to request with `-fspv-extension` and no
  new `-fspv-target-env`. What was missing was the validator side: DXC validated
  its own output against the pre-maintenance8 Vulkan rule, so a shader using a
  computed texture offset failed to compile with
  `[VUID-RuntimeSpirv-Offset-10213] Image Operand Offset can only be used with
  OpImage*Gather operations` unless `-fcgl` was passed. DXC now validates with the
  relaxation in effect. The host must still provide Vulkan 1.4, or Vulkan 1.1+
  with `VK_KHR_maintenance8` enabled and the `maintenance8` feature bit set; the
  compiler cannot check that.
  - Added `-fspv-enable-maintenance9` for `VK_KHR_maintenance9`, whose
  `maintenance9` feature bit lifts the Vulkan rule
  (`VUID-RuntimeSpirv-None-10824`) that required a 32-bit Base operand for
  `OpBitReverse`, `OpBitCount`, `OpBitFieldInsert`, `OpBitFieldSExtract` and
  `OpBitFieldUExtract`. With the flag, `reversebits` on a 16-bit operand is one
  `OpBitReverse %ushort` instead of a widen/reverse/shift/truncate sequence, and
  on a 64-bit operand one `OpBitReverse %ulong` instead of nine instructions that
  reverse both halves and recombine them; `countbits` similarly drops its
  widening (16-bit) and its two-half decomposition (64-bit). The flag is off by
  default, so generated code is unchanged without it, and the validator
  relaxation (`SetAllowVulkan32BitBitwise`) is applied only when it is passed.
  As with maintenance8 there is no `SPV_KHR_maintenance9` to request with
  `-fspv-extension` and nothing is added to the module header; the relaxation is
  a device feature, so it is not expressible with `-fspv-target-env`. The host
  must enable `VK_KHR_maintenance9` at `vkCreateDevice` and set the `maintenance9`
  feature bit; the compiler cannot check that.
  - Added support for `VK_KHR_maintenance12`, the Vulkan device extension whose
  first item permits non-uniform indexing of values within a variable with a
  `PushConstant` storage class. On the SPIR-V side that permission has exactly
  one representation, and DXC already emits it: a `NonUniform` decoration on the
  access chain whose index is divergent, plus the `ShaderNonUniform` capability
  (from `SPV_EXT_descriptor_indexing`) that legalises the decoration. So there is
  no `SPV_KHR_maintenance12` to request with `-fspv-extension`, no new target
  environment, nothing added to the module header and no flag to pass. What was
  missing was the coverage and the guidance: a non-uniform push constant
  subscript was untested, and nothing said how HLSL declares one.
  `NonUniformResourceIndex()` is the declaration; despite the name its Sema check
  accepts a plain `uint`, so it applies to a push constant subscript, and the
  marking it puts on the index reaches the access chain, the loaded value and the
  value's consumers. DXC does not infer divergence - an unwrapped divergent index
  produces no decoration at all, and the module then claims the index is
  dynamically uniform - so the marking has to be written at the indexing site.
  `maintenance12.*.hlsl` in `tools/clang/test/CodeGenSPIRV` now pins the
  decoration on the push constant access chain (flat array and nested
  struct-of-arrays), its absence for uniform and unwrapped indices, the unchanged
  classic `ConstantBuffer<>` path, and its survival through spirv-opt. The host
  must enable `VK_KHR_maintenance12` at `vkCreateDevice` and enable the feature
  bits it exposes (`VkPhysicalDeviceMaintenance12FeaturesKHR`); without them a
  driver is entitled to assume the subscript is dynamically uniform, and the
  compiler cannot check that.
  - Added support for the `VK_KHR_shader_bfloat16` compute half of
    `SPV_KHR_bfloat16`, so that all three of its capabilities are now
    expressible. `dot()` on `bfloat16_t` vector operands is emitted as `OpDot`
    with a `BFloat16KHR` component type and declares
    `OpCapability BFloat16DotProductKHR` (5117) on top of the existing
    `BFloat16TypeKHR`; it is `OpDot`, not `OpSDot`/`OpUDot`, because the integer
    dot product instructions require an integer result type. `dot()` now returns
    `bfloat16_t` for `bfloat16_t` operands, so `float f = dot(a, b)` widens the
    bfloat16 result with an extra `OpFConvert`, and mixing `bfloat16_t` with any
    other component type in one `dot()` call is a compile error instead of a
    silent widening. `vk::khr::CooperativeMatrix<bfloat16_t, ...>` from
    `<vk/khr/cooperative_matrix.h>` is now usable and declares
    `OpCapability BFloat16CooperativeMatrixKHR` (5118) in addition to
    `CooperativeMatrixKHR`; only multiply-add, load, store, `Splat`, `Get`/`Set`
    and `GetLength` are legal on it, since the extension defines no arithmetic
    for the component type. Both are opt-in at the driver level through
    `VkPhysicalDeviceShaderBfloat16FeaturesKHR` (`shaderBFloat16Type`,
    `shaderBFloat16DotProduct`, `shaderBFloat16CooperativeMatrix`), which the
    compiler cannot check. `docs/SPIR-V.rst` now documents the extension,
    including the conversion model (implicit widening to `float` only, no
    `bfloat16_t`/`float16_t` mixing) and the stage I/O restriction.
- Added support for `SPV_VALVE_mixed_float_dot_product`: with
  `-fspv-extension=SPV_VALVE_mixed_float_dot_product`, HLSL's
  `float dot2add(half2 a, half2 b, float acc)` is emitted as the fused
  `OpFDot2MixAcc32VALVE` (6916) with `OpCapability
  DotProductFloat16AccFloat32VALVE` (6912) instead of the unfused
  `OpFMul`/`OpFConvert`/`OpFAdd` sequence. The result is the same dot product
  rounded once rather than several times, which is a numeric change for existing
  shaders, and the extension is therefore opt-in: VALVE extensions are
  vendor-specific, and a module that declares the capability is only accepted by
  drivers exposing `VK_VALVE_shader_mixed_float_dot_product`. Without the flag
  code generation is unchanged. Only the FP16-input/FP32-accumulator form is
  emitted: `OpFDot2MixAcc16VALVE` has no HLSL call site (`dot2add` always
  accumulates in `float`), the bfloat16 form needs a `bfloat16_t2` overload of
  `dot2add` that does not exist, and the FP8 form needs the `SPV_EXT_float8` type
  system, which this backend does not implement yet.


Place release notes for the upcoming release below this line and remove this
line upon naming the release. Refer to previous for appropriate section names.

#### Shader Model 6.10

- Shader Model 6.10 and DXIL 1.10 are now available in retail, introducing
  LinAlg Matrix, WaveGroup Index and Count, DebugBreak, Clustered Geometry, and
  Triangle Object Positions.
- Allowed DXIL `insertvalue` instructions starting with Shader Model 6.10,
  enabling unoptimized DXIL that constructs aggregate values to be valid in cases that previously were not.
- Removed work graph support from Shader Model 6.10, and DXIL 1.10
  [microsoft/hlsl-specs#915](https://github.com/microsoft/hlsl-specs/issues/915).
- Fixed the set of numeric types allowed in LinAlg matrix intrinsics
  [#8271](https://github.com/microsoft/DirectXShaderCompiler/issues/8271).
- Corrected the parameter order of `InterlockedAccumulate`
  [microsoft/hlsl-specs#869](https://github.com/microsoft/hlsl-specs/issues/869).
- Added validation of LinAlg matrix builtin parameters and result K dimension
  [#8491](https://github.com/microsoft/DirectXShaderCompiler/issues/8491).
- Restricted the component types allowed in LinAlg matrices
  [#8494](https://github.com/microsoft/DirectXShaderCompiler/issues/8494).
- Added `BFloat16` to the ComponentType enum in DxilConstants and the linalg
  header [#8722](https://github.com/microsoft/DirectXShaderCompiler/issues/8722).

#### HLSL Language

- The `shared` and `uniform` keywords are removed in HLSL 202x, with
  compatibility warnings available for earlier language versions
  [#8482](https://github.com/microsoft/DirectXShaderCompiler/issues/8482).
- The `interface` keyword and interface declarations are removed in HLSL 202x,
  with compatibility warnings available for earlier language versions.
- Added support for `auto` return types for normal functions aligning with C++14
  [#8903](https://github.com/microsoft/DirectXShaderCompiler/issues/8903).
- HLSL 202x now supports variadic templates and template function parameter
  packs, pack expansions, and `sizeof...()`
  [#8905](https://github.com/microsoft/DirectXShaderCompiler/issues/8905).
- HLSL 202x disallows initializers on variables in explicit and implicit
  constant buffers and texture buffers
  [#8483](https://github.com/microsoft/DirectXShaderCompiler/issues/8483).
- HLSL 202x disallows putting cbuffer, tbuffer, or namespace declarations inside
  a cbuffer or tbuffer
  [#8484](https://github.com/microsoft/DirectXShaderCompiler/issues/8484).
- Starting with HLSL 202x, `cbuffer` and `tbuffer` declarations and their
  members belong to their enclosing namespace.
- HLSL 202x supports `const`-qualified instance methods and rejects calls
  to non-`const` methods on `const` objects, including objects in constant 
  buffers 
  [#8964](https://github.com/microsoft/DirectXShaderCompiler/issues/8964).
- HLSL 202x supports `mutable` member variables in structs, allowing them to be
  modified even in `const`-qualified instance methods
  ([#8965](https://github.com/microsoft/DirectXShaderCompiler/issues/8965)).
- Add `static_assert` matching C++11 and C++17 under HLSL 202x
  ([#8910](https://github.com/microsoft/DirectXShaderCompiler/issues/8910)).
- Fix HLSL 202x conforming literals false-positive warning for hex literal
  signedness
  ([#7864](https://github.com/microsoft/DirectXShaderCompiler/issues/7864)).

#### SPIR-V

- Extended `SPV_EXT_descriptor_heap` lowering (`-fspv-use-descriptor-heap`) to
  buffer-like resources (`StructuredBuffer`, `ByteAddressBuffer`,
  `ConstantBuffer`, `TextureBuffer`, and RW variants) via
  `SPV_KHR_untyped_pointers`. Requires `-fspv-target-env=vulkan1.3`.
- Extended `-fspv-use-descriptor-heap` to support `RaytracingAccelerationStructure`
  loaded from `ResourceDescriptorHeap`. Outside ray-tracing stages, list
  `-fspv-extension=SPV_KHR_ray_query`, `SPV_KHR_ray_tracing` or
  `SPV_NV_ray_tracing` so the resource heap stride covers acceleration structure
  descriptors; otherwise compilation fails.

#### Bug Fixes

- Improved compiler performance by reducing excessive memory-dependence scans
  during GVN and repeated vector-elimination work.
- Fixed GVN load forwarding generating unsupported integer types when optimizing
  native vectors
  [#9040](https://github.com/microsoft/DirectXShaderCompiler/issues/9040).
- Fixed shader reflection dropping leading characters from user-defined struct type names.
- Fixed an optimizer crash when scalarizing an out-of-bounds vector access
  [#8940](https://github.com/microsoft/DirectXShaderCompiler/issues/8940).
- Fixed members following a merged bitfield reading the wrong value when a
  struct is flat-converted
  [#8526](https://github.com/microsoft/DirectXShaderCompiler/issues/8526).
- Fixed incorrect shader results caused by stale overflow and exactness flags
  after bit-tracking dead code elimination.
- Fixed an optimizer miscompile where selects of bitwise-not values guarded by
  signed less-than or unsigned compares were treated as a signed minimum.

### Upcoming Preview Release

These changes apply to experimental preview shader models only and will not be
part of the next non-preview release.

#### Experimental Shader Model 6.11

- Added experimental Shader Model 6.11 target profiles.

### Version 1.9.2609

#### Bug Fixes

- Fixed derivative operations being moved into divergent control flow, which
  could produce incorrect results
  [#8001](https://github.com/microsoft/DirectXShaderCompiler/issues/8001).
- Fixed a bug in template instantiations involving functions with an
  out parameter, which could lead to an assert or a bad memory access.
  [#5293](https://github.com/microsoft/DirectXShaderCompiler/issues/5293),
  [#8310](https://github.com/microsoft/DirectXShaderCompiler/issues/8310).
- SPIR-V: Fixed an invalid `OpSelect` being generated when optimizing for
  SPIR-V 1.3 and earlier
  [#8603](https://github.com/microsoft/DirectXShaderCompiler/issues/8603).
- Fix a crash generating DXIL from sources containing a dynamic resource heap
  access that was discarded. Identified during development of SPIR-V support for
  [descriptor heaps](https://github.com/microsoft/DirectXShaderCompiler/pull/8517#discussion_r3752113078).
- SPIR-V: Fixed a crash when writing to a bitfield member through a
  `vk::BufferPointer`
  [#8402](https://github.com/microsoft/DirectXShaderCompiler/issues/8402).
- Prevented an assertion from hiding the original fatal error when Clang skips
  template specialization
  [#6615](https://github.com/microsoft/DirectXShaderCompiler/issues/6615),
  [#4875](https://github.com/microsoft/DirectXShaderCompiler/issues/4875).
- Fixed internal compiler errors when a member method is called on a ray payload
  or on one of its fields with payload access qualifiers enabled
  [#6464](https://github.com/microsoft/DirectXShaderCompiler/issues/6464).
- Fixed undefined behavior in DXC IntelliSense caused by the uninitialized
  `ExpandTokPastingArg` preprocessor option, which made token-pasting
  behavior indeterminate.
- SPIR-V: Fixed user-defined types whose names match built-in types being
  incorrectly lowered as the built-in type.
- SPIR-V: 16-bit sampled types on `vk::SampledTexture` are rejected as required
  by VUID-StandaloneSpirv-OpTypeImage-04656.
- SPIR-V: Added support for multisampled UAV types fixing miscompiles in
  previous releases.

#### HLSL Language

- Starting with HLSL 202x, the count in `[unroll(N)]` is a partial-unroll hint
  and no longer limits the number of loop iterations
  [#8789](https://github.com/microsoft/DirectXShaderCompiler/issues/8789).
- Casting a scalar to a struct or array containing a resource is now an error
  instead of crashing
  [#6661](https://github.com/microsoft/DirectXShaderCompiler/issues/6661).
- Added the `-Whlsl-2026-compat` warning group for identifying issues
  with language changes introduced in HLSL 2026.
- The legacy effects syntax support is removed in HLSL 202x
  [#8480](https://github.com/microsoft/DirectXShaderCompiler/issues/8480).

#### SPIR-V

- Inline `[[vk::ext_decorate]]`, `[[vk::ext_capability]]`, and
  `[[vk::ext_extension]]` attributes are now honored on ordinary functions
  [#8616](https://github.com/microsoft/DirectXShaderCompiler/pull/8616).
- `globallycoherent` is now supported on `ResourceDescriptorHeap` accesses
  [#7740](https://github.com/microsoft/DirectXShaderCompiler/issues/7740).
- Fixed a crash when a user-defined type named `RayQuery` shadows the intrinsic
  type [#8601](https://github.com/microsoft/DirectXShaderCompiler/issues/8601).
- Fixed a crash from `static` members of a `cbuffer`/`tbuffer`, which were
  incorrectly counted as buffer members and shifted the member indices of the
  members declared after them
  [#8537](https://github.com/microsoft/DirectXShaderCompiler/issues/8537).
- Fixed incorrect alignment of 64-bit elements in `vk::RawBufferLoad` and
  `vk::RawBufferStore` intrinsics
  [#8572](https://github.com/microsoft/DirectXShaderCompiler/issues/8572).

### Version 1.9.2607

#### HLSL Language

- Added `auto` for C++11-style type deduction
  [#8452](https://github.com/microsoft/DirectXShaderCompiler/pull/8452). `auto`
  cannot be used to infer built-in internal types or the types returned by
  `ResourceDescriptorHeap`/`SamplerDescriptorHeap`.
- Added the `[[nodiscard]]` attribute
  [#8462](https://github.com/microsoft/DirectXShaderCompiler/pull/8462).
- Added bit-precise floating-point literal suffixes
  [#8478](https://github.com/microsoft/DirectXShaderCompiler/pull/8478).
- `>>` no longer requires surrounding spaces in nested template arguments
  [#8453](https://github.com/microsoft/DirectXShaderCompiler/pull/8453).
- The `volatile` keyword is now disallowed
  [#8391](https://github.com/microsoft/DirectXShaderCompiler/issues/8391).
- The `groupshared` parameter attribute can now be used on templates
  [#8217](https://github.com/microsoft/DirectXShaderCompiler/pull/8217).
- Added `GroupSharedLimit` attribute support for mesh, amplification, and node
  shaders [#8140](https://github.com/microsoft/DirectXShaderCompiler/pull/8140).

#### SPIR-V

- Added sampler and resource heaps for textures
  [#8281](https://github.com/microsoft/DirectXShaderCompiler/pull/8281).
- Function parameters can now be decorated with inline SPIR-V
  [#8103](https://github.com/microsoft/DirectXShaderCompiler/issues/8103).
- Fixed `vk::BufferPointer` cast methods
  [#8365](https://github.com/microsoft/DirectXShaderCompiler/pull/8365).
- Fixed layout-rule propagation for `ConstantBuffer`/`TextureBuffer` function
  variable and parameter aliasing
  [#8244](https://github.com/microsoft/DirectXShaderCompiler/issues/8244).
- Fixed counter handling in a direct `return` statement
  [#8215](https://github.com/microsoft/DirectXShaderCompiler/issues/8215).
- Fixed `OpSpecConstant` for composites
  [#8278](https://github.com/microsoft/DirectXShaderCompiler/pull/8278).
- Fixed a crash with out-of-line template declarations
  [#5823](https://github.com/microsoft/DirectXShaderCompiler/issues/5823).
- Fixed handling of `void` in extended instruction sets
  [#8012](https://github.com/microsoft/DirectXShaderCompiler/issues/8012).

#### Bug Fixes

- Fixed GVN/SROA miscompilation of minimum-precision vector element access
  [#8268](https://github.com/microsoft/DirectXShaderCompiler/issues/8268).
- Fixed `rawBufferVectorLoad`/`Store` to widen minimum-precision types to 32-bit
  [#8273](https://github.com/microsoft/DirectXShaderCompiler/issues/8273).
- Fixed out-of-bounds subscript indexing of a column-major matrix in a constant
  buffer [#7865](https://github.com/microsoft/DirectXShaderCompiler/issues/7865).
- Fixed illegal-width bitmap generated from a `switch` lookup table in
  SimplifyCFG
  [#8421](https://github.com/microsoft/DirectXShaderCompiler/issues/8421).
- Fixed a crash producing diagnostics for source containing embedded nulls
  [#8164](https://github.com/microsoft/DirectXShaderCompiler/pull/8164).
- Fixed constant folding of `VectorReduce.*`
  [#8570](https://github.com/microsoft/DirectXShaderCompiler/issues/8570).
- GVN no longer coerces a vector store through `i128` or wider
  [#8573](https://github.com/microsoft/DirectXShaderCompiler/issues/8573).
- Validation now drills through chained GEPs when resolving TGSM globals, needed
  for SM 6.9 native vectors
  [#8571](https://github.com/microsoft/DirectXShaderCompiler/issues/8571).
- The sampler feedback shader flag is now set when sampler feedback operations
  are used and the validator version is >= 1.9
  [#8533](https://github.com/microsoft/DirectXShaderCompiler/issues/8533).
- Preserve coherence qualifiers (`globallycoherent`/`reordercoherent`) on
  resource flat-conversions
  [#8583](https://github.com/microsoft/DirectXShaderCompiler/pull/8583).
- Fixed type annotation serialization for resources in HL modules
  [#8440](https://github.com/microsoft/DirectXShaderCompiler/issues/8440).
- Fixed the `COMPARISON_NONE` handling and its error message
  [#8246](https://github.com/microsoft/DirectXShaderCompiler/issues/8246).
- Fixed an ambiguous overloaded `operator+` error with newer Clang
  [#8516](https://github.com/microsoft/DirectXShaderCompiler/pull/8516).
- Stopped emitting illegal `*.with.overflow` intrinsics for DXIL, which caused
  validation failures for overflow-check idioms when optimizations were enabled
  [#8600](https://github.com/microsoft/DirectXShaderCompiler/pull/8600).

#### Other Changes

- Built-in HLSL headers are now embedded in the dxcompiler library so that users do not need to copy headers around with the toolchain.
- vector_utils.h and enable_if.h are renamed to vector_utils and enable_if respectively in alignment with TC57 decision on standard header files to exclude file extensions (See: https://github.com/hlsl-tc57/tc57/blob/main/docs/DesignConsiderations.md#minor-details).
- Added `-Fre` support for the Metal backend to emit the Metal Shader Converter
  reflection JSON
  [#8159](https://github.com/microsoft/DirectXShaderCompiler/pull/8159).

### Version 1.10.2605

#### Experimental Shader Model 6.10

- Removed experimental Cooperative Vector, this has been replaced by LinAlg matrix.
- Implement GetGroupWaveIndex and GetGroupWaveCount in experimental Shader Model 6.10.
  - [proposal](https://github.com/microsoft/hlsl-specs/blob/main/proposals/0048-group-wave-index.md)
  - GetGroupWaveIndex: New intrinsic for Compute, Mesh, Amplification and Node shaders which returns the index of the wave within the thread group that the the thread is executing.
  - GetGroupWaveCount: New intrinsic for Compute, Mesh, Amplification and Node
  shaders which returns the total number of waves executing within the thread
  group.
- Added `DebugBreak()` and `dx::IsDebuggingEnabled()` intrinsics for shader debugging (experimental Shader Model 6.10).
  - `DebugBreak()` triggers a breakpoint if debugging is enabled.
  - `dx::IsDebuggingEnabled()` returns true if debugging is enabled when the
    intrinsic executes.
  - SPIR-V: `DebugBreak()` emits `NonSemantic.DebugBreak` extended instruction; `IsDebuggingEnabled()` is not supported.

#### Bug Fixes

- Fixed non-deterministic DXIL/PDB output when compiling shaders with resource
  arrays, debug info, and SM 6.6+.
  [#8171](https://github.com/microsoft/DirectXShaderCompiler/issues/8171)
- Fixed mesh shader semantics that were incorrectly case sensitive.
- User-defined conversion operators (e.g., `operator float4()`) now produce an
  error instead of being silently ignored.
  [#5103](https://github.com/microsoft/DirectXShaderCompiler/pull/8206)
- DXIL validation: added validation for `CreateHandleFromBinding`.
- DXIL validation now rejects non-standard integer bit widths (e.g. `i25`) in
  instructions.

#### Other Changes

- `/P` now matches `cl.exe` behavior: preprocesses to `<inputname>.i` by
  default, with `/Fi` to override the output filename. The old FXC-style `/P
   <filename>` positional syntax has been renamed to `/Po`.
  [#4611](https://github.com/microsoft/DirectXShaderCompiler/issues/4611).
- SPIR-V: Support `vk::SampledTexture` types (GLSL's `samplerND` equivalent)
  [#7979](https://github.com/microsoft/DirectXShaderCompiler/issues/7979). With
  this type, users no longer need to define both Sampler and Texture resources
  with the same binding number.

### Version 1.9.2602

#### Shader Model 6.9 Release

- Shader Model 6.9 is fully supported.
  - See [the official blog
  post](https://devblogs.microsoft.com/directx/shader-model-6-9-dxr-1-2-and-agilitysdk-1-619-release)
  for more details.

#### Noteble SPIR-V updates

- Handle vector element assignment for asuint. [#8011](https://github.com/microsoft/DirectXShaderCompiler/issues/8011)
- Support sizeof(vk::BufferPointer). [#8010](https://github.com/microsoft/DirectXShaderCompiler/issues/8010)
- Scalar layout to follow C structure layout. [#7996](https://github.com/microsoft/DirectXShaderCompiler/issues/7996)
- Support asdouble() for uint3 argument type. [#7965](https://github.com/microsoft/DirectXShaderCompiler/issues/7965)
- Add const to many FeatureManager fns. [#7980](https://github.com/microsoft/DirectXShaderCompiler/issues/7980)
- Handle vk::BufferPointer in initializer list. [#7946](https://github.com/microsoft/DirectXShaderCompiler/issues/7946)
- Fix layout rule on ConstantBuffer alias. [#7960](https://github.com/microsoft/DirectXShaderCompiler/issues/7960)
- Fix layout rule for BufferPointer pointee type. [#7956](https://github.com/microsoft/DirectXShaderCompiler/issues/7956)
- Use desugared type when processing binary op. [#7948](https://github.com/microsoft/DirectXShaderCompiler/issues/7948)
- Handle associated counters for RWStructuredBuffer in base classes. [#7880](https://github.com/microsoft/DirectXShaderCompiler/issues/7880)
- Fix precision for dot2add. [#7861](https://github.com/microsoft/DirectXShaderCompiler/issues/7861)
- Support sign() intrinsics for unsigned integers. [#7845](https://github.com/microsoft/DirectXShaderCompiler/issues/7845)
- Fix resource heap & fvk-bind-register interactions. [#7858](https://github.com/microsoft/DirectXShaderCompiler/issues/7858)
- Fix incorrect branch gen on return. [#7834](https://github.com/microsoft/DirectXShaderCompiler/issues/7834)
- Add diagnostic for boolean bitfields. [#7722](https://github.com/microsoft/DirectXShaderCompiler/issues/7822)
- Implement WaveOpsIncludeHelperLanes. [#7806](https://github.com/microsoft/DirectXShaderCompiler/issues/7806)
- Fix spirv codegen for uabs intrinsic when argument is unsigned. [#7750](https://github.com/microsoft/DirectXShaderCompiler/issues/7750)
- Fix invalid codegen for empty cbuffers. [#7717](https://github.com/microsoft/DirectXShaderCompiler/issues/7717)
- Preserve NaN, Inf, and signed zeros w/ -Gis. [#7693](https://github.com/microsoft/DirectXShaderCompiler/issues/7693)
- Fix pcf with rich debug info enabled. [#7663](https://github.com/microsoft/DirectXShaderCompiler/issues/7663)
- Create only 1 DebugCompilationUnit per spirv module. [#7669](https://github.com/microsoft/DirectXShaderCompiler/issues/7669)
- Handle member traversal with template type. [#7674](https://github.com/microsoft/DirectXShaderCompiler/issues/7674)
- Handle partial template class specialization. [#7673](https://github.com/microsoft/DirectXShaderCompiler/issues/7673)
- Fix declaration order of values in decorations. [#7672](https://github.com/microsoft/DirectXShaderCompiler/issues/7672)
- Fix DebugSource for files which are not found. [#7662](https://github.com/microsoft/DirectXShaderCompiler/issues/7662)
- Fixed a crash if encounter constant buffer fields with overlapping register
  assignments. [#7636](https://github.com/microsoft/DirectXShaderCompiler/issues/7636)
- Add option to use the Unknown image format. [#7632](https://github.com/microsoft/DirectXShaderCompiler/issues/7632)
- Add the derivative group execution mode only on shader types that allow it. [#7628](https://github.com/microsoft/DirectXShaderCompiler/issues/7628)
- Allow spirv type as template parameter. [#7626](https://github.com/microsoft/DirectXShaderCompiler/issues/7626)
- Explicitly state which layout rules require scalar block layout. [#7539](https://github.com/microsoft/DirectXShaderCompiler/issues/7539)
- Emit DebugScope in wrapper. [#77341](https://github.com/microsoft/DirectXShaderCompiler/issues/7341)
- Use unknown image format in vk1.3 and later. [#7528](https://github.com/microsoft/DirectXShaderCompiler/issues/7528)
- Use OpCopyLogical to reconstruct values. [#7530](https://github.com/microsoft/DirectXShaderCompiler/issues/7530)
- AMD work graphs extension. [#7353](https://github.com/microsoft/DirectXShaderCompiler/issues/7353)
- Get Alignment from pointee type for vk::BufferPointer store. [#7501](https://github.com/microsoft/DirectXShaderCompiler/issues/7501)
- Fix bool cast on buffers with swizzle. [#7497](https://github.com/microsoft/DirectXShaderCompiler/issues/7497)
- Add payload to OpEmitMeshTasksEXT. [#7485](https://github.com/microsoft/DirectXShaderCompiler/issues/7485)
- Fix r-value being used in mul intrinsic. [#7489](https://github.com/microsoft/DirectXShaderCompiler/issues/7489)
- Several small bug fixes.

#### Other Changes
- Fixed regression: [#7510](https://github.com/microsoft/DirectXShaderCompiler/issues/7510) crash when calling `sizeof` on templated type.
- Fixed regression: [#7508](https://github.com/microsoft/DirectXShaderCompiler/issues/7508) crash when calling `Load` with `status`.
- Header file `dxcpix.h` was added to the release package.
- C4146 (unary minus operatore applied to unsigned type) enabled as a build
  break for MSVC builds.
- Implement isnormal function.
  [#7720](https://github.com/microsoft/DirectXShaderCompiler/issues/7720)
- Disallow 64bit msad, ibfe, and ubfe. [#7774](https://github.com/microsoft/DirectXShaderCompiler/issues/7774)
- Added support for `long long` and `unsigned long long` compile-time constant evaluation, fixes [#7952](https://github.com/microsoft/DirectXShaderCompiler/issues/7952).
- Added support for the groupshared attribute for parameters to Shader Model 6.10 [#8013](https://github.com/microsoft/DirectXShaderCompiler/pull/8013)

### Version 1.8.2505

#### Potentially breaking changes

- Typed buffers (including ROV buffers) no longer accept types other than vectors and scalars. Any other types will produce descriptive errors. This removes support for appropriately sized matrices and structs. Though it worked in some contexts, code generated from such types was unreliable.
  - Load and Store operations have been refactored as a consequence. Behavior should be identical, please file issues if discrepancies are observed.
- The compiler will now always use the internal validator instead of searching for an external DXIL.dll.  The (hidden) `-select-validator` option has been removed.

#### Notable SPIR-V updates

- Fix unnecessary Int64 requirement when loading Float64
- Added vk::BufferPointer, see [proposal](https://github.com/microsoft/hlsl-specs/blob/main/proposals/0010-vk-buffer-ref.md) for more details.
- Implement QuadAny and QuadAll (#7266)
- Fix -fvk-invert-y (#7447)

#### Shader Model 6.9 Preview

You can now compile shaders to SM 6.9, but this is a preview, so shader hashes will be set to the PREVIEW_BYPASS pattern.
SM 6.9 shaders will only work with AgilitySDK 1.717.0-preview, a supported preview driver, and use of experimental shader models in developer mode.
Preview shaders will not be compatible with the SM 6.9 release, or likely even later versions of the SM 6.9 preview.

SM 6.9 Preview Additions:

- Long vectors are allowed in HLSL when targeting shader model 6.9. Vectors up to 1024 elements in length can be loaded from/stored to raw buffers and used in elementwise operations. See the [long vector proposal](https://github.com/microsoft/hlsl-specs/blob/main/proposals/0026-hlsl-long-vector-type.md) for more details.
- HLSL Vectors are still limited to a maximum of 4 elements when used in certain contexts:
  - entry function inputs/outputs
  - parameter, payload, attribute, and node record types for mesh, raytracing, and node shaders
  - constant buffers (cbuffer), texture buffers (tbuffer), textures and typed buffers
  - Note: some HLSL elementwise intrinsics do not yet support long vectors in this preview
- Native vectors of up to 1024 elements are now present in DXIL. This includes vector llvm instructions, load/store, and various elementwise DXIL operations. This may result in smaller DXIL and potentially other performance improvements. See the [dxil vectors proposal](https://github.com/microsoft/hlsl-specs/blob/main/proposals/0030-dxil-vectors.md) for more details.
- Cooperative Vector operations, a subset of Linear Algebra (LinAlg). See the [cooperative vectors proposal](https://github.com/microsoft/hlsl-specs/blob/main/proposals/0029-cooperative-vector.md) and the [HLSL header based API proposal](https://github.com/microsoft/hlsl-specs/blob/main/proposals/0031-hlsl-vector-matrix-operations.md) for more details.
  - New built-in operations are added for multiplying long vectors with a matrix in a ByteAddressBuffer, optionally with accumulation and bias data, as well as outer product and vector accumulate operations.
  - An HLSL header shipped with this release provides a more convenient API for using these built-in operations.
- Support for [Opacity Micromaps](https://github.com/microsoft/hlsl-specs/blob/main/proposals/0024-opacity-micromaps.md) in DXR shaders as well as for RayQuery.
  - Unlocks DXR performance improvements using triangle sub-divisions for fast hit/miss detection to reduce the need for anyhit invocations.
- Support for [Shader Execution Reordering](https://github.com/microsoft/hlsl-specs/blob/main/proposals/0027-shader-execution-reordering.md) in DXR.
  - Introduces `MaybeReorderThread()` to explicitly specify where and how shader execution coherence can be improved. `MaybeReorderThread()` can be used in raygeneration shaders.
  - `HitObject` decouples traversal, intersection testing and anyhit shading from closesthit and miss shading for more control and better reordering opportunities. `HitObject` can be used in raygeneration, closesthit and miss shaders.

### Version 1.8.2502

This cumulative release contains numerous bug fixes and stability improvements.

Here are some highlights:

- The incomplete WaveMatrix implementation has been removed. [#6807](https://github.com/microsoft/DirectXShaderCompiler/pull/6807)
- DXIL Validator Hash is open sourced. [#6846](https://github.com/microsoft/DirectXShaderCompiler/pull/6846)
- DXIL container validation for PSV0 part allows any content ordering inside string and semantic index tables. [#6859](https://github.com/microsoft/DirectXShaderCompiler/pull/6859)
- The and() and or() intrinsics will now accept non-integer parameters by casting them to bools. [#7060](https://github.com/microsoft/DirectXShaderCompiler/pull/7060)
- Released executables will now expect the filenames associated with the released pdbs. Instead of expecting `dxc_full.pdb`, `dxc.exe` will now expect `dxc.pdb`.

### Version 1.8.2407

This cumulative release contains numerous bug fixes and stability improvments.

Here are some highlights:

- dxc generates invalid alignment on groupshared matrix load/store instructions in [#6416](https://github.com/microsoft/DirectXShaderCompiler/issues/6416)
- [Optimization] DXC is missing common factor optimization in some cases in [#6593](https://github.com/microsoft/DirectXShaderCompiler/issues/6593)
- [SPIR-V] Implement WaveMutliPrefix* in [#6600](https://github.com/microsoft/DirectXShaderCompiler/issues/6600)
- [SPIR-V] Implement SampleCmpLevel for SM6.7 in [#6613](https://github.com/microsoft/DirectXShaderCompiler/issues/6613)
- Avoid adding types to default namespace in [#6646](https://github.com/microsoft/DirectXShaderCompiler/issues/6646)
- Release notes once found in `README.md` can now be found in `ReleaseNotes.md`
- Fixed several bugs in the loop restructurizer. Shader developers who are using -opt-disable structurize-loop-exits-for-unroll to disable the loop restructurizer should consider removing that workaround.

### Version 1.8.2405

DX Compiler Release for May 2024

This release includes two major new elements:

- The introduction of the first component of HLSL 202x
- The inclusion of clang-built Windows binaries

See [the official blog post](https://devblogs.microsoft.com/directx/dxc-1-8-2405-available) for a more detailed description of this release.

HLSL 202x is a placeholder designation for what will ultimately be a new language version that further aligns HLSL with modern language features. It is intended to serve as a bridge to help transition to the expected behavior of the modernized compiler.

To experiment with 202x, use the `-HV 202x` flag. We recommend enabling these warnings as well to catch potential changes in behavior: `-Wconversion -Wdouble-promotion -Whlsl-legacy-literal`.

The first feature available in 202x updates HLSL's treatment of literals to better conform with C/C++. In previous versions, un-suffixed literal types targeted the highest possible precision. This feature revises that to mostly conform with C/C++ behavior. See the above blog post for details.

Clang-built Windows binaries are included in addition to the MSVC-built binaries that have always been shipped before. The clang-built compiler is expected to improve HLSL compile times in many cases. We are eager for feedback about this build positive or negative, related to compile times or correctness.

### Version 1.8.2403.2

DX Compiler Release for March 2024 - Patch 2

- Fix regression: [#6426](https://github.com/microsoft/DirectXShaderCompiler/issues/6426) Regression, SIGSEGV instead of diagnostics when encountering bool operator==(const T&, const T&).

### Version 1.8.2403.1

DX Compiler Release for March 2024 - Patch 1

- Fix regression: [#6419](https://github.com/microsoft/DirectXShaderCompiler/issues/6419) crash when using literal arguments with `fmod`.

### Version 1.8.2403

DX Compiler release for March 2024

- Shader Model 6.8 is fully supported
  - Work Graphs allow node shaders with user-defined input and output payloads
  - New Barrier builtin functions with specific memory types and semantics
  - Expanded Comparison sampler intrinsics: SampleCmpBias, SampleCmpGrad, and CalculateLevelOfDetail
  - StartVertexLocation and StartInstanceLocation semantics
  - WaveSizeRange entry point attribute allows specifying a range of supported wave sizes
- Improved compile-time validation and runtime validation information
- Various stability improvements including numerous address sanitation fixes
- Several Diagnostic improvements
  - Many diagnostics are generated earlier and with more detailed information
  - Library profile diagnostic improvements
  - No longer infer library shader type when not specified
  - More helpful diagnostics for numthreads and other entry point attributes
  - Validation errors more accurately determine usage by the entry point
- Improve debug info generation
- Further improvements to Linux build quality
- File paths arguments for `IDxcIncludeHandler::LoadSource` will now be normalized to use OS specific slashes
  (`\` for windows, `/` for *nix) and no longer have double slashes except for UNC paths (`\\my\unc\path`).”

### Version 1.7.2308

DX Compiler release for August 2023

- HLSL 2021 is now enabled by default
- Various HLSL 2021 fixes have been made to
  - Operator overloading fixes
  - Templates fixes
  - Select() with samplers
  - Bitfields show in reflections
  - Bitfields can be used on enums
  - Allow function template default params
- Issues with loading and using Linux binaries have been resolved
- Support #pragma region/endregion
- Various stability and diagnostic improvements
- Dxcapi.h inline documentation is improved
- Linking of libraries created by different compilers is disallowed to prevent interface Issues
- Inout parameter correctness improved

The package includes dxc.exe, dxcompiler.dll, corresponding lib and headers, and dxil.dll for x64 and arm64 platforms on Windows.
The package also includes Linux version of the compiler with corresponding executable, libdxcompiler.so, corresponding headers, and libdxil.so for x64 platforms.

The new DirectX 12 Agility SDK (Microsoft.Direct3D.D3D12 nuget package) and a hardware driver with appropriate support
are required to run shader model 6.7 shaders. Please see <https://aka.ms/directx12agility> for details.

The SPIR-V backend of the compiler has been enabled in this release.

### Version 1.7.2212

DX Compiler release for December 2022.

- Includes full support of HLSL 2021 for SPIRV generation as well as many HLSL 2021 fixes and enhancements:
  - HLSL 2021's `and`, `or` and `select` intrinsics are now exposed in all language modes. This was done to ease porting code bases to HLSL2021, but may cause name conflicts in existing code.
  - Improved template utility with user-defined types
  - Many additional bug fixes
- Linux binaries are now included.
 This includes the compiler executable, the dynamic library, and the dxil signing library.
- New flags for inspecting compile times:
  - `-ftime-report` flag prints a high level summary of compile time broken down by major phase or pass in the compiler. The DXC
command line will print the output to stdout.
  - `-ftime-trace` flag prints a Chrome trace json file. The output can be routed to a specific file by providing a filename to
the argument using the format `-ftime-trace=<filename>`. Chrome trace files can be opened in Chrome by loading the built-in tracing tool
at chrome://tracing. The trace file captures hierarchial timing data with additional context enabling a much more in-depth profiling
experience.
  - Both new options are supported via the DXC API using the `DXC_OUT_TIME_REPORT` and `DXC_OUT_TIME_TRACE` output kinds respectively.
- IDxcPdbUtils2 enables reading new PDB container part
- `-P` flag will now behave as it does with cl using the file specified by `-Fi` or a default
- Unbound multidimensional resource arrays are allowed
- Diagnostic improvements
- Reflection support on non-Windows platforms; minor updates adding RequiredFeatureFlags to library function reflection and thread group size for AS and MS.

The package includes dxc.exe, dxcompiler.dll, corresponding lib and headers, and dxil.dll for x64 and arm64 platforms on Windows.
For the first time the package also includes Linux version of the compiler with corresponding executable, libdxcompiler.so, corresponding headers, and libdxil.so for x64 platforms.

The new DirectX 12 Agility SDK (Microsoft.Direct3D.D3D12 nuget package) and a hardware driver with appropriate support
are required to run shader model 6.7 shaders. Please see <https://aka.ms/directx12agility> for details.

The SPIR-V backend of the compiler has been enabled in this release. Please note that Microsoft does not perform testing/verification of the SPIR-V backend.

### Version 1.7.2207

DX Compiler release for July 2022. Contains shader model 6.7 and many bug fixes and improvements, such as:

- Features: Shader Model 6.7 includes support for Raw Gather, Programmable Offsets, QuadAny/QuadAll, WaveOpsIncludeHelperLanes, and more!
- Platforms: ARM64 support
- HLSL 2021 : Enable “using” keyword
- Optimizations: Loop unrolling and dead code elimination improvements
- Developer tools: Improved disassembly output

The package includes dxc.exe, dxcompiler.dll, corresponding lib and headers, and dxil.dll for x64 and, for the first time, arm64 platforms!

The new DirectX 12 Agility SDK (Microsoft.Direct3D.D3D12 nuget package) and a hardware driver with appropriate support
are required to run shader model 6.7 shaders. Please see <https://aka.ms/directx12agility> for details.

The SPIR-V backend of the compiler has been enabled in this release. Please note that Microsoft does not perform testing/verification of the SPIR-V backend.
