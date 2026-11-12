//===------ FeatureManager.h - SPIR-V Version/Extension Manager -*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//===----------------------------------------------------------------------===//
//
//  This file defines a SPIR-V version and extension manager.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CLANG_LIB_SPIRV_FEATUREMANAGER_H
#define LLVM_CLANG_LIB_SPIRV_FEATUREMANAGER_H

#include <string>

#include "spirv-tools/libspirv.h"

#include "dxc/Support/SPIRVOptions.h"
#include "clang/Basic/Diagnostic.h"
#include "clang/Basic/SourceLocation.h"
#include "clang/Basic/VersionTuple.h"
#include "llvm/ADT/Optional.h"
#include "llvm/ADT/SmallBitVector.h"
#include "llvm/ADT/StringRef.h"

namespace clang {
namespace spirv {

/// A list of SPIR-V extensions known to our CodeGen.
enum class Extension {
  KHR = 0,
  KHR_8bit_storage,
  KHR_16bit_storage,
  KHR_device_group,
  KHR_fragment_shading_rate,
  KHR_non_semantic_info,
  KHR_multiview,
  KHR_shader_draw_parameters,
  KHR_post_depth_coverage,
  KHR_ray_tracing,
  KHR_shader_clock,
  EXT_demote_to_helper_invocation,
  EXT_descriptor_indexing,
  EXT_fragment_fully_covered,
  EXT_fragment_invocation_density,
  EXT_fragment_shader_interlock,
  EXT_mesh_shader,
  EXT_shader_stencil_export,
  EXT_shader_viewport_index_layer,
  AMD_gpu_shader_half_float,
  AMD_shader_early_and_late_fragment_tests,
  GOOGLE_hlsl_functionality1,
  GOOGLE_user_type,
  NV_ray_tracing,
  NV_mesh_shader,
  KHR_ray_query,
  EXT_shader_image_int64,
  KHR_physical_storage_buffer,
  AMD_shader_enqueue,
  KHR_vulkan_memory_model,
  NV_compute_shader_derivatives,
  KHR_compute_shader_derivatives,
  KHR_fragment_shader_barycentric,
  KHR_maximal_reconvergence,
  KHR_float_controls,
  NV_shader_subgroup_partitioned,
  KHR_quad_control,
  EXT_descriptor_heap,
  KHR_untyped_pointers,
  KHR_workgroup_memory_explicit_layout,
  EXT_shader_atomic_float_add,
  EXT_shader_atomic_float_min_max,
  // HLSL Change - SPV_KHR_bfloat16 (bfloat16_t type support).
  KHR_bfloat16,
  // HLSL Change - SPV_EXT_float8 (float8_e4m3_t / float8_e5m2_t).
  EXT_float8,
    // HLSL Change - SPV_KHR_fma (OpFmaKHR for HLSL fused multiply-add).
    KHR_fma,
    // HLSL Change - SPV_EXT_split_barrier (vk::SplitBarrierArrive/Wait).
    EXT_split_barrier,
    // HLSL Change - SPV_EXT_shader_subgroup_partitioned, the standardised name
    // of SPV_NV_shader_subgroup_partitioned. Both extensions name the same
    // capability (GroupNonUniformPartitionedEXT ==
    // GroupNonUniformPartitionedNV == 5297), so only one of the two may be
    // emitted for a module; see getShaderSubgroupPartitionedProvider().
    EXT_shader_subgroup_partitioned,
      // HLSL Change - SPV_QCOM_multiple_wait_queues
      // ([[vk::multiple_wait_queues]] on a loop).
      QCOM_multiple_wait_queues,
  // HLSL Change - SPV_NV_push_constant_bank ([[vk::push_constant_bank(N)]]
  // and [[vk::push_constant_bank_offset(N)]] on a push constant block).
  NV_push_constant_bank,
  // HLSL Change - SPV_VALVE_mixed_float_dot_product (OpFDot2MixAcc32VALVE for
  // HLSL's dot2add intrinsic).
  VALVE_mixed_float_dot_product,
  // HLSL Change - SPV_KHR_opacity_micromap (the OpacityMicromapIdKHR execution
  // mode derived from the HLSL opacity-micromap ray flags).
  KHR_opacity_micromap,
  // HLSL Change - SPV_NV_cluster_acceleration_structure
  // (OpRayQueryGetIntersectionClusterIdNV, the cluster-ID accessors in
  // <vk/nv/cluster_as.h>).
  NV_cluster_acceleration_structure,
  // HLSL Change - SPV_NV_linear_swept_spheres (the OpRayQuery*Sphere*NV /
  // OpRayQuery*LSS*NV accessors in <vk/nv/linear_swept_spheres.h>).
  NV_linear_swept_spheres,
  // HLSL Change - SPV_QCOM_image_processing3 (OpImageGatherQCOM, the gather
  // entry points in <vk/qcom/image_processing3.h>).
  QCOM_image_processing3,
  // HLSL Change - SPV_KHR_constant_data (OpConstantDataKHR for
  // -fspv-constant-data).
  KHR_constant_data,
    // HLSL Change - SPV_KHR_abort (OpAbortKHR for vk::Abort).
    KHR_abort,
    // HLSL Change - SPV_ARM_cooperative_matrix_layouts (the
    // RowBlockedInterleavedARM / ColumnBlockedInterleavedARM MemoryLayout
    // operands of OpCooperativeMatrixLoadKHR / OpCooperativeMatrixStoreKHR, and
    // the entry points in <vk/arm/cooperative_matrix_layouts.h>).
    ARM_cooperative_matrix_layouts,
    // HLSL Change - SPV_EXT_cooperative_matrix_maintenance1
    // (OpCooperativeMatrixConvertUseEXT, OpCooperativeMatrixReduceEXT,
    // OpCooperativeMatrixPerElementOpEXT and
    // OpCooperativeMatrixGetCoordinateEXT, the entry points in
    // <vk/khr/cooperative_matrix.h>). Enabled by default; see
    // enabledByDefault() in FeatureManager.cpp.
    EXT_cooperative_matrix_maintenance1,
    // HLSL Change - SPV_EXT_long_vector (OpTypeVector with more than four
    // components, the vk::ext::LongVector type in <vk/ext/long_vector.h>).
    // Opt-in; see enabledByDefault() in FeatureManager.cpp.
    EXT_long_vector,
    // HLSL Change - SPV_NV_cooperative_vector (OpTypeVectorIdEXT as a
    // cooperative vector type and the six OpCooperativeVector*NV operations,
    // the entry points in <vk/nv/cooperative_vector.h>). Opt-in; see
    // enabledByDefault() in FeatureManager.cpp.
    NV_cooperative_vector,
      // HLSL Change - SPV_NV_tensor_addressing (OpTypeTensorLayoutNV /
      // OpTypeTensorViewNV and OpCapability TensorAddressingNV, the tensor
      // layout that OpCooperativeMatrixLoadTensorNV reads through). It is the
      // base the other two entries below build on, so it is enabled by default;
      // see enabledByDefault() in FeatureManager.cpp.
      NV_tensor_addressing,
      // HLSL Change - SPV_NV_cooperative_matrix2's tensor half
      // (OpCooperativeMatrixLoadTensorNV / OpCooperativeMatrixStoreTensorNV and
      // OpCapability CooperativeMatrixTensorAddressingNV /
      // CooperativeMatrixBlockLoadsNV). Enabled by default. The already landed
      // SPV_NV_cooperative_matrix2 reduce / per-element operations do not route
      // their OpExtension through this entry (they pass the string straight to
      // SpirvBuilder::createSpirvIntrInstExt, see
      // SpirvEmitter::processCooperativeMatrixReduce), so registering it does not
      // change their code generation.
      NV_cooperative_matrix2,
      // HLSL Change - SPV_NV_cooperative_matrix_decode_vector (the
      // TensorAddressingOperands DecodeVectorFunc bit of
      // OpCooperativeMatrixLoadTensorNV, the entry point in
      // <vk/nv/cooperative_matrix_decode_vector.h>). Opt-in; see
      // enabledByDefault() in FeatureManager.cpp.
      NV_cooperative_matrix_decode_vector,
      // HLSL Change - SPV_ARM_tensors (OpTypeTensorARM, the OpTensorReadARM /
      // OpTensorWriteARM / OpTensorQuerySizeARM operations, and the
      // vk::arm::Tensor type with its accessors in <vk/arm/tensors.h>). Enabled
      // by default; see enabledByDefault() in FeatureManager.cpp.
      ARM_tensors,
        // HLSL Change - SPV_ARM_graph (the module-scope graph region of
        // VK_ARM_data_graph: OpGraphARM, OpGraphEntryPointARM, OpGraphInputARM,
        // OpGraphSetOutputARM and OpGraphEndARM, declared by the entry points in
        // <vk/arm/graph.h>). Enabled by default; see enabledByDefault() in
        // FeatureManager.cpp.
        ARM_graph,
      // HLSL Change - SPV_EXT_shader_invocation_reorder
      // (OpTypeHitObjectEXT, the OpHitObject*EXT accessors and the
      // OpReorderThreadWithHintEXT / OpReorderThreadWithHitObjectEXT entry
      // points, i.e. the API of <vk/ext/invocation_reorder.h>). Opt-in; see
      // enabledByDefault() in FeatureManager.cpp.
      EXT_shader_invocation_reorder,
      // HLSL Change - SPV_NV_ray_tracing_motion_blur, requested only by
      // OpHitObjectGetCurrentTimeEXT (SPIRV-Tools: "<op>: requires
      // RayTracingMotionBlurNV capability"), which is why the one accessor of
      // <vk/ext/invocation_reorder.h> that needs it declares both extensions.
      // Opt-in; see enabledByDefault() in FeatureManager.cpp.
      NV_ray_tracing_motion_blur,
      // HLSL Change - SPV_QCOM_tile_shading. Tile-resident attachments (the
      // TileAttachmentQCOM storage class), the TileOffsetQCOM /
      // TileDimensionQCOM / TileApronSizeQCOM built-ins and the
      // TileShadingRateQCOM / NonCoherentTileAttachmentReadQCOM execution
      // modes, i.e. the API of <vk/qcom/tile_shading.h>. Opt-in; see
      // enabledByDefault() in FeatureManager.cpp.
      QCOM_tile_shading,
      Unknown,
};

/// The class for handling SPIR-V version and extension requests.
class FeatureManager {
public:
  FeatureManager(DiagnosticsEngine &de, const SpirvCodeGenOptions &);

  /// Allows the given extension to be used in CodeGen.
  bool allowExtension(llvm::StringRef);

  /// Allows all extensions to be used in CodeGen.
  void allowAllKnownExtensions();

  /// Requests the given extension for translating the given target feature at
  /// the given source location. Emits an error if the given extension is not
  /// permitted to use.
  bool requestExtension(Extension, llvm::StringRef target, SourceLocation);

  /// Translates extension name to symbol.
  Extension getExtensionSymbol(llvm::StringRef name);

  /// Translates extension symbol to name.
  const char *getExtensionName(Extension symbol);

  /// Returns true if the given extension is a KHR extension.
  bool isKHRExtension(llvm::StringRef name) const;

  /// Returns the names of all known extensions as a string.
  std::string getKnownExtensions(const char *delimiter, const char *prefix = "",
                                 const char *postfix = "");

  /// Request the given target environment for translating the given feature at
  /// the given source location. Emits an error if the requested target
  /// environment does not match user's target environemnt.
  bool requestTargetEnv(spv_target_env, llvm::StringRef target, SourceLocation);

  /// Returns the target environment corresponding to the target environment
  /// that was specified as command line option. If no option is specified, the
  /// default (Vulkan 1.0) is returned.
  spv_target_env getTargetEnv() const { return targetEnv; }

  /// Returns true if the given extension is not part of the core of the target
  /// environment.
  bool isExtensionRequiredForTargetEnv(Extension) const;

  /// Returns true if the given extension is set in allowedExtensions
  bool isExtensionEnabled(Extension) const;

  /// \brief Returns the allowed extension that provides the acceleration
  /// structure type, or Extension::Unknown if there is none.
  Extension getAccelerationStructureProvider() const;

  /// \brief Returns true if the user listed, with -fspv-extension, an extension
  /// that provides the acceleration structure type.
  /// When no list is given, returns false.
  bool hasExplicitAccelerationStructureProvider() const;

  /// HLSL Change - Returns the allowed extension that provides the partitioned
  /// wave operations (WaveMatch and the WaveMultiPrefix* family), or
  /// Extension::Unknown if neither SPV_EXT_shader_subgroup_partitioned nor
  /// SPV_NV_shader_subgroup_partitioned is enabled.
  ///
  /// The two extensions are two names for one capability
  /// (GroupNonUniformPartitionedEXT == GroupNonUniformPartitionedNV == 5297),
  /// so a module must declare at most one of them. The standardised EXT
  /// spelling wins when the user lists both; when no -fspv-extension is given
  /// only the NV spelling is enabled, which is what DXC emitted historically.
  Extension getShaderSubgroupPartitionedProvider() const;

  /// Returns true if the target environment is Vulkan 1.1 or above.
  /// Returns false otherwise.
  bool isTargetEnvVulkan1p1OrAbove() const;

  /// Returns true if the target environment is SPIR-V 1.4 or above.
  /// Returns false otherwise.
  bool isTargetEnvSpirv1p4OrAbove() const;

  // HLSL Change Begin - SPV_EXT_long_vector.
  /// Returns true if the target environment emits SPIR-V 1.3 or above, the
  /// SPIR-V version SPV_EXT_long_vector is specified against.
  ///
  /// Unlike the isTargetEnvVulkan*OrAbove() predicates this one compares the
  /// SPIR-V version the target environment emits, because spv_target_env orders
  /// the Vulkan environments after every universal one: vulkan1.0 is SPIR-V 1.0
  /// even though the enumerator sorts above SPV_ENV_UNIVERSAL_1_3.
  bool isTargetEnvSpirv1p3OrAbove() const;

  /// Requires a SPIR-V 1.3 target environment for the given feature. Emits an
  /// error and returns false if the target environment emits an earlier SPIR-V
  /// version.
  bool requestTargetEnvSpirv1p3(llvm::StringRef target, SourceLocation);

  /// Emits an error with the given message at the given source location. Used by
  /// CapabilityVisitor, which has no DiagnosticsEngine of its own.
  template <unsigned N>
  void reportError(const char (&message)[N], SourceLocation loc) {
    diags.Report(loc, diags.getCustomDiagID(clang::DiagnosticsEngine::Error,
                                            message));
  }
  // HLSL Change End - SPV_EXT_long_vector.

  /// Returns true if the target environment is Vulkan 1.1 with SPIR-V 1.4 or
  /// above. Returns false otherwise.
  bool isTargetEnvVulkan1p1Spirv1p4OrAbove() const;

  /// Returns true if the target environment is Vulkan 1.2 or above.
  /// Returns false otherwise.
  bool isTargetEnvVulkan1p2OrAbove() const;

  /// Returns true if the target environment is Vulkan 1.3 or above.
  /// Returns false otherwise.
  bool isTargetEnvVulkan1p3OrAbove() const;

  /// Return true if the target environment is a Vulkan environment.
  bool isTargetEnvVulkan() const;

  /// Returns the spv_target_env matching the input string if possible.
  /// This functions matches the spv_target_env with the command-line version
  /// of the name ('vulkan1.1', not 'Vulkan 1.1').
  /// Returns an empty Optional if no matching env is found.
  static llvm::Optional<spv_target_env>
  stringToSpvEnvironment(const std::string &target_env);

  // Returns the SPIR-V version used for the target environment.
  static clang::VersionTuple getSpirvVersion(spv_target_env env);

  /// Returns the equivalent to spv_target_env in pretty, human readable form.
  /// (SPV_ENV_VULKAN_1_0 -> "Vulkan 1.0").
  /// Returns an empty Optional if the name cannot be matched.
  static llvm::Optional<std::string>
  spvEnvironmentToPrettyName(spv_target_env target_env);

private:
  /// Returns whether codegen should allow usage of this extension by default.
  bool enabledByDefault(Extension);

  /// \brief Wrapper method to create an error message and report it
  /// in the diagnostic engine associated with this object.
  template <unsigned N>
  DiagnosticBuilder emitError(const char (&message)[N], SourceLocation loc) {
    const auto diagId =
        diags.getCustomDiagID(clang::DiagnosticsEngine::Error, message);
    return diags.Report(loc, diagId);
  }

  /// \brief Wrapper method to create an note message and report it
  /// in the diagnostic engine associated with this object.
  template <unsigned N>
  DiagnosticBuilder emitNote(const char (&message)[N], SourceLocation loc) {
    const auto diagId =
        diags.getCustomDiagID(clang::DiagnosticsEngine::Note, message);
    return diags.Report(loc, diagId);
  }

  DiagnosticsEngine &diags;

  llvm::SmallBitVector allowedExtensions;
  bool hasExplicitExtensions = false;
  spv_target_env targetEnv;
  std::string targetEnvStr;
};

} // end namespace spirv
} // end namespace clang

#endif // LLVM_CLANG_LIB_SPIRV_FEATUREMANAGER_H
