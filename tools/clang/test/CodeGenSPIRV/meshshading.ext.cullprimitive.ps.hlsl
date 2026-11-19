// RUN: %dxc -T ps_6_5 -E main %s -spirv -DCULL_TYPE=bool | FileCheck %s
// RUN: %dxc -T ps_6_5 -E main %s -spirv -DCULL_TYPE=uint | FileCheck %s
// RUN: %dxc -T ps_6_5 -E main %s -spirv -DCULL_TYPE=bool2 | FileCheck %s
// RUN: %dxc -T ps_6_5 -E main %s -spirv -fspv-target-env=vulkan1.3 -DCULL_ARRAY | FileCheck %s
// RUN: %dxc -T ps_6_5 -E main %s -spirv -fcgl -DCULL_TYPE=bool | FileCheck %s --check-prefix=BOOL
// RUN: %dxc -T ps_6_5 -E main %s -spirv -fcgl -DCULL_TYPE=uint | FileCheck %s --check-prefix=UINT
// RUN: %dxc -T ps_6_5 -E main %s -spirv -fcgl -DCULL_TYPE=bool2 | FileCheck %s --check-prefix=BOOL2
// RUN: %dxc -T ps_6_5 -E main %s -spirv -fcgl -fspv-target-env=vulkan1.3 -DCULL_ARRAY | FileCheck %s --check-prefix=ARRAY
// RUN: %dxc -T ps_6_5 -E main %s -spirv -fcgl -DCULL_BUILTIN | FileCheck %s --check-prefix=BUILTIN

// SV_CullPrimitive as a pixel shader input is replaced with 0, mirroring DXIL.
// Mapping it to the CullPrimitiveEXT builtin requires MeshShadingEXT and is
// not allowed in a fragment shader (VUID 07034), so the generated SPIR-V used
// to be invalid.  DXIL does not look at the type here, so aggregates are
// replaced as well.
//
// CHECK-NOT: CullPrimitiveEXT
// CHECK: OpEntryPoint Fragment
// CHECK-NOT: CullPrimitiveEXT
//
// BOOL: [[null:%[0-9]+]] = OpConstantNull %bool
// BOOL: OpStore %param_var_cull [[null]]
//
// UINT: [[null:%[0-9]+]] = OpConstantNull %uint
// UINT: OpStore %param_var_cull [[null]]
//
// BOOL2: [[null:%[0-9]+]] = OpConstantNull %v2bool
// BOOL2: OpStore %param_var_cull [[null]]
//
// ARRAY: [[null:%[0-9]+]] = OpConstantNull %_arr_bool_uint_2
// ARRAY: OpStore %param_var_cull [[null]]
//
// An explicit vk::builtin still takes precedence over the replacement.
// BUILTIN-NOT: OpConstantNull %bool
// BUILTIN: OpLoad %bool %HelperInvocation

#ifdef CULL_ARRAY
float4 main(bool cull[2] : SV_CullPrimitive) : SV_Target { return cull[1]; }
#elif defined(CULL_BUILTIN)
float4 main([[vk::builtin("HelperInvocation")]] bool cull : SV_CullPrimitive)
    : SV_Target {
  return cull;
}
#else
float4 main(CULL_TYPE cull : SV_CullPrimitive) : SV_Target { return cull.x; }
#endif
