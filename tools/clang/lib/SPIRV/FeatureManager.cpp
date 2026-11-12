//===---- FeatureManager.cpp - SPIR-V Version/Extension Manager -*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//===----------------------------------------------------------------------===//

#include "clang/SPIRV/FeatureManager.h"

#include <array>
#include <sstream>

#include "llvm/ADT/Optional.h"
#include "llvm/ADT/StringSwitch.h"

namespace clang {
namespace spirv {
namespace {

constexpr std::array<std::pair<const char *, spv_target_env>, 6>
    kKnownTargetEnv = {{{"vulkan1.0", SPV_ENV_VULKAN_1_0},
                        {"vulkan1.1", SPV_ENV_VULKAN_1_1},
                        {"vulkan1.1spirv1.4", SPV_ENV_VULKAN_1_1_SPIRV_1_4},
                        {"vulkan1.2", SPV_ENV_VULKAN_1_2},
                        {"vulkan1.3", SPV_ENV_VULKAN_1_3},
                        {"universal1.5", SPV_ENV_UNIVERSAL_1_5}}};

constexpr std::array<std::pair<spv_target_env, const char *>, 6>
    kHumanReadableTargetEnv = {
        {{SPV_ENV_VULKAN_1_0, "Vulkan 1.0"},
         {SPV_ENV_VULKAN_1_1, "Vulkan 1.1"},
         {SPV_ENV_VULKAN_1_1_SPIRV_1_4, "Vulkan 1.1 with SPIR-V 1.4"},
         {SPV_ENV_VULKAN_1_2, "Vulkan 1.2"},
         {SPV_ENV_VULKAN_1_3, "Vulkan 1.3"},
         {SPV_ENV_UNIVERSAL_1_5, "SPIR-V 1.5"}}};

constexpr std::array<std::pair<spv_target_env, std::pair<uint32_t, uint32_t>>,
                     6>
    kTargetEnvToSpirvVersion = {{{SPV_ENV_VULKAN_1_0, {1, 0}},
                                 {SPV_ENV_VULKAN_1_1, {1, 3}},
                                 {SPV_ENV_VULKAN_1_1_SPIRV_1_4, {1, 4}},
                                 {SPV_ENV_VULKAN_1_2, {1, 5}},
                                 {SPV_ENV_VULKAN_1_3, {1, 6}},
                                 {SPV_ENV_UNIVERSAL_1_5, {1, 5}}}};

static_assert(
    kKnownTargetEnv.size() == kHumanReadableTargetEnv.size(),
    "kKnownTargetEnv and kHumanReadableTargetEnv should remain in sync.");

} // end namespace

llvm::Optional<spv_target_env>
FeatureManager::stringToSpvEnvironment(const std::string &target_env) {
  auto it =
      std::find_if(kKnownTargetEnv.cbegin(), kKnownTargetEnv.cend(),
                   [&](const auto &pair) { return pair.first == target_env; });

  return it == kKnownTargetEnv.end()
             ? llvm::None
             : llvm::Optional<spv_target_env>(it->second);
}

clang::VersionTuple FeatureManager::getSpirvVersion(spv_target_env env) {
  auto it = std::find_if(kTargetEnvToSpirvVersion.cbegin(),
                         kTargetEnvToSpirvVersion.cend(),
                         [&](const auto &pair) { return pair.first == env; });

  return it == kTargetEnvToSpirvVersion.end()
             ? clang::VersionTuple()
             : clang::VersionTuple(it->second.first, it->second.second);
}

llvm::Optional<std::string>
FeatureManager::spvEnvironmentToPrettyName(spv_target_env target_env) {
  auto it = std::find_if(
      kHumanReadableTargetEnv.cbegin(), kHumanReadableTargetEnv.cend(),
      [&](const auto &pair) { return pair.first == target_env; });
  return it == kHumanReadableTargetEnv.end()
             ? llvm::None
             : llvm::Optional<std::string>(it->second);
}

FeatureManager::FeatureManager(DiagnosticsEngine &de,
                               const SpirvCodeGenOptions &opts)
    : diags(de) {
  allowedExtensions.resize(static_cast<unsigned>(Extension::Unknown) + 1);

  targetEnvStr = opts.targetEnv;

  llvm::Optional<spv_target_env> targetEnvOpt =
      stringToSpvEnvironment(opts.targetEnv);
  if (!targetEnvOpt) {
    emitError("unknown SPIR-V target environment '%0'", {}) << opts.targetEnv;
    emitNote("allowed options are:\n vulkan1.0\n vulkan1.1\n "
             "vulkan1.1spirv1.4\n vulkan1.2\n vulkan1.3\n universal1.5",
             {});
    return;
  }
  targetEnv = *targetEnvOpt;

  hasExplicitExtensions = !opts.allowedExtensions.empty();
  if (!hasExplicitExtensions) {
    // If no explicit extension control from command line, use the default mode:
    // allowing all extensions that are enabled by default.
    allowAllKnownExtensions();
  } else {
    for (auto ext : opts.allowedExtensions)
      allowExtension(ext);

    // The option to use the vulkan memory model implies the extension is
    // available.
    if (opts.useVulkanMemoryModel) {
      allowExtension("SPV_KHR_vulkan_memory_model");
    }
  }
}

bool FeatureManager::allowExtension(llvm::StringRef name) {
  // Special case: If we are asked to allow "SPV_KHR" extension, it indicates
  // that we should allow using *all* KHR extensions.
  if (getExtensionSymbol(name) == Extension::KHR) {
    bool result = true;
    for (uint32_t i = 0; i < static_cast<uint32_t>(Extension::Unknown); ++i) {
      llvm::StringRef extName(getExtensionName(static_cast<Extension>(i)));
      if (isKHRExtension(extName))
        result = result && allowExtension(extName);
    }
    return result;
  }

  const auto symbol = getExtensionSymbol(name);
  if (symbol == Extension::Unknown) {
    emitError("unknown SPIR-V extension '%0'", {}) << name;
    emitNote("known extensions are\n%0", {})
        << getKnownExtensions("\n* ", "* ");
    return false;
  }

  allowedExtensions.set(static_cast<unsigned>(symbol));

  return true;
}

void FeatureManager::allowAllKnownExtensions() {
  allowedExtensions.set();
  const auto numExtensions = static_cast<uint32_t>(Extension::Unknown);
  for (uint32_t ext = 0; ext < numExtensions; ++ext)
    if (!enabledByDefault(static_cast<Extension>(ext)))
      allowedExtensions.reset(ext);
}

bool FeatureManager::requestExtension(Extension ext, llvm::StringRef target,
                                      SourceLocation srcLoc) {
  if (allowedExtensions.test(static_cast<unsigned>(ext)))
    return true;

  emitError("SPIR-V extension '%0' required for %1 but not permitted to use",
            srcLoc)
      << getExtensionName(ext) << target;
  return false;
}

bool FeatureManager::requestTargetEnv(spv_target_env requestedEnv,
                                      llvm::StringRef target,
                                      SourceLocation srcLoc) {
  if (targetEnv < requestedEnv) {
    auto envName = spvEnvironmentToPrettyName(requestedEnv);
    emitError("%0 is required for %1 but not permitted to use", srcLoc)
        << envName.getValueOr("unknown") << target;
    emitNote("please specify your target environment via command line option "
             "-fspv-target-env=",
             {});
    return false;
  }
  return true;
}

Extension FeatureManager::getExtensionSymbol(llvm::StringRef name) {
  return llvm::StringSwitch<Extension>(name)
      .Case("KHR", Extension::KHR)
      .Case("SPV_KHR_8bit_storage", Extension::KHR_8bit_storage)
      .Case("SPV_KHR_16bit_storage", Extension::KHR_16bit_storage)
      .Case("SPV_KHR_device_group", Extension::KHR_device_group)
      .Case("SPV_KHR_multiview", Extension::KHR_multiview)
      .Case("SPV_KHR_non_semantic_info", Extension::KHR_non_semantic_info)
      .Case("SPV_KHR_shader_draw_parameters",
            Extension::KHR_shader_draw_parameters)
      .Case("SPV_KHR_ray_tracing", Extension::KHR_ray_tracing)
      .Case("SPV_EXT_demote_to_helper_invocation",
            Extension::EXT_demote_to_helper_invocation)
      .Case("SPV_EXT_descriptor_indexing", Extension::EXT_descriptor_indexing)
      .Case("SPV_EXT_fragment_fully_covered",
            Extension::EXT_fragment_fully_covered)
      .Case("SPV_EXT_fragment_invocation_density",
            Extension::EXT_fragment_invocation_density)
      .Case("SPV_EXT_fragment_shader_interlock",
            Extension::EXT_fragment_shader_interlock)
      .Case("SPV_EXT_mesh_shader", Extension::EXT_mesh_shader)
      .Case("SPV_EXT_shader_stencil_export",
            Extension::EXT_shader_stencil_export)
      .Case("SPV_EXT_shader_viewport_index_layer",
            Extension::EXT_shader_viewport_index_layer)
      .Case("SPV_AMD_shader_early_and_late_fragment_tests",
            Extension::AMD_shader_early_and_late_fragment_tests)
      .Case("SPV_GOOGLE_hlsl_functionality1",
            Extension::GOOGLE_hlsl_functionality1)
      .Case("SPV_GOOGLE_user_type", Extension::GOOGLE_user_type)
      .Case("SPV_KHR_post_depth_coverage", Extension::KHR_post_depth_coverage)
      .Case("SPV_KHR_shader_clock", Extension::KHR_shader_clock)
      .Case("SPV_NV_ray_tracing", Extension::NV_ray_tracing)
      .Case("SPV_NV_mesh_shader", Extension::NV_mesh_shader)
      .Case("SPV_KHR_ray_query", Extension::KHR_ray_query)
      .Case("SPV_KHR_fragment_shading_rate",
            Extension::KHR_fragment_shading_rate)
      .Case("SPV_EXT_shader_image_int64", Extension::EXT_shader_image_int64)
      .Case("SPV_KHR_physical_storage_buffer",
            Extension::KHR_physical_storage_buffer)
      .Case("SPV_AMDX_shader_enqueue", Extension::AMD_shader_enqueue)
      .Case("SPV_KHR_vulkan_memory_model", Extension::KHR_vulkan_memory_model)
      .Case("SPV_KHR_compute_shader_derivatives",
            Extension::KHR_compute_shader_derivatives)
      .Case("SPV_NV_compute_shader_derivatives",
            Extension::NV_compute_shader_derivatives)
      .Case("SPV_KHR_fragment_shader_barycentric",
            Extension::KHR_fragment_shader_barycentric)
      .Case("SPV_KHR_maximal_reconvergence",
            Extension::KHR_maximal_reconvergence)
      .Case("SPV_KHR_float_controls", Extension::KHR_float_controls)
      .Case("SPV_NV_shader_subgroup_partitioned",
            Extension::NV_shader_subgroup_partitioned)
      .Case("SPV_KHR_quad_control", Extension::KHR_quad_control)
      .Case("SPV_EXT_descriptor_heap", Extension::EXT_descriptor_heap)
      .Case("SPV_KHR_untyped_pointers", Extension::KHR_untyped_pointers)
      .Case("SPV_KHR_workgroup_memory_explicit_layout",
            Extension::KHR_workgroup_memory_explicit_layout)
      .Case("SPV_EXT_shader_atomic_float_add", Extension::EXT_shader_atomic_float_add)
      .Case("SPV_EXT_shader_atomic_float_min_max", Extension::EXT_shader_atomic_float_min_max)
        // HLSL Change - SPV_KHR_bfloat16 (bfloat16_t type support).
        .Case("SPV_KHR_bfloat16", Extension::KHR_bfloat16)
        // HLSL Change - SPV_KHR_fma (OpFmaKHR for HLSL fused multiply-add).
        .Case("SPV_KHR_fma", Extension::KHR_fma)
        // HLSL Change - SPV_EXT_split_barrier.
        .Case("SPV_EXT_split_barrier", Extension::EXT_split_barrier)
        // HLSL Change - SPV_EXT_shader_subgroup_partitioned.
        .Case("SPV_EXT_shader_subgroup_partitioned",
              Extension::EXT_shader_subgroup_partitioned)
          // HLSL Change - SPV_QCOM_multiple_wait_queues.
          .Case("SPV_QCOM_multiple_wait_queues",
                Extension::QCOM_multiple_wait_queues)
        // HLSL Change - SPV_NV_push_constant_bank.
        .Case("SPV_NV_push_constant_bank", Extension::NV_push_constant_bank)
        // HLSL Change - SPV_VALVE_mixed_float_dot_product.
        .Case("SPV_VALVE_mixed_float_dot_product",
              Extension::VALVE_mixed_float_dot_product)
        // HLSL Change - SPV_KHR_opacity_micromap.
        .Case("SPV_KHR_opacity_micromap", Extension::KHR_opacity_micromap)
        // HLSL Change - SPV_NV_cluster_acceleration_structure.
        .Case("SPV_NV_cluster_acceleration_structure",
              Extension::NV_cluster_acceleration_structure)
        // HLSL Change - SPV_NV_linear_swept_spheres.
        .Case("SPV_NV_linear_swept_spheres",
              Extension::NV_linear_swept_spheres)
        // HLSL Change - SPV_QCOM_image_processing3.
        .Case("SPV_QCOM_image_processing3",
              Extension::QCOM_image_processing3)
          // HLSL Change - SPV_KHR_constant_data.
          .Case("SPV_KHR_constant_data",
                Extension::KHR_constant_data)
.Case("SPV_KHR_abort", Extension::KHR_abort)
          // HLSL Change - SPV_ARM_cooperative_matrix_layouts.
          .Case("SPV_ARM_cooperative_matrix_layouts",
                Extension::ARM_cooperative_matrix_layouts)
          .Default(Extension::Unknown);
}

const char *FeatureManager::getExtensionName(Extension symbol) {
  switch (symbol) {
  case Extension::KHR:
    return "KHR";
  case Extension::KHR_8bit_storage:
    return "SPV_KHR_8bit_storage";
  case Extension::KHR_16bit_storage:
    return "SPV_KHR_16bit_storage";
  case Extension::KHR_device_group:
    return "SPV_KHR_device_group";
  case Extension::KHR_multiview:
    return "SPV_KHR_multiview";
  case Extension::KHR_non_semantic_info:
    return "SPV_KHR_non_semantic_info";
  case Extension::KHR_shader_draw_parameters:
    return "SPV_KHR_shader_draw_parameters";
  case Extension::KHR_post_depth_coverage:
    return "SPV_KHR_post_depth_coverage";
  case Extension::KHR_ray_tracing:
    return "SPV_KHR_ray_tracing";
  case Extension::KHR_shader_clock:
    return "SPV_KHR_shader_clock";
  case Extension::EXT_demote_to_helper_invocation:
    return "SPV_EXT_demote_to_helper_invocation";
  case Extension::EXT_descriptor_indexing:
    return "SPV_EXT_descriptor_indexing";
  case Extension::EXT_fragment_fully_covered:
    return "SPV_EXT_fragment_fully_covered";
  case Extension::EXT_fragment_invocation_density:
    return "SPV_EXT_fragment_invocation_density";
  case Extension::EXT_fragment_shader_interlock:
    return "SPV_EXT_fragment_shader_interlock";
  case Extension::EXT_mesh_shader:
    return "SPV_EXT_mesh_shader";
  case Extension::EXT_shader_stencil_export:
    return "SPV_EXT_shader_stencil_export";
  case Extension::EXT_shader_viewport_index_layer:
    return "SPV_EXT_shader_viewport_index_layer";
  case Extension::AMD_shader_early_and_late_fragment_tests:
    return "SPV_AMD_shader_early_and_late_fragment_tests";
  case Extension::GOOGLE_hlsl_functionality1:
    return "SPV_GOOGLE_hlsl_functionality1";
  case Extension::GOOGLE_user_type:
    return "SPV_GOOGLE_user_type";
  case Extension::NV_ray_tracing:
    return "SPV_NV_ray_tracing";
  case Extension::NV_mesh_shader:
    return "SPV_NV_mesh_shader";
  case Extension::KHR_ray_query:
    return "SPV_KHR_ray_query";
  case Extension::KHR_fragment_shading_rate:
    return "SPV_KHR_fragment_shading_rate";
  case Extension::EXT_shader_image_int64:
    return "SPV_EXT_shader_image_int64";
  case Extension::KHR_physical_storage_buffer:
    return "SPV_KHR_physical_storage_buffer";
  case Extension::AMD_shader_enqueue:
    return "SPV_AMDX_shader_enqueue";
  case Extension::KHR_vulkan_memory_model:
    return "SPV_KHR_vulkan_memory_model";
  case Extension::KHR_compute_shader_derivatives:
    return "SPV_KHR_compute_shader_derivatives";
  case Extension::NV_compute_shader_derivatives:
    return "SPV_NV_compute_shader_derivatives";
  case Extension::KHR_fragment_shader_barycentric:
    return "SPV_KHR_fragment_shader_barycentric";
  case Extension::KHR_maximal_reconvergence:
    return "SPV_KHR_maximal_reconvergence";
  case Extension::KHR_float_controls:
    return "SPV_KHR_float_controls";
  case Extension::NV_shader_subgroup_partitioned:
    return "SPV_NV_shader_subgroup_partitioned";
  case Extension::KHR_quad_control:
    return "SPV_KHR_quad_control";
  case Extension::EXT_descriptor_heap:
    return "SPV_EXT_descriptor_heap";
  case Extension::KHR_untyped_pointers:
    return "SPV_KHR_untyped_pointers";
  case Extension::KHR_workgroup_memory_explicit_layout:
    return "SPV_KHR_workgroup_memory_explicit_layout";
  case Extension::EXT_shader_atomic_float_add:
    return "SPV_EXT_shader_atomic_float_add";
  case Extension::EXT_shader_atomic_float_min_max:
    return "SPV_EXT_shader_atomic_float_min_max";
  // HLSL Change - SPV_KHR_bfloat16 (bfloat16_t type support).
  case Extension::KHR_bfloat16:
 return "SPV_KHR_bfloat16";
    // HLSL Change - SPV_KHR_fma (OpFmaKHR for HLSL fused multiply-add).
    case Extension::KHR_fma:
      return "SPV_KHR_fma";
    // HLSL Change - SPV_EXT_split_barrier.
    case Extension::EXT_split_barrier:
      return "SPV_EXT_split_barrier";
    // HLSL Change - SPV_EXT_shader_subgroup_partitioned.
    case Extension::EXT_shader_subgroup_partitioned:
      return "SPV_EXT_shader_subgroup_partitioned";
      // HLSL Change - SPV_QCOM_multiple_wait_queues.
      case Extension::QCOM_multiple_wait_queues:
        return "SPV_QCOM_multiple_wait_queues";
    // HLSL Change - SPV_NV_push_constant_bank.
    case Extension::NV_push_constant_bank:
      return "SPV_NV_push_constant_bank";
    // HLSL Change - SPV_VALVE_mixed_float_dot_product.
    case Extension::VALVE_mixed_float_dot_product:
      return "SPV_VALVE_mixed_float_dot_product";
    // HLSL Change - SPV_KHR_opacity_micromap.
    case Extension::KHR_opacity_micromap:
      return "SPV_KHR_opacity_micromap";
    // HLSL Change - SPV_NV_cluster_acceleration_structure.
    case Extension::NV_cluster_acceleration_structure:
      return "SPV_NV_cluster_acceleration_structure";
    // HLSL Change - SPV_NV_linear_swept_spheres.
    case Extension::NV_linear_swept_spheres:
      return "SPV_NV_linear_swept_spheres";
    // HLSL Change - SPV_QCOM_image_processing3.
    case Extension::QCOM_image_processing3:
      return "SPV_QCOM_image_processing3";
    // HLSL Change - SPV_KHR_constant_data.
    case Extension::KHR_constant_data:
      return "SPV_KHR_constant_data";
      // HLSL Change - SPV_KHR_abort.
      case Extension::KHR_abort:
        return "SPV_KHR_abort";
      // HLSL Change - SPV_ARM_cooperative_matrix_layouts.
      case Extension::ARM_cooperative_matrix_layouts:
        return "SPV_ARM_cooperative_matrix_layouts";
      default:
    break;
  }
  return "<unknown extension>";
}

bool FeatureManager::isKHRExtension(llvm::StringRef name) const {
  return name.startswith_lower("spv_khr_");
}

std::string FeatureManager::getKnownExtensions(const char *delimiter,
                                               const char *prefix,
                                               const char *postfix) {
  std::ostringstream oss;

  oss << prefix;

  const auto numExtensions = static_cast<uint32_t>(Extension::Unknown);
  for (uint32_t i = 0; i < numExtensions; ++i) {
    oss << getExtensionName(static_cast<Extension>(i));
    if (i + 1 < numExtensions)
      oss << delimiter;
  }

  oss << postfix;

  return oss.str();
}

bool FeatureManager::isExtensionRequiredForTargetEnv(Extension ext) const {
  bool required = true;
  if (targetEnv >= SPV_ENV_VULKAN_1_3) {
    // The following extensions are incorporated into Vulkan 1.3 or above, and
    // are therefore not required to be emitted for that target environment.
    switch (ext) {
    case Extension::KHR_non_semantic_info:
      required = false;
      break;
    default:
      break;
    }
  }
  if (required && targetEnv >= SPV_ENV_VULKAN_1_1) {
    // The following extensions are incorporated into Vulkan 1.1 or above, and
    // are therefore not required to be emitted for that target environment.
    // TODO: Also add the following extensions  if we start to support them.
    // * SPV_KHR_storage_buffer_storage_class
    // * SPV_KHR_variable_pointers
    switch (ext) {
    case Extension::KHR_16bit_storage:
    case Extension::KHR_device_group:
    case Extension::KHR_multiview:
    case Extension::KHR_shader_draw_parameters:
      required = false;
      break;
    default:
      // Only 1.1 or above extensions can be suppressed.
      break;
    }
  }

  return required;
}

bool FeatureManager::isExtensionEnabled(Extension ext) const {
  bool allowed = false;
  if (ext != Extension::Unknown &&
      allowedExtensions.test(static_cast<unsigned>(ext)))
    allowed = true;
  return allowed;
}

Extension FeatureManager::getAccelerationStructureProvider() const {
  for (Extension ext : {Extension::KHR_ray_query, Extension::KHR_ray_tracing,
                        Extension::NV_ray_tracing})
    if (isExtensionEnabled(ext))
      return ext;
  return Extension::Unknown;
}

bool FeatureManager::hasExplicitAccelerationStructureProvider() const {
  return hasExplicitExtensions &&
         getAccelerationStructureProvider() != Extension::Unknown;
}

// HLSL Change Begin - SPV_EXT_shader_subgroup_partitioned.
Extension FeatureManager::getShaderSubgroupPartitionedProvider() const {
  // SPV_EXT_shader_subgroup_partitioned and SPV_NV_shader_subgroup_partitioned
  // are two names for the same capability (5297), so a module declares at most
  // one of them. The standardised EXT spelling is checked first: with the
  // default extension set only NV is enabled, and with an explicit
  // -fspv-extension list the user's choice decides.
  for (Extension ext : {Extension::EXT_shader_subgroup_partitioned,
                        Extension::NV_shader_subgroup_partitioned})
    if (isExtensionEnabled(ext))
      return ext;
  return Extension::Unknown;
}
// HLSL Change End - SPV_EXT_shader_subgroup_partitioned.

bool FeatureManager::enabledByDefault(Extension ext) {
  switch (ext) {
    // KHR_ray_tracing and NV_ray_tracing are mutually exclusive so enable only
    // KHR extension by default
  case Extension::NV_ray_tracing:
    return false;
    // KHR_compute_shader_derivatives and NV_compute_shader_derivatives are
    // mutually exclusive so enable only KHR extension by default
  case Extension::NV_compute_shader_derivatives:
    return false;
    // Enabling EXT_demote_to_helper_invocation changes the code generation
    // behavior for the 'discard' statement. Therefore we will only enable it if
    // the user explicitly asks for it.
  case Extension::EXT_demote_to_helper_invocation:
    return false;
  case Extension::EXT_mesh_shader:
    // Enabling EXT_mesh_shader only when the target environment is SPIR-V 1.4
    // or above
    return isTargetEnvSpirv1p4OrAbove();
  // HLSL Change - SPV_KHR_fma. Enabling it changes the code generation for
  // the HLSL fused multiply-add intrinsics (the GLSL.std.450 Fma extended
  // instruction becomes the OpFmaKHR core instruction), and modules using
  // OpFmaKHR are rejected by drivers without VK_KHR_shader_fma. Therefore it
  // is only enabled when the user explicitly asks for it.
    case Extension::KHR_fma:
      return false;
    // HLSL Change - SPV_EXT_split_barrier. Split barriers are a new construct
    // (vk::SplitBarrierArrive/vk::SplitBarrierWait) rather than a replacement
    // for existing codegen, but modules using them declare the SplitBarrierEXT
    // capability and the SPV_EXT_split_barrier extension, which a driver
    // without VK_EXT_shader_split_barrier rejects. Enabling them is therefore
    // opt-in: without -fspv-extension=SPV_EXT_split_barrier the header's
    // entry points are rejected with a diagnostic instead of silently
    // lowering to OpControlBarrier.
    case Extension::EXT_split_barrier:
      return false;
    // HLSL Change - SPV_EXT_shader_subgroup_partitioned. Only one of the two
    // spellings of the partitioned wave operations may be declared, and DXC
    // has always emitted SPV_NV_shader_subgroup_partitioned, so the NV
    // spelling stays the default and the standardised EXT spelling has to be
    // requested with -fspv-extension=SPV_EXT_shader_subgroup_partitioned.
    // This keeps the default output of every existing shader unchanged
    // (docs/SPIR-V.rst, "Shader Model 6.0+ Wave Intrinsics").
    case Extension::EXT_shader_subgroup_partitioned:
        return false;
      // HLSL Change - SPV_QCOM_multiple_wait_queues. The annotation
      // ([[vk::multiple_wait_queues]]) is new syntax, so no existing shader can
      // start using it by accident, but a module that carries the
      // MultipleWaitQueuesQCOM capability and the
      // SPV_QCOM_multiple_wait_queues extension is rejected by a driver without
      // VK_QCOM_shader_multiple_wait_queues. Registration is therefore opt-in:
      // without -fspv-extension=SPV_QCOM_multiple_wait_queues the annotation is
      // rejected with a diagnostic rather than silently dropped, and the
      // capability is only ever emitted together with the extension.
      case Extension::QCOM_multiple_wait_queues:
      return false;
    // HLSL Change - SPV_NV_push_constant_bank. Opt-in for the same reason: the
    // BankNV / MemberOffsetNV decorations change the descriptor contract with
    // the host (the shader no longer reads bank 0 at offset 0), and a module
    // that carries the PushConstantBanksNV capability is rejected by a driver
    // without VK_NV_push_constant_bank. Without
    // -fspv-extension=SPV_NV_push_constant_bank the two attributes are
    // rejected with a diagnostic instead of silently dropped, and the
    // capability is only ever emitted together with the extension.
    case Extension::NV_push_constant_bank:
      return false;
    // HLSL Change - SPV_VALVE_mixed_float_dot_product. Enabling it changes the
    // code generation for the HLSL dot2add intrinsic (the unfused
    // OpFMul/OpFConvert/OpFAdd sequence becomes OpFDot2MixAcc32VALVE), and a
    // module using that instruction declares the
    // DotProductFloat16AccFloat32VALVE capability, which only drivers exposing
    // the vendor-specific VK_VALVE_shader_mixed_float_dot_product device
    // extension accept. Enabling it is therefore opt-in: without
    // -fspv-extension=SPV_VALVE_mixed_float_dot_product the pre-existing
    // lowering is kept byte for byte.
    case Extension::VALVE_mixed_float_dot_product:
      return false;
    // HLSL Change - SPV_KHR_opacity_micromap. The extension exists to carry the
    // OpacityMicromapIdKHR execution mode, whose operand is a specialization
    // constant the host sets to true to make ray query traversal evaluate
    // opacity micromaps. Enabling it changes the module interface (a new
    // specialization constant) and the emitted module declares
    // RayTracingOpacityMicromapExecutionModeKHR plus
    // OpExtension "SPV_KHR_opacity_micromap", which a driver without
    // VK_KHR_opacity_micromap rejects. It is therefore opt-in: without
    // -fspv-extension=SPV_KHR_opacity_micromap the HLSL opacity-micromap ray
    // flags keep their pre-existing, flag-only code generation.
    case Extension::KHR_opacity_micromap:
      return false;
    // HLSL Change - SPV_NV_cluster_acceleration_structure. A module that reads
    // the cluster ID of an intersection declares the
    // RayTracingClusterAccelerationStructureNV capability and
    // OpExtension "SPV_NV_cluster_acceleration_structure", which a driver
    // without VK_NV_cluster_acceleration_structure rejects. The extension
    // is therefore opt-in: without
    // -fspv-extension=SPV_NV_cluster_acceleration_structure the accessors
    // in <vk/nv/cluster_as.h> are compile errors (see the
    // OpRayQueryGetIntersectionClusterIdNV case in CapabilityVisitor)
    // instead of a module that declares an extension the host never asked
    // for, and a module that does not read a cluster ID is unchanged.
    case Extension::NV_cluster_acceleration_structure:
      return false;
    // HLSL Change - SPV_NV_linear_swept_spheres. A module that reads the
    // sphere (or linear-swept-sphere) parameters of an intersection declares
    // RayTracingSpheresGeometryNV (or RayTracingLinearSweptSpheresGeometryNV)
    // and OpExtension "SPV_NV_linear_swept_spheres", which a driver without
    // VK_NV_ray_tracing_linear_swept_spheres rejects. The extension is
    // therefore opt-in: without
    // -fspv-extension=SPV_NV_linear_swept_spheres the accessors in
    // <vk/nv/linear_swept_spheres.h> are compile errors (see the
    // OpRayQuery*Sphere*NV / OpRayQuery*LSS*NV cases in CapabilityVisitor)
    // instead of a module that declares an extension the host never asked
    // for, and a module that does not touch sphere geometry is unchanged.
    case Extension::NV_linear_swept_spheres:
      return false;
    // HLSL Change - SPV_QCOM_image_processing3. A module that gathers with one of
    // the modes in <vk/qcom/image_processing3.h> declares the
    // ImageGatherLinearQCOM or the ImageGatherExtendedModesQCOM capability and
    // OpExtension "SPV_QCOM_image_processing3", which a driver without
    // VK_QCOM_image_processing3 rejects. The extension is therefore opt-in:
    // without -fspv-extension=SPV_QCOM_image_processing3 every gather call is a
    // compile error (see the OpImageGatherQCOM case in CapabilityVisitor)
    // instead of a module that declares an extension the host never asked for,
    // and a shader that does not gather with one of the modes - including one
    // that includes the header - is unchanged.
    case Extension::QCOM_image_processing3:
      return false;
    // HLSL Change - SPV_KHR_constant_data. OpConstantDataKHR is only
    // emitted when -fspv-constant-data asks for it, it changes the encoding
    // of existing array constants, and a driver or offline tool that does
    // not know SPV_KHR_constant_data rejects the module, so the extension
    // is opt-in: without -fspv-extension=SPV_KHR_constant_data the
    // instruction is a compile error instead of an implicit request.
    case Extension::KHR_constant_data:
      return false;
    // HLSL Change - SPV_KHR_abort. A module that aborts declares the AbortKHR
    // capability and the SPV_KHR_abort extension, and an abort is not a
    // recovery point: VK_KHR_shader_abort requires the host to enable
    // VkPhysicalDeviceShaderAbortFeaturesKHR::shaderAbort and makes the abort
    // lose the device. Emitting one implicitly would therefore turn a shader
    // that "just reports something" into a device loss on a host that never
    // opted in. The extension is opt-in: without
    // -fspv-extension=SPV_KHR_abort every vk::Abort call is a compile error
    // (SpirvEmitter::processAbortKHR) and a shader that only includes the
    // header is unchanged.
      case Extension::KHR_abort:
        return false;
      // HLSL Change - SPV_ARM_cooperative_matrix_layouts. Deliberately *not*
      // opt-in. Naming one of the Arm layouts is an explicit, unconditional
      // request written in the HLSL source - there is no run-time flag and no
      // alternative lowering that could silently replace it - so making the
      // extension refusable would only turn
      // CooperativeMatrix::LoadBlockedInterleaved<RowBlockedInterleavedARM, N>
      // into a compile error with no way to accept it other than an extra
      // command-line flag. No existing code generation changes either: the
      // RowMajorKHR (0) and ColumnMajorKHR (1) paths never declare the
      // capability or the extension, because CapabilityVisitor only does so when
      // the MemoryLayout operand is one of the two Arm enumerants. Registration
      // still buys three things:
      // -fspv-extension=SPV_ARM_cooperative_matrix_layouts is accepted instead of
      // being reported as an unknown extension, the extension is listed by the
      // -fspv-extension= diagnostics, and it is emitted through the same
      // addExtension() path as every other extension, so it is cross-checked
      // against the target environment and cannot be emitted without its
      // capability.
      case Extension::ARM_cooperative_matrix_layouts:
        return true;
      default:
    return true;
  }
}

bool FeatureManager::isTargetEnvVulkan1p1OrAbove() const {
  return targetEnv >= SPV_ENV_VULKAN_1_1;
}

bool FeatureManager::isTargetEnvSpirv1p4OrAbove() const {
  return targetEnv >= SPV_ENV_UNIVERSAL_1_4;
}

bool FeatureManager::isTargetEnvVulkan1p1Spirv1p4OrAbove() const {
  return targetEnv >= SPV_ENV_VULKAN_1_1_SPIRV_1_4;
}

bool FeatureManager::isTargetEnvVulkan1p2OrAbove() const {
  return targetEnv >= SPV_ENV_VULKAN_1_2;
}

bool FeatureManager::isTargetEnvVulkan1p3OrAbove() const {
  return targetEnv >= SPV_ENV_VULKAN_1_3;
}

bool FeatureManager::isTargetEnvVulkan() const {
  // This assert ensure that this list will be updated, if necessary, when
  // a new target environment is added.
  static_assert(SPV_ENV_VULKAN_1_4 + 1 == SPV_ENV_MAX);

  switch (targetEnv) {
  case SPV_ENV_VULKAN_1_0:
  case SPV_ENV_VULKAN_1_1:
  case SPV_ENV_VULKAN_1_2:
  case SPV_ENV_VULKAN_1_1_SPIRV_1_4:
  case SPV_ENV_VULKAN_1_3:
  case SPV_ENV_VULKAN_1_4:
    return true;
  default:
    return false;
  }
}

} // end namespace spirv
} // end namespace clang
