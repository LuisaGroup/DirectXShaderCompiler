#define _INF_f (1.#INF)
SamplerState samplers[16]:register(s0,space1);
#define _GETSMP(idx) samplers[NonUniformResourceIndex(idx)]
template<typename T>
T _acosh(T v){return log(v+sqrt(v*v-1.0));}
template<typename T>
T _asinh(T v){return log(v+sqrt(v*v+1.0));}
template<typename T>
T _atanh(T v){return 0.5*log((1.0+v)/(1.0-v));}
template<typename T>
T _exp10(T v){return pow(10,v);};
template<typename T>
float _length_sqr(T x){return dot(x,x);}
template<typename T>
T _fma(T a,T b,T c){return a*b+c;}
float2x2 _float2x2(float3x4 v){return float2x2(v[0].xy,v[1].xy);}
float2x2 _float2x2(float4x4 v){return float2x2(v[0].xy,v[1].xy);}
float3x4 _float3x3(float2x2 v){return float3x4(v[0],0,0,v[1],0,0,0,0,0,0);}
float3x4 _float3x3(float4x4 v){return float3x4(v[0].xyz,0,v[1].xyz,0,v[2].xyz,0);}
float4x4 _float4x4(float2x2 v){return float4x4(v[0],0,0,v[1].xy,0,0,0,0,0,0,0,0,0,0);};
float4x4 _float4x4(float3x4 v){return float4x4(v[0].xyz,0,v[1].xyz,0,v[2].xyz,0,0,0,0,0);}
float2x2 _float2x2(float m00,float m01,float m10,float m11){return float2x2(m00,m01,m10,m11);}
float3x4 _float3x3(float m00,float m01,float m02,float m10,float m11,float m12,float m20,float m21,float m22){return float3x4(m00,m01,m02,0,m10,m11,m12,0,m20,m21,m22,0);}
float4x4 _float4x4(float m00,float m01,float m02,float m03,float m10,float m11,float m12,float m13,float m20,float m21,float m22,float m23,float m30,float m31,float m32,float m33){return float4x4(m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33);}
float2x2 _float2x2(float2 c0,float2 c1){return float2x2(c0,c1);}
float3x4 _float3x3(float3 c0,float3 c1,float3 c2){return float3x4(float4(c0,0),float4(c1,0),float4(c2,0));}
float4x4 _float4x4(float4 c0,float4 c1,float4 c2,float4 c3){return float4x4(c0,c1,c2,c3);}
float2x2 _transpose(float2x2 m){return transpose(m);}
float3x4 _transpose(float3x4 m){
float4x3 mm=transpose(m);
return _float3x3(mm[0],mm[1],mm[2]);
}
float4x4 _transpose(float4x4 m){return transpose(m);}
float4x4 _Mul(float4x4 a,float4x4 b){return mul(b,a);}
float3x4 _Mul(float3x4 a,float3x4 b){return mul(b,float4x4(a,0,0,0,0));}
float2x2 _Mul(float2x2 a,float2x2 b){return mul(b,a);}
float4 _Mul(float4x4 b,float4 a){return mul(a,b);}
float3 _Mul(float3x4 b,float3 a){return mul(a,b).xyz;}
float2 _Mul(float2x2 b,float2 a){return mul(a,b);}
float16_t4 _Mul(float16_t4x4 b,float16_t4 a){return mul(a,b);}
float16_t3 _Mul(float16_t3x4 b,float16_t3 a){return mul(a,b).xyz;}
float16_t2 _Mul(float16_t2x2 b,float16_t2 a){return mul(a,b);}
#ifdef LUISA_DEBUG_INFO
	#define _bfreadMat(bf,idx,vid) (((idx) < _Global[0]._validate_##vid) ? bf[idx].m : (bf[0].m * 0) - 1)
	#define _bfwriteMat(bf,idx,value,vid) { if ((idx) < _Global[0]._validate_##vid) { bf[idx].m = value; } }
	// Volatile and byte-buffer matrix macros use template functions below (unchanged for debug)
#else
	#define _bfreadMat(bf,idx) bf[idx].m
	#define _bfwriteMat(bf,idx,value) bf[idx].m=value
#endif
template<typename T,typename BufferType>
T _volatile_bfreadMat(BufferType b,uint idx){
DeviceMemoryBarrier();
return b[idx].m;
}
template<typename BufferElem,typename T,typename BufferType>
T _volatile_bytebfreadMat(BufferType b,uint idx){
DeviceMemoryBarrier();
return b.template Load<BufferElem>(idx).m;
}
#define _volatile_bfwriteMat(bf,idx,value) {bf[idx].m=value; DeviceMemoryBarrier();}
#define _bytebfreadMat(bf,type,idx) bf.template Load<type>(idx).m
#define _bytebfwriteMat(bf,type,idx,value) {type _tempm;_tempm.m=value;bf.template Store<type>(idx,_tempm);}
#define _volatile_bytebfwriteMat(bf,type,idx,value) {type _tempm;_tempm.m=value;bf.template Store<type>(idx,_tempm);DeviceMemoryBarrier();}
struct _wfloat3 {float3 v; float a;};
struct _wfloat16_t3 {float16_t3 v; float16_t a;};
struct _wfloat64_t3 {float64_t3 v; float64_t a;};
struct _wuint3 {uint3 v; uint a;};
struct _wuint16_t3 {uint16_t3 v; uint16_t a;};
struct _wuint64_t3 {uint64_t3 v; uint64_t a;};
struct _wint3 {int3 v; int a;};
struct _wint16_t3 {int16_t3 v; int16_t a;};
struct _wint64_t3 {int64_t3 v; int64_t a;};
struct _WrappedFloat2x2 {float2x2 m;};
struct _WrappedFloat3x3 {
float3x4 m;
};
struct _WrappedFloat4x4 {
float4x4 m;
};
#ifdef LUISA_DEBUG_INFO
// Debug: range-checked buffer read/write macros with validate index
#define _bfread(bf,idx,vid) \
    (((idx) < _Global[0]._validate_##vid) ? bf[idx] : (bf[0] * 0) - 1)
#define _bfreadVec3(bf,idx,vid) \
    (((idx) < _Global[0]._validate_##vid) ? bf[idx].xyz : (bf[0].xyz * 0) - 1)
#define _bfwrite(bf,idx,value,vid) \
    { if ((idx) < _Global[0]._validate_##vid) { bf[idx] = value; } }
#define _bfwriteVec3(bf,idx,value,type,vid) \
    { if ((idx) < _Global[0]._validate_##vid) { bf[idx] = type##4(value, 0); } }
#else
#define _bfread(bf,idx) bf[idx]
#define _bfreadVec3(bf,idx) bf[idx].xyz
#define _bfwrite(bf,idx,value) bf[idx]=value
#define _bfwriteVec3(bf,idx,value,type) bf[idx]=type##4(value,0)
#endif
template<typename T,typename BufferType>
T _volatile_bfread(BufferType b,uint idx){
DeviceMemoryBarrier();
return b[idx];
}
template<typename T,typename BufferType>
T _volatile_bfreadVec3(BufferType b,uint idx){
DeviceMemoryBarrier();
return b[idx].xyz;
}

template<typename T,typename BufferType>
T _volatile_bytebfread(BufferType b,uint idx){
DeviceMemoryBarrier();
return b.template Load<T>(idx);
}
template<typename BufferElem,typename T,typename BufferType>
T _volatile_bytebfreadVec3(BufferType b,uint idx){
DeviceMemoryBarrier();
return b.template Load<BufferElem>(idx).xyz;
}

#define _volatile_bfwrite(bf,idx,value) {bf[idx]=value; DeviceMemoryBarrier();}
#define _volatile_bfwriteVec3(bf,idx,value,type) {bf[idx]=type##4(value,0); DeviceMemoryBarrier();}
#ifdef LUISA_DEBUG_INFO
#define _bytebfread(bf,type,idx,vid) \
    (((idx) < _Global[0]._validate_##vid) ? bf.template Load<type>(idx) : (bf.template Load<type>(0) * 0) - 1)
#define _bytebfreadVec3(bf,type,idx,vid) \
    (((idx) < _Global[0]._validate_##vid) ? bf.template Load<type##4>(idx).xyz : (bf.template Load<type##4>(0).xyz * 0) - 1)
#define _bytebfwrite(bf,idx,value,vid) \
    { if ((idx) < _Global[0]._validate_##vid) { bf.Store(idx, value); } }
#define _bytebfwriteVec3(bf,type,idx,value,vid) \
    { if ((idx) < _Global[0]._validate_##vid) { bf.template Store<type##4>(idx, type##4(value, 0)); } }
#define _volatile_bytebfwrite(bf,idx,value,vid) \
    { if ((idx) < _Global[0]._validate_##vid) { bf.Store(idx, value); DeviceMemoryBarrier(); } }
#define _volatile_bytebfwriteVec3(bf,type,idx,value,vid) \
    { if ((idx) < _Global[0]._validate_##vid) { bf.template Store<type##4>(idx, type##4(value, 0)); DeviceMemoryBarrier(); } }
#else
#define _bytebfread(bf,type,idx) bf.template Load<type>(idx)
#define _bytebfreadVec3(bf,type,idx) bf.template Load<type##4>(idx).xyz
#define _bytebfwrite(bf,idx,value) bf.Store(idx,value)
#define _bytebfwriteVec3(bf,type,idx,value) bf.template Store<type##4>(idx,type##4(value,0))
#define _volatile_bytebfwrite(bf,idx,value) {bf.Store(idx,value); DeviceMemoryBarrier();}
#define _volatile_bytebfwriteVec3(bf,type,idx,value) {bf.template Store<type##4>(idx,type##4(value,0)); DeviceMemoryBarrier();}
#endif
#define _Readtx(tex,uv) tex[uv]
#define _Writetx(tex,uv,value) tex[uv]=value
#define _Smptx(tex,uv,filter,address) (tex.SampleLevel(_GETSMP((address)*4+(filter)),(uv),0))
#define _SmptxPixel(tex,uv,filter,address) (tex.Sample(_GETSMP((address)*4+(filter)),(uv)))
#define _SmptxLevel(tex,uv,level,filter,address) (tex.SampleLevel(_GETSMP((address)*4+(filter)),uv,level))
#define _SmptxGrad(tex,uv,dx,dy,filter,address) (tex.SampleGrad(_GETSMP((address)*4+(filter)),uv,dx,dy))
#define _SmptxGrad2DLevel(tex,uv,dx,dy,minMip,filter,address) (tex.SampleGrad(_GETSMP((address)*4+(filter)),uv,dx,dy,int2(0),minMip))
#define _SmptxGrad3DLevel(tex,uv,dx,dy,minMip,filter,address) (tex.SampleGrad(_GETSMP((address)*4+(filter)),uv,dx,dy,int3(0),minMip))
#define _clz(T,arg,size) (((T)size)-firstbithigh(arg))
template<typename T>
T _round(T x){return sign(x)*floor(abs(x)+(T)0.5);}
template<typename T>
T _atan2(T y,T x){return (x==T(0)&&y==T(0))?T(0):atan2(y,x);}
template<typename T>
T _ctz(T x){return x==T(0)?T(32):firstbitlow(x);}
template<typename T>
T _fract(T x){return x-floor(x);}
struct _Hit0{uint v0;uint v1;float2 v2;uint v3;float v4;};
struct _Hit1{uint v0;uint v1;float2 v2;float v3;uint _a0;};
struct _Hit2{uint v0;uint v1;};
struct _MeshInst {
float4 p0;
float4 p1;
float4 p2;
uint InstanceID:24;
uint InstanceMask:8;
uint InstanceContributionToHitGroupIndex:24;
uint Flags:8;
uint2 accelStructPtr;
};
float2x2 _outer_product(float2 a,float2 b){return float2x2(a*b.x,a*b.y);}
float3x4 _outer_product(float3 a,float3 b){return float3x4(float4(a*b.x,0),float4(a*b.y,0),float4(a*b.z,0));}
float4x4 _outer_product(float4 a,float4 b){return float4x4(a*b.x,a*b.y,a*b.z,a*b.w);}
float2x2 _mat_comp_mul(float2x2 a,float2x2 b){return float2x2(a[0]*b[0],a[1]*b[1]);}
float3x4 _mat_comp_mul(float3x4 a,float3x4 b){return float3x4(float4(a[0].xyz*b[0].xyz,0),float4(a[1].xyz*b[1].xyz,0),float4(a[2].xyz*b[2].xyz,0));}
float4x4 _mat_comp_mul(float4x4 a,float4x4 b){return float4x4(a[0]*b[0],a[1]*b[1],a[2]*b[2],a[3]*b[3]);}
bool2 to_bool2(int v){return bool2((v&255)!=0,((v>>8)&255)!=0);}
bool3 to_bool3(int v){return bool3((v&255)!=0,((v>>8)&255)!=0,((v>>16)&255)!=0);}
bool4 to_bool4(int v){return bool4((v&255)!=0,((v>>8)&255)!=0,((v>>16)&255)!=0,((v>>24)&255)!=0);}
int to_Alsbool2(bool2 v){return (v.x?1:0)|(v.y?256:0);}
int to_Alsbool3(bool3 v){return (v.x?1:0)|(v.y?256:0)|(v.z?65536:0);}
int to_Alsbool4(bool4 v){return (v.x?1:0)|(v.y?256:0)|(v.z?65536:0)|(v.w?16777216:0);}
template<typename Src,typename Dst>
Dst Vec2AsInt(Src v){return (((Dst)v.y)<<((Dst)16))|v.x;}
template<typename Src,typename Dst>
Dst IntAsVec2(Src v){
Dst d;
d.x=v&((Src)65535);
d.y=(v>>((Src)16))&((Src)65535);
return d;
}
template<typename Dst>
Dst Bool4AsInt(bool4 v){
int4 d=select(v,int4(1,256,65536,16777216),int4(0,0,0,0));
return ((Dst)d.x)|((Dst)d.y)|((Dst)d.z)|((Dst)d.w);
}
template<typename Src>
bool4 IntAsBool4(Src v){
bool4 d;
d.x=(v&((Src)255))!=0;
d.y=((v>>((Src)8))&((Src)255))!=0;
d.z=((v>>((Src)16))&((Src)255))!=0;
d.w=((v>>((Src)24))&((Src)255))!=0;
return d;
}
#define _zero(type) ((type)0)
#define _one(type) ((type)1)
// Header for linear algebra APIs.

#if __spirv__
// SPIR-V path: use cooperative vector extension
// Deep-copied from D:\DirectXShaderCompiler\tools\clang\lib\Headers\hlsl\vk to avoid relying on DXC include paths.
// ----- begin vk/spirv.h -----
// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef _HLSL_VK_SPIRV_H_
#define _HLSL_VK_SPIRV_H_

namespace vk {

enum CooperativeMatrixUse {
  CooperativeMatrixUseMatrixAKHR = 0,
  CooperativeMatrixUseMatrixBKHR = 1,
  CooperativeMatrixUseMatrixAccumulatorKHR = 2,
  CooperativeMatrixUseMax = 0x7fffffff,
};

enum CooperativeMatrixLayout {
  CooperativeMatrixLayoutRowMajorKHR = 0,
  CooperativeMatrixLayoutColumnMajorKHR = 1,
  CooperativeMatrixLayoutRowBlockedInterleavedARM = 4202,
  CooperativeMatrixLayoutColumnBlockedInterleavedARM = 4203,
  CooperativeMatrixLayoutMax = 0x7fffffff,
};

enum CooperativeMatrixOperandsMask {
  CooperativeMatrixOperandsMaskNone = 0,
  CooperativeMatrixOperandsMatrixASignedComponentsKHRMask = 0x00000001,
  CooperativeMatrixOperandsMatrixBSignedComponentsKHRMask = 0x00000002,
  CooperativeMatrixOperandsMatrixCSignedComponentsKHRMask = 0x00000004,
  CooperativeMatrixOperandsMatrixResultSignedComponentsKHRMask = 0x00000008,
  CooperativeMatrixOperandsSaturatingAccumulationKHRMask = 0x00000010,
};

// Cooperative Vector Matrix Layout (SPV_NV_cooperative_vector)
enum CooperativeVectorMatrixLayout {
  CooperativeVectorMatrixLayoutRowMajorNV = 0,
  CooperativeVectorMatrixLayoutColumnMajorNV = 1,
  CooperativeVectorMatrixLayoutInferencingOptimalNV = 2,
  CooperativeVectorMatrixLayoutTrainingOptimalNV = 3,
  CooperativeVectorMatrixLayoutMax = 0x7fffffff,
};

// Component type interpretations (matches VkComponentTypeKHR / gl_ComponentType*)
enum CooperativeVectorComponentType {
  CooperativeVectorComponentTypeFloat16NV = 0,
  CooperativeVectorComponentTypeFloat32NV = 1,
  CooperativeVectorComponentTypeFloat64NV = 2,
  CooperativeVectorComponentTypeSignedInt8NV = 3,
  CooperativeVectorComponentTypeSignedInt16NV = 4,
  CooperativeVectorComponentTypeSignedInt32NV = 5,
  CooperativeVectorComponentTypeSignedInt64NV = 6,
  CooperativeVectorComponentTypeUnsignedInt8NV = 7,
  CooperativeVectorComponentTypeUnsignedInt16NV = 8,
  CooperativeVectorComponentTypeUnsignedInt32NV = 9,
  CooperativeVectorComponentTypeUnsignedInt64NV = 10,
  CooperativeVectorComponentTypeSignedInt8PackedNV = 1000491000,
  CooperativeVectorComponentTypeUnsignedInt8PackedNV = 1000491001,
  CooperativeVectorComponentTypeFloatE4M3NV = 1000491002,
  CooperativeVectorComponentTypeFloatE5M2NV = 1000491003,
};

enum MemoryAccessMask {
  MemoryAccessMaskNone = 0,
  MemoryAccessVolatileMask = 0x00000001,
  MemoryAccessAlignedMask = 0x00000002,
  MemoryAccessNontemporalMask = 0x00000004,
  MemoryAccessMakePointerAvailableMask = 0x00000008,
  MemoryAccessMakePointerAvailableKHRMask = 0x00000008,
  MemoryAccessMakePointerVisibleMask = 0x00000010,
  MemoryAccessMakePointerVisibleKHRMask = 0x00000010,
  MemoryAccessNonPrivatePointerMask = 0x00000020,
  MemoryAccessNonPrivatePointerKHRMask = 0x00000020,
  MemoryAccessAliasScopeINTELMaskMask = 0x00010000,
  MemoryAccessNoAliasINTELMaskMask = 0x00020000,
};

enum Scope {
  ScopeCrossDevice = 0,
  ScopeDevice = 1,
  ScopeWorkgroup = 2,
  ScopeSubgroup = 3,
  ScopeInvocation = 4,
  ScopeQueueFamily = 5,
  ScopeQueueFamilyKHR = 5,
  ScopeShaderCallKHR = 6,
  ScopeMax = 0x7fffffff,
};

enum StorageClass {
  StorageClassWorkgroup = 4,
};

// An opaque type to represent a Spir-V pointer to the workgroup storage class.
// clang-format off
template <typename PointeeType>
using WorkgroupSpirvPointer = const vk::SpirvOpaqueType<
    /* OpTypePointer */ 32,
    vk::Literal<vk::integral_constant<uint, StorageClassWorkgroup> >,
    PointeeType>;
// clang-format on

// Returns an opaque Spir-V pointer to v. The memory object v's storage class
// modifier must be groupshared. If the incorrect storage class is used, then
// there will be a validation error, and it will not show the correct
template <typename T>
[[vk::ext_instruction(/* OpCopyObject */ 83)]] WorkgroupSpirvPointer<T>
GetGroupSharedAddress([[vk::ext_reference]] T v);

} // namespace vk

#endif // _HLSL_VK_SPIRV_H_
// ----- end vk/spirv.h -----

// ----- begin vk/opcode_selector.h -----
// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef _HLSL_VK_KHR_OPCODE_SELECTOR_H_
#define _HLSL_VK_KHR_OPCODE_SELECTOR_H_

#define DECLARE_UNARY_OP(name, opcode)                                         \
  template <typename ResultType>                                               \
  [[vk::ext_instruction(opcode)]] ResultType __builtin_spv_##name(             \
      ResultType a)

DECLARE_UNARY_OP(CopyObject, 83);
DECLARE_UNARY_OP(SNegate, 126);
DECLARE_UNARY_OP(FNegate, 127);

#define DECLARE_CONVERSION_OP(name, opcode)                                    \
  template <typename ResultType, typename OperandType>                         \
  [[vk::ext_instruction(opcode)]] ResultType __builtin_spv_##name(             \
      OperandType a)

DECLARE_CONVERSION_OP(ConvertFtoU, 109);
DECLARE_CONVERSION_OP(ConvertFtoS, 110);
DECLARE_CONVERSION_OP(ConvertSToF, 111);
DECLARE_CONVERSION_OP(ConvertUToF, 112);
DECLARE_CONVERSION_OP(UConvert, 113);
DECLARE_CONVERSION_OP(SConvert, 114);
DECLARE_CONVERSION_OP(FConvert, 115);
DECLARE_CONVERSION_OP(Bitcast, 124);

#undef DECLARY_UNARY_OP

#define DECLARE_BINOP(name, opcode)                                            \
  template <typename ResultType>                                               \
  [[vk::ext_instruction(opcode)]] ResultType __builtin_spv_##name(             \
      ResultType a, ResultType b)

DECLARE_BINOP(IAdd, 128);
DECLARE_BINOP(FAdd, 129);
DECLARE_BINOP(ISub, 130);
DECLARE_BINOP(FSub, 131);
DECLARE_BINOP(IMul, 132);
DECLARE_BINOP(FMul, 133);
DECLARE_BINOP(UDiv, 134);
DECLARE_BINOP(SDiv, 135);
DECLARE_BINOP(FDiv, 136);

#undef DECLARE_BINOP
namespace vk {
namespace util {

template <class ComponentType> class ArithmeticSelector;

#define ARITHMETIC_SELECTOR(BaseType, OpNegate, OpAdd, OpSub, OpMul, OpDiv,    \
                            SIGNED_INTEGER_TYPE)                               \
  template <> class ArithmeticSelector<BaseType> {                             \
    template <class T> static T Negate(T a) { return OpNegate(a); }            \
    template <class T> static T Add(T a, T b) { return OpAdd(a, b); }          \
    template <class T> static T Sub(T a, T b) { return OpSub(a, b); }          \
    template <class T> static T Mul(T a, T b) { return OpMul(a, b); }          \
    template <class T> static T Div(T a, T b) { return OpDiv(a, b); }          \
  };

ARITHMETIC_SELECTOR(half, __builtin_spv_FNegate, __builtin_spv_FAdd,
                    __builtin_spv_FSub, __builtin_spv_FMul, __builtin_spv_FDiv,
                    false);
ARITHMETIC_SELECTOR(float, __builtin_spv_FNegate, __builtin_spv_FAdd,
                    __builtin_spv_FSub, __builtin_spv_FMul, __builtin_spv_FDiv,
                    false);
ARITHMETIC_SELECTOR(double, __builtin_spv_FNegate, __builtin_spv_FAdd,
                    __builtin_spv_FSub, __builtin_spv_FMul, __builtin_spv_FDiv,
                    false);

#if __HLSL_ENABLE_16_BIT
ARITHMETIC_SELECTOR(int16_t, __builtin_spv_SNegate, __builtin_spv_IAdd,
                    __builtin_spv_ISub, __builtin_spv_IMul, __builtin_spv_SDiv,
                    true);
ARITHMETIC_SELECTOR(uint16_t, __builtin_spv_SNegate, __builtin_spv_IAdd,
                    __builtin_spv_ISub, __builtin_spv_IMul, __builtin_spv_UDiv,
                    false);
#endif // __HLSL_ENABLE_16_BIT

ARITHMETIC_SELECTOR(int32_t, __builtin_spv_SNegate, __builtin_spv_IAdd,
                    __builtin_spv_ISub, __builtin_spv_IMul, __builtin_spv_SDiv,
                    true);
ARITHMETIC_SELECTOR(int64_t, __builtin_spv_SNegate, __builtin_spv_IAdd,
                    __builtin_spv_ISub, __builtin_spv_IMul, __builtin_spv_SDiv,
                    true);
ARITHMETIC_SELECTOR(uint32_t, __builtin_spv_SNegate, __builtin_spv_IAdd,
                    __builtin_spv_ISub, __builtin_spv_IMul, __builtin_spv_UDiv,
                    false);
ARITHMETIC_SELECTOR(uint64_t, __builtin_spv_SNegate, __builtin_spv_IAdd,
                    __builtin_spv_ISub, __builtin_spv_IMul, __builtin_spv_UDiv,
                    false);

// The conversion selector is will be used to convert one type to another
// using the SPIR-V conversion instructions. See
// https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html#_conversion_instructions.
// SourceType and TargetType must be integer or floating point scalar type.

// ConversionSelector::Convert converts an object of type S to an object of type
// T. S must be SourceType, a vector of SourceType, or a cooperative matrix of
// SourceType. T must be TargetType, a vector of TargetType, or a cooperative
// matrix of TargetType. T must have the same number of components as S. T is a
// cooperative matrix if and only if S is a cooperative matrix.
template <class SourceType, class TargetType> class ConversionSelector;

#define CONVERSION_SELECTOR(SourceType, TargetType, OpConvert)                 \
  template <> class ConversionSelector<SourceType, TargetType> {               \
    template <class T, class S> static T Convert(S a) {                        \
      return OpConvert<T>(a);                                                  \
    }                                                                          \
  };

#if __HLSL_ENABLE_16_BIT
CONVERSION_SELECTOR(uint16_t, uint16_t, __builtin_spv_CopyObject);
CONVERSION_SELECTOR(uint16_t, int16_t, __builtin_spv_Bitcast);
CONVERSION_SELECTOR(uint16_t, uint32_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(uint16_t, int32_t, __builtin_spv_SConvert);
CONVERSION_SELECTOR(uint16_t, uint64_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(uint16_t, int64_t, __builtin_spv_SConvert);
CONVERSION_SELECTOR(uint16_t, half, __builtin_spv_ConvertUToF);
CONVERSION_SELECTOR(uint16_t, float, __builtin_spv_ConvertUToF);
CONVERSION_SELECTOR(uint16_t, double, __builtin_spv_ConvertUToF);

CONVERSION_SELECTOR(int16_t, uint16_t, __builtin_spv_Bitcast);
CONVERSION_SELECTOR(int16_t, int16_t, __builtin_spv_CopyObject);
CONVERSION_SELECTOR(int16_t, uint32_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(int16_t, int32_t, __builtin_spv_SConvert);
CONVERSION_SELECTOR(int16_t, uint64_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(int16_t, int64_t, __builtin_spv_SConvert);
CONVERSION_SELECTOR(int16_t, half, __builtin_spv_ConvertSToF);
CONVERSION_SELECTOR(int16_t, float, __builtin_spv_ConvertSToF);
CONVERSION_SELECTOR(int16_t, double, __builtin_spv_ConvertSToF);

CONVERSION_SELECTOR(uint32_t, uint16_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(uint32_t, int16_t, __builtin_spv_SConvert);

CONVERSION_SELECTOR(int32_t, uint16_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(int32_t, int16_t, __builtin_spv_SConvert);

CONVERSION_SELECTOR(uint64_t, uint16_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(uint64_t, int16_t, __builtin_spv_SConvert);

CONVERSION_SELECTOR(int64_t, uint16_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(int64_t, int16_t, __builtin_spv_SConvert);

CONVERSION_SELECTOR(half, uint16_t, __builtin_spv_ConvertFtoU);
CONVERSION_SELECTOR(half, int16_t, __builtin_spv_ConvertFtoS);

CONVERSION_SELECTOR(float, uint16_t, __builtin_spv_ConvertFtoU);
CONVERSION_SELECTOR(float, int16_t, __builtin_spv_ConvertFtoS);

CONVERSION_SELECTOR(double, uint16_t, __builtin_spv_ConvertFtoU);
CONVERSION_SELECTOR(double, int16_t, __builtin_spv_ConvertFtoS);
#endif

CONVERSION_SELECTOR(uint32_t, uint32_t, __builtin_spv_CopyObject);
CONVERSION_SELECTOR(uint32_t, int32_t, __builtin_spv_Bitcast);
CONVERSION_SELECTOR(uint32_t, uint64_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(uint32_t, int64_t, __builtin_spv_SConvert);
CONVERSION_SELECTOR(uint32_t, half, __builtin_spv_ConvertUToF);
CONVERSION_SELECTOR(uint32_t, float, __builtin_spv_ConvertUToF);
CONVERSION_SELECTOR(uint32_t, double, __builtin_spv_ConvertUToF);

CONVERSION_SELECTOR(int32_t, uint32_t, __builtin_spv_Bitcast);
CONVERSION_SELECTOR(int32_t, int32_t, __builtin_spv_CopyObject);
CONVERSION_SELECTOR(int32_t, uint64_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(int32_t, int64_t, __builtin_spv_SConvert);
CONVERSION_SELECTOR(int32_t, half, __builtin_spv_ConvertSToF);
CONVERSION_SELECTOR(int32_t, float, __builtin_spv_ConvertSToF);
CONVERSION_SELECTOR(int32_t, double, __builtin_spv_ConvertSToF);

CONVERSION_SELECTOR(uint64_t, uint32_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(uint64_t, int32_t, __builtin_spv_SConvert);
CONVERSION_SELECTOR(uint64_t, uint64_t, __builtin_spv_Bitcast);
CONVERSION_SELECTOR(uint64_t, int64_t, __builtin_spv_CopyObject);
CONVERSION_SELECTOR(uint64_t, half, __builtin_spv_ConvertUToF);
CONVERSION_SELECTOR(uint64_t, float, __builtin_spv_ConvertUToF);
CONVERSION_SELECTOR(uint64_t, double, __builtin_spv_ConvertUToF);

CONVERSION_SELECTOR(int64_t, uint32_t, __builtin_spv_UConvert);
CONVERSION_SELECTOR(int64_t, int32_t, __builtin_spv_SConvert);
CONVERSION_SELECTOR(int64_t, uint64_t, __builtin_spv_Bitcast);
CONVERSION_SELECTOR(int64_t, int64_t, __builtin_spv_CopyObject);
CONVERSION_SELECTOR(int64_t, half, __builtin_spv_ConvertSToF);
CONVERSION_SELECTOR(int64_t, float, __builtin_spv_ConvertSToF);
CONVERSION_SELECTOR(int64_t, double, __builtin_spv_ConvertSToF);

CONVERSION_SELECTOR(half, uint32_t, __builtin_spv_ConvertFtoU);
CONVERSION_SELECTOR(half, int32_t, __builtin_spv_ConvertFtoS);
CONVERSION_SELECTOR(half, uint64_t, __builtin_spv_ConvertFtoU);
CONVERSION_SELECTOR(half, int64_t, __builtin_spv_ConvertFtoS);
CONVERSION_SELECTOR(half, half, __builtin_spv_CopyObject);
#if __HLSL_ENABLE_16_BIT
CONVERSION_SELECTOR(half, float, __builtin_spv_FConvert);
#else
CONVERSION_SELECTOR(half, float, __builtin_spv_CopyObject);
#endif

CONVERSION_SELECTOR(half, double, __builtin_spv_FConvert);

CONVERSION_SELECTOR(float, uint32_t, __builtin_spv_ConvertFtoU);
CONVERSION_SELECTOR(float, int32_t, __builtin_spv_ConvertFtoS);
CONVERSION_SELECTOR(float, uint64_t, __builtin_spv_ConvertFtoU);
CONVERSION_SELECTOR(float, int64_t, __builtin_spv_ConvertFtoS);
#if __HLSL_ENABLE_16_BIT
CONVERSION_SELECTOR(float, half, __builtin_spv_FConvert);
#else
CONVERSION_SELECTOR(float, half, __builtin_spv_CopyObject);
#endif
CONVERSION_SELECTOR(float, float, __builtin_spv_CopyObject);
CONVERSION_SELECTOR(float, double, __builtin_spv_FConvert);

CONVERSION_SELECTOR(double, uint32_t, __builtin_spv_ConvertFtoU);
CONVERSION_SELECTOR(double, int32_t, __builtin_spv_ConvertFtoS);
CONVERSION_SELECTOR(double, uint64_t, __builtin_spv_ConvertFtoU);
CONVERSION_SELECTOR(double, int64_t, __builtin_spv_ConvertFtoS);
CONVERSION_SELECTOR(double, half, __builtin_spv_FConvert);
CONVERSION_SELECTOR(double, float, __builtin_spv_FConvert);
CONVERSION_SELECTOR(double, double, __builtin_spv_CopyObject);
}; // namespace util
} // namespace vk

#endif // _HLSL_VK_KHR_OPCODE_SELECTOR_H_
// ----- end vk/opcode_selector.h -----

// ----- begin vk/nv/cooperative_vector.h -----
// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef _HLSL_VK_NV_COOPERATIVE_VECTOR_H_
#define _HLSL_VK_NV_COOPERATIVE_VECTOR_H_

#if __SPIRV_MAJOR_VERSION__ == 1 && __SPIRV_MINOR_VERSION__ < 6
#error "CooperativeVector requires a minimum of SPIR-V 1.6"
#endif


namespace vk {
namespace nv {

// The base cooperative vector class. The template arguments correspond to the
// operands in the OpTypeCooperativeVectorNV instruction.
template <typename ComponentType, uint components>
class CooperativeVector {
  template <class NewComponentType>
  CooperativeVector<NewComponentType, components> cast();

  // Apply OpSNegate or OpFNegate, depending on ComponentType, in an element by
  // element manner.
  CooperativeVector negate();

  // Apply OpIAdd or OpFAdd, depending on ComponentType, in an element by element
  // manner.
  CooperativeVector operator+(CooperativeVector other);

  // Apply OpISub or OpFSub, depending on ComponentType, in an element by element
  // manner.
  CooperativeVector operator-(CooperativeVector other);

  // Apply OpIMul or OpFMul, depending on ComponentType, in an element by element
  // manner.
  CooperativeVector operator*(CooperativeVector other);

  // Apply OpSDiv, OpUDiv or OpFDiv, depending on ComponentType, in an element by
  // element manner.
  CooperativeVector operator/(CooperativeVector other);

  // Apply OpMatrixTimesScalar in an element by element manner.
  CooperativeVector operator*(ComponentType scalar);

  // Load a cooperative vector using OpCooperativeVectorLoadNV from
  // data[index] using the given memory access operands.
  template <uint32_t memoryAccessOperands, class Type>
  static CooperativeVector Load(RWStructuredBuffer<Type> data, uint32_t index);

  // Same as above, but uses MemoryAccessMaskNone for the memory access
  // operands.
  template <class Type>
  static CooperativeVector Load(RWStructuredBuffer<Type> data, uint32_t index) {
    return Load<MemoryAccessMaskNone>(data, index);
  }

  // Load a cooperative vector using OpCooperativeVectorLoadNV from
  // data[index] using the given memory access operands. No additional memory
  // access bits are added since the memory is readonly.
  template <uint32_t memoryAccessOperands, class Type>
  static CooperativeVector Load(StructuredBuffer<Type> data, uint32_t index);

  // Same as above, but uses MemoryAccessMaskNone for the memory access
  // operands.
  template <class Type>
  static CooperativeVector Load(StructuredBuffer<Type> data, uint32_t index) {
    return Load<MemoryAccessMaskNone>(data, index);
  }

  // Store the cooperative vector using OpCooperativeVectorStoreNV to
  // data[index] using the given memory access operands.
  template <uint32_t memoryAccessOperands, class Type>
  void Store(RWStructuredBuffer<Type> data, uint32_t index);

  // Same as above, but uses MemoryAccessMaskNone for the memory access
  // operands.
  template <class Type>
  void Store(RWStructuredBuffer<Type> data, uint32_t index) {
    Store<MemoryAccessMaskNone>(data, index);
  }

  // Load a cooperative vector using OpCooperativeVectorLoadNV from
  // groupshared memory using the given memory access operands.
  //
  // This function uses a SPIR-V pointer because HLSL does not allow groupshared
  // memory object to be passed by reference.
  template <uint32_t memoryAccessOperands, class Type>
  static CooperativeVector Load(WorkgroupSpirvPointer<Type> data);

  // Same as above, but uses MemoryAccessMaskNone for the memory access
  // operands.
  template <class Type>
  static CooperativeVector Load(WorkgroupSpirvPointer<Type> data) {
    return Load<MemoryAccessMaskNone>(data);
  }

  // Store the cooperative vector using OpCooperativeVectorStoreNV to
  // groupshared memory using the given memory access operands.
  //
  // This function uses a SPIR-V pointer because HLSL does not allow groupshared
  // memory object to be passed by reference.
  template <uint32_t memoryAccessOperands, class Type>
  void Store(WorkgroupSpirvPointer<Type> data);

  // Same as above, but uses MemoryAccessMaskNone for the memory access
  // operands.
  template <class Type>
  void Store(WorkgroupSpirvPointer<Type> data) {
    Store<MemoryAccessMaskNone>(data);
  }

  // Constructs a cooperative vector with all values initialized to v.
  static CooperativeVector Splat(ComponentType v);

  // Returns the number of components in the cooperative vector.
  static uint32_t GetLength();

  // Functions to access the elements of the cooperative vector. The index must
  // be less than GetLength().
  void Set(ComponentType value, uint32_t index);
  ComponentType Get(uint32_t index);

  static const bool hasSignedIntegerComponentType =
      (ComponentType(0) - ComponentType(1) < ComponentType(0));

  // clang-format off
  using SpirvVectorType = vk::SpirvOpaqueType<
      /* OpTypeCooperativeVectorNV */ 5288,
      ComponentType,
      vk::integral_constant<uint, components> >;

  [[vk::ext_extension("SPV_NV_cooperative_vector")]]
  [[vk::ext_capability(/* CooperativeVectorNV */ 5394)]]
  SpirvVectorType _vector;
  // clang-format on
};

// Returns the result of OpCooperativeVectorMatrixMulNV: result = matrix * input.
// The cooperative matrix operands are inferred from signedness.
template <typename ResultComponentType, typename InputComponentType,
          uint M, uint K, class BufferType>
CooperativeVector<ResultComponentType, M>
cooperativeVectorMatrixMul(
    CooperativeVector<InputComponentType, K> input,
    uint inputInterpretation,
    BufferType matrix, uint matrixOffset,
    uint matrixInterpretation,
    uint stride, CooperativeVectorMatrixLayout layout,
    bool transpose);

// Returns the result of OpCooperativeVectorMatrixMulAddNV:
// result = matrix * input + bias.
// The cooperative matrix operands are inferred from signedness.
template <typename ResultComponentType, typename InputComponentType,
          uint M, uint K, class BufferType>
CooperativeVector<ResultComponentType, M>
cooperativeVectorMatrixMulAdd(
    CooperativeVector<InputComponentType, K> input,
    uint inputInterpretation,
    BufferType matrix, uint matrixOffset,
    uint matrixInterpretation,
    BufferType bias, uint biasOffset,
    uint biasInterpretation,
    uint stride, CooperativeVectorMatrixLayout layout,
    bool transpose);

// Atomically accumulates v1 * transpose(v2) into buf.
// REQUIRES: CooperativeVectorTrainingNV capability.
template <typename T, uint M, uint N, class BufferType>
void cooperativeVectorOuterProductAccumulate(
    CooperativeVector<T, M> v1,
    CooperativeVector<T, N> v2,
    BufferType buf, uint offset, uint stride,
    CooperativeVectorMatrixLayout layout, uint matrixInterpretation);

// Atomically adds vector components to buf.
// REQUIRES: CooperativeVectorTrainingNV capability.
template <typename T, uint N, class BufferType>
void cooperativeVectorReduceSumAccumulate(
    CooperativeVector<T, N> v,
    BufferType buf, uint offset);

} // namespace nv
} // namespace vk

#endif // _HLSL_VK_NV_COOPERATIVE_VECTOR_H_
// ----- end vk/nv/cooperative_vector.h -----

// ----- begin vk/nv/cooperative_vector.impl -----
// Copyright (c) 2024 Google LLC
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception


// ============================================================================
// Inline-SPIR-V Builtin Declarations
// ============================================================================

// --- Composite operations for element access ---

template <typename ComponentType, uint components>
[[vk::ext_instruction(/* OpCompositeExtract */ 81)]] ComponentType
__builtin_spv_ExtractFromCooperativeVector(
    typename vk::nv::CooperativeVector<ComponentType, components>::SpirvVectorType vec,
    uint32_t index);

template <typename CoopVecType, typename ComponentType>
[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] CoopVecType
__builtin_spv_ConstructCooperativeVector(ComponentType value);

template <typename CoopVecType, typename ComponentType>
[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] CoopVecType
__builtin_spv_ConstructCooperativeVector_2(ComponentType v0, ComponentType v1);

template <typename CoopVecType, typename ComponentType>
[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] CoopVecType
__builtin_spv_ConstructCooperativeVector_4(ComponentType v0, ComponentType v1, ComponentType v2, ComponentType v3);

template <typename CoopVecType, typename ComponentType>
[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] CoopVecType
__builtin_spv_ConstructCooperativeVector_8(ComponentType v0, ComponentType v1, ComponentType v2, ComponentType v3, ComponentType v4, ComponentType v5, ComponentType v6, ComponentType v7);

template <typename CoopVecType, typename ComponentType>
[[vk::ext_instruction(/* OpCompositeConstruct */ 80)]] CoopVecType
__builtin_spv_ConstructCooperativeVector_16(ComponentType v0, ComponentType v1, ComponentType v2, ComponentType v3, ComponentType v4, ComponentType v5, ComponentType v6, ComponentType v7, ComponentType v8, ComponentType v9, ComponentType v10, ComponentType v11, ComponentType v12, ComponentType v13, ComponentType v14, ComponentType v15);

template <typename ComponentType, uint components>
[[vk::ext_instruction(/* OpCompositeInsert */ 82)]]
typename vk::nv::CooperativeVector<ComponentType, components>::SpirvVectorType
__builtin_spv_InsertIntoCooperativeVector(
    ComponentType value,
    typename vk::nv::CooperativeVector<ComponentType, components>::SpirvVectorType vec,
    uint32_t index);

// --- Matrix-times-scalar for scalar multiplication ---

template <typename ResultType, typename ComponentType>
[[vk::ext_instruction(/* OpMatrixTimesScalar */ 143)]] ResultType
__builtin_spv_MatrixTimesScalar(ResultType a, ComponentType b);

// --- OpCooperativeVectorMatrixMulNV (5289) ---

template <typename ResultType, typename InputVectorType,
          typename MatrixPointerType>
[[vk::ext_instruction(/* OpCooperativeVectorMatrixMulNV */ 5289)]] ResultType
__builtin_spv_CooperativeVectorMatrixMulNV(
    InputVectorType input,                        // IdRef
    uint inputInterpretation,                     // IdRef
    [[vk::ext_reference]] MatrixPointerType matrix, // IdRef (pointer)
    uint matrixOffset,                            // IdRef
    uint matrixInterpretation,                    // IdRef
    uint M, uint K,                               // IdRef
    uint memoryLayout,                            // IdRef
    bool transpose,                               // IdRef
    uint matrixStride,                            // IdRef
    [[vk::ext_literal]] uint32_t operands);       // CooperativeMatrixOperands LITERAL

// --- OpCooperativeVectorMatrixMulAddNV (5292) ---

template <typename ResultType, typename InputVectorType,
          typename MatrixPointerType, typename BiasPointerType>
[[vk::ext_instruction(/* OpCooperativeVectorMatrixMulAddNV */ 5292)]] ResultType
__builtin_spv_CooperativeVectorMatrixMulAddNV(
    InputVectorType input,
    uint inputInterpretation,
    [[vk::ext_reference]] MatrixPointerType matrix, uint matrixOffset,
    uint matrixInterpretation,
    [[vk::ext_reference]] BiasPointerType bias, uint biasOffset,
    uint biasInterpretation,
    uint M, uint K,
    uint memoryLayout,
    bool transpose,
    uint matrixStride,
    [[vk::ext_literal]] uint32_t operands);

// --- OpCooperativeVectorOuterProductAccumulateNV (5290) ---
// NOTE: Requires CooperativeVectorTrainingNV (5435) capability

template <typename VecType1, typename VecType2, typename PointerType>
[[vk::ext_instruction(/* OpCooperativeVectorOuterProductAccumulateNV */ 5290)]]
[[vk::ext_capability(/* CooperativeVectorTrainingNV */ 5435)]] void
__builtin_spv_CooperativeVectorOuterProductAccumulateNV(
    [[vk::ext_reference]] PointerType buf, uint offset,
    VecType1 v1, VecType2 v2,
    uint memoryLayout, uint matrixInterpretation, uint matrixStride);

// --- OpCooperativeVectorReduceSumAccumulateNV (5291) ---
// NOTE: Requires CooperativeVectorTrainingNV (5435) capability

template <typename VecType, typename PointerType>
[[vk::ext_instruction(/* OpCooperativeVectorReduceSumAccumulateNV */ 5291)]]
[[vk::ext_capability(/* CooperativeVectorTrainingNV */ 5435)]] void
__builtin_spv_CooperativeVectorReduceSumAccumulateNV(
    [[vk::ext_reference]] PointerType buf, uint offset, VecType v);

// --- OpCooperativeVectorLoadNV (5302) ---

template <typename ResultType, typename PointerType>
[[vk::ext_instruction(/* OpCooperativeVectorLoadNV */ 5302)]] ResultType
__builtin_spv_CooperativeVectorLoadNV(
    [[vk::ext_reference]] PointerType pointer, uint offset,
    [[vk::ext_literal]] uint32_t memoryAccess);

// --- OpCooperativeVectorStoreNV (5303) ---

template <typename ObjectType, typename PointerType>
[[vk::ext_instruction(/* OpCooperativeVectorStoreNV */ 5303)]] void
__builtin_spv_CooperativeVectorStoreNV(
    [[vk::ext_reference]] PointerType pointer, uint offset,
    ObjectType object,
    [[vk::ext_literal]] uint32_t memoryAccess);

// --- OpCooperativeVectorLoadNV from WorkgroupSpirvPointer ---

template <typename ResultType, typename PointerType>
[[vk::ext_instruction(/* OpCooperativeVectorLoadNV */ 5302)]] ResultType
__builtin_spv_CooperativeVectorWorkgroupLoadNV(
    vk::WorkgroupSpirvPointer<PointerType> pointer, uint offset,
    [[vk::ext_literal]] uint32_t memoryAccess);

// --- OpCooperativeVectorStoreNV to WorkgroupSpirvPointer ---

template <typename ObjectType, typename PointerType>
[[vk::ext_instruction(/* OpCooperativeVectorStoreNV */ 5303)]] void
__builtin_spv_CooperativeVectorWorkgroupStoreNV(
    vk::WorkgroupSpirvPointer<PointerType> pointer, uint offset,
    ObjectType object,
    [[vk::ext_literal]] uint32_t memoryAccess);


// ============================================================================
// Template Method Implementations
// ============================================================================

namespace vk {
namespace nv {

template <class ComponentType, uint components>
template <class NewComponentType>
CooperativeVector<NewComponentType, components>
CooperativeVector<ComponentType, components>::cast() {
  using ResultType =
      CooperativeVector<NewComponentType, components>;
  ResultType result;
  result._vector = util::ConversionSelector<ComponentType, NewComponentType>::
      template Convert<typename ResultType::SpirvVectorType>(_vector);
  return result;
}

template <class ComponentType, uint components>
CooperativeVector<ComponentType, components>
CooperativeVector<ComponentType, components>::negate() {
  CooperativeVector result;
  result._vector = util::ArithmeticSelector<ComponentType>::Negate(_vector);
  return result;
}

template <class ComponentType, uint components>
CooperativeVector<ComponentType, components>
CooperativeVector<ComponentType, components>::operator+(
    CooperativeVector other) {
  CooperativeVector result;
  result._vector =
      util::ArithmeticSelector<ComponentType>::Add(_vector, other._vector);
  return result;
}

template <class ComponentType, uint components>
CooperativeVector<ComponentType, components>
CooperativeVector<ComponentType, components>::operator-(
    CooperativeVector other) {
  CooperativeVector result;
  result._vector =
      util::ArithmeticSelector<ComponentType>::Sub(_vector, other._vector);
  return result;
}

template <class ComponentType, uint components>
CooperativeVector<ComponentType, components>
CooperativeVector<ComponentType, components>::operator*(
    CooperativeVector other) {
  CooperativeVector result;
  result._vector =
      util::ArithmeticSelector<ComponentType>::Mul(_vector, other._vector);
  return result;
}

template <class ComponentType, uint components>
CooperativeVector<ComponentType, components>
CooperativeVector<ComponentType, components>::operator/(
    CooperativeVector other) {
  CooperativeVector result;
  result._vector =
      util::ArithmeticSelector<ComponentType>::Div(_vector, other._vector);
  return result;
}

template <class ComponentType, uint components>
CooperativeVector<ComponentType, components>
CooperativeVector<ComponentType, components>::operator*(
    ComponentType scalar) {
  CooperativeVector result;
  result._vector = __builtin_spv_MatrixTimesScalar(_vector, scalar);
  return result;
}

template <class ComponentType, uint components>
template <uint32_t memoryAccessOperands, class Type>
CooperativeVector<ComponentType, components>
CooperativeVector<ComponentType, components>::Load(
    RWStructuredBuffer<Type> data, uint32_t index) {
  CooperativeVector result;
  result._vector = __builtin_spv_CooperativeVectorLoadNV<SpirvVectorType>(
      data[index], 0, memoryAccessOperands);
  return result;
}

template <class ComponentType, uint components>
template <uint32_t memoryAccessOperands, class Type>
CooperativeVector<ComponentType, components>
CooperativeVector<ComponentType, components>::Load(
    StructuredBuffer<Type> data, uint32_t index) {
  CooperativeVector result;
  result._vector = __builtin_spv_CooperativeVectorLoadNV<SpirvVectorType>(
      data[index], 0, MemoryAccessMaskNone);
  return result;
}

template <class ComponentType, uint components>
template <uint32_t memoryAccessOperands, class Type>
void CooperativeVector<ComponentType, components>::Store(
    RWStructuredBuffer<Type> data, uint32_t index) {
  __builtin_spv_CooperativeVectorStoreNV(data[index], 0, _vector,
                                         memoryAccessOperands);
}

template <class ComponentType, uint components>
template <uint32_t memoryAccessOperands, class Type>
CooperativeVector<ComponentType, components>
CooperativeVector<ComponentType, components>::Load(
    vk::WorkgroupSpirvPointer<Type> data) {
  CooperativeVector result;
  result._vector =
      __builtin_spv_CooperativeVectorWorkgroupLoadNV<SpirvVectorType>(
          data, 0,
          memoryAccessOperands | MemoryAccessNonPrivatePointerMask |
              MemoryAccessMakePointerVisibleMask);
  return result;
}

template <class ComponentType, uint components>
template <uint32_t memoryAccessOperands, class Type>
void CooperativeVector<ComponentType, components>::Store(
    vk::WorkgroupSpirvPointer<Type> data) {
  __builtin_spv_CooperativeVectorWorkgroupStoreNV(
      data, 0, _vector,
      memoryAccessOperands | MemoryAccessNonPrivatePointerMask |
          MemoryAccessMakePointerAvailableMask);
}

template <class ComponentType, uint components>
CooperativeVector<ComponentType, components>
CooperativeVector<ComponentType, components>::Splat(ComponentType v) {
  CooperativeVector result;
  result._vector = __builtin_spv_ConstructCooperativeVector<SpirvVectorType>(v);
  return result;
}

template <class ComponentType, uint components>
uint32_t CooperativeVector<ComponentType, components>::GetLength() {
  return components;
}

template <class ComponentType, uint components>
ComponentType CooperativeVector<ComponentType, components>::Get(
    uint32_t index) {
  return __builtin_spv_ExtractFromCooperativeVector<ComponentType, components>(
      _vector, index);
}

template <class ComponentType, uint components>
void CooperativeVector<ComponentType, components>::Set(
    ComponentType value, uint32_t index) {
  _vector = __builtin_spv_InsertIntoCooperativeVector<ComponentType, components>(
      value, _vector, index);
}


// ============================================================================
// Free Function Implementations
// ============================================================================

template <typename ResultComponentType, typename InputComponentType,
          uint M, uint K, class BufferType>
CooperativeVector<ResultComponentType, M>
cooperativeVectorMatrixMul(
    CooperativeVector<InputComponentType, K> input,
    uint inputInterpretation,
    BufferType matrix, uint matrixOffset,
    uint matrixInterpretation,
    uint stride, CooperativeVectorMatrixLayout layout,
    bool transpose) {

  const CooperativeMatrixOperandsMask allSignedComponents =
      CooperativeMatrixOperandsMatrixASignedComponentsKHRMask |
      CooperativeMatrixOperandsMatrixBSignedComponentsKHRMask |
      CooperativeMatrixOperandsMatrixCSignedComponentsKHRMask |
      CooperativeMatrixOperandsMatrixResultSignedComponentsKHRMask;

  const CooperativeMatrixOperandsMask operands =
      (CooperativeMatrixOperandsMask)(
          input.hasSignedIntegerComponentType
              ? allSignedComponents
              : CooperativeMatrixOperandsMaskNone);

  CooperativeVector<ResultComponentType, M> result;
  result._vector = __builtin_spv_CooperativeVectorMatrixMulNV<
      typename CooperativeVector<ResultComponentType, M>::SpirvVectorType>(
      input._vector, inputInterpretation,
      matrix, matrixOffset, matrixInterpretation,
      M, K, layout, transpose, stride, operands);
  return result;
}

template <typename ResultComponentType, typename InputComponentType,
          uint M, uint K, class BufferType>
CooperativeVector<ResultComponentType, M>
cooperativeVectorMatrixMulAdd(
    CooperativeVector<InputComponentType, K> input,
    uint inputInterpretation,
    BufferType matrix, uint matrixOffset,
    uint matrixInterpretation,
    BufferType bias, uint biasOffset,
    uint biasInterpretation,
    uint stride, CooperativeVectorMatrixLayout layout,
    bool transpose) {

  const CooperativeMatrixOperandsMask allSignedComponents =
      CooperativeMatrixOperandsMatrixASignedComponentsKHRMask |
      CooperativeMatrixOperandsMatrixBSignedComponentsKHRMask |
      CooperativeMatrixOperandsMatrixCSignedComponentsKHRMask |
      CooperativeMatrixOperandsMatrixResultSignedComponentsKHRMask;

  const CooperativeMatrixOperandsMask operands =
      (CooperativeMatrixOperandsMask)(
          input.hasSignedIntegerComponentType
              ? allSignedComponents
              : CooperativeMatrixOperandsMaskNone);

  CooperativeVector<ResultComponentType, M> result;
  result._vector = __builtin_spv_CooperativeVectorMatrixMulAddNV<
      typename CooperativeVector<ResultComponentType, M>::SpirvVectorType>(
      input._vector, inputInterpretation,
      matrix, matrixOffset, matrixInterpretation,
      bias, biasOffset, biasInterpretation,
      M, K, layout, transpose, stride, operands);
  return result;
}

template <typename T, uint M, uint N, class BufferType>
void cooperativeVectorOuterProductAccumulate(
    CooperativeVector<T, M> v1,
    CooperativeVector<T, N> v2,
    BufferType buf, uint offset, uint stride,
    CooperativeVectorMatrixLayout layout, uint matrixInterpretation) {
  __builtin_spv_CooperativeVectorOuterProductAccumulateNV(
      buf, offset, v1._vector, v2._vector,
      layout, matrixInterpretation, stride);
}

template <typename T, uint N, class BufferType>
void cooperativeVectorReduceSumAccumulate(
    CooperativeVector<T, N> v,
    BufferType buf, uint offset) {
  __builtin_spv_CooperativeVectorReduceSumAccumulateNV(
      buf, offset, v._vector);
}

} // namespace nv
} // namespace vk
// ----- end vk/nv/cooperative_vector.impl -----


namespace dx {
namespace linalg {

// NOTE: can't be an enum class because we get this error:
//     error: non-type template argument of type 'dx::linalg::DataType' is not
//     an integral constant expression
//
enum DataType {
  DATA_TYPE_SINT16 = 2,
  DATA_TYPE_UINT16 = 3,
  DATA_TYPE_SINT32 = 4,
  DATA_TYPE_UINT32 = 5,
  DATA_TYPE_FLOAT16 = 8,
  DATA_TYPE_FLOAT32 = 9,
  DATA_TYPE_SINT8_T4_PACKED = 17,
  DATA_TYPE_UINT8_T4_PACKED = 18,
  DATA_TYPE_UINT8 = 19,
  DATA_TYPE_SINT8 = 20,
  DATA_TYPE_FLOAT8_E4M3 = 21,
  DATA_TYPE_FLOAT8_E5M2 = 22,
};

enum MatrixLayout {
  MATRIX_LAYOUT_ROW_MAJOR = 0,
  MATRIX_LAYOUT_COLUMN_MAJOR = 1,
  MATRIX_LAYOUT_MUL_OPTIMAL = 2,
  MATRIX_LAYOUT_OUTER_PRODUCT_OPTIMAL = 3
};

//
// (RW)MatrixRef
//

template <typename BufferTy, DataType DT, uint M, uint K, MatrixLayout ML,
          bool Transpose>
struct MatrixRefImpl {
  BufferTy Buffer;
  uint StartOffset;
  uint Stride;
};

template <DataType DT, uint M, uint K, MatrixLayout ML, bool Transpose = false>
using MatrixRef = MatrixRefImpl<ByteAddressBuffer, DT, M, K, ML, Transpose>;

template <DataType DT, uint M, uint K, MatrixLayout ML, bool Transpose = false>
using RWMatrixRef = MatrixRefImpl<RWByteAddressBuffer, DT, M, K, ML, Transpose>;

//
// (RW)VectorRef
//

template <typename BufferTy, DataType DT> struct VectorRefImpl {
  BufferTy Buffer;
  uint StartOffset;
};

template <DataType DT> using VectorRef = VectorRefImpl<ByteAddressBuffer, DT>;

template <DataType DT>
using RWVectorRef = VectorRefImpl<RWByteAddressBuffer, DT>;

// --- Map dx::linalg::MatrixLayout to vk::CooperativeVectorMatrixLayout ---

template <MatrixLayout ML> struct MatrixLayoutMap {};
template <> struct MatrixLayoutMap<MATRIX_LAYOUT_ROW_MAJOR> {
  static const vk::CooperativeVectorMatrixLayout value =
      vk::CooperativeVectorMatrixLayoutRowMajorNV;
};
template <> struct MatrixLayoutMap<MATRIX_LAYOUT_COLUMN_MAJOR> {
  static const vk::CooperativeVectorMatrixLayout value =
      vk::CooperativeVectorMatrixLayoutColumnMajorNV;
};
template <> struct MatrixLayoutMap<MATRIX_LAYOUT_MUL_OPTIMAL> {
  static const vk::CooperativeVectorMatrixLayout value =
      vk::CooperativeVectorMatrixLayoutInferencingOptimalNV;
};
template <> struct MatrixLayoutMap<MATRIX_LAYOUT_OUTER_PRODUCT_OPTIMAL> {
  static const vk::CooperativeVectorMatrixLayout value =
      vk::CooperativeVectorMatrixLayoutTrainingOptimalNV;
};

// --- Map dx::linalg::DataType to SPIR-V component type ---

template <DataType DT> struct ComponentTypeMap {};
template <> struct ComponentTypeMap<DATA_TYPE_FLOAT16> {
  static const uint value = vk::CooperativeVectorComponentTypeFloat16NV;
};
template <> struct ComponentTypeMap<DATA_TYPE_FLOAT32> {
  static const uint value = vk::CooperativeVectorComponentTypeFloat32NV;
};
template <> struct ComponentTypeMap<DATA_TYPE_SINT16> {
  static const uint value = vk::CooperativeVectorComponentTypeSignedInt16NV;
};
template <> struct ComponentTypeMap<DATA_TYPE_UINT16> {
  static const uint value = vk::CooperativeVectorComponentTypeUnsignedInt16NV;
};
template <> struct ComponentTypeMap<DATA_TYPE_SINT32> {
  static const uint value = vk::CooperativeVectorComponentTypeSignedInt32NV;
};
template <> struct ComponentTypeMap<DATA_TYPE_UINT32> {
  static const uint value = vk::CooperativeVectorComponentTypeUnsignedInt32NV;
};
template <> struct ComponentTypeMap<DATA_TYPE_UINT8> {
  static const uint value = vk::CooperativeVectorComponentTypeUnsignedInt8NV;
};
template <> struct ComponentTypeMap<DATA_TYPE_SINT8> {
  static const uint value = vk::CooperativeVectorComponentTypeSignedInt8NV;
};
template <> struct ComponentTypeMap<DATA_TYPE_SINT8_T4_PACKED> {
  static const uint value = vk::CooperativeVectorComponentTypeSignedInt8PackedNV;
};
template <> struct ComponentTypeMap<DATA_TYPE_UINT8_T4_PACKED> {
  static const uint value = vk::CooperativeVectorComponentTypeUnsignedInt8PackedNV;
};
template <> struct ComponentTypeMap<DATA_TYPE_FLOAT8_E4M3> {
  static const uint value = vk::CooperativeVectorComponentTypeFloatE4M3NV;
};
template <> struct ComponentTypeMap<DATA_TYPE_FLOAT8_E5M2> {
  static const uint value = vk::CooperativeVectorComponentTypeFloatE5M2NV;
};

//
// Helper: construct cooperative vector from regular vector via OpCompositeConstruct.
// Uses template specialization to pick the right N-argument builtin.
//
template <typename ElTy, int ElCount>
struct CoopVecConstructor {
  static vk::nv::CooperativeVector<ElTy, ElCount> Construct(vector<ElTy, ElCount> v);
};

template <typename ElTy>
struct CoopVecConstructor<ElTy, 1> {
  static vk::nv::CooperativeVector<ElTy, 1> Construct(vector<ElTy, 1> v) {
    using CV = vk::nv::CooperativeVector<ElTy, 1>;
    CV result;
    result._vector = __builtin_spv_ConstructCooperativeVector<typename CV::SpirvVectorType>(v[0]);
    return result;
  }
};

template <typename ElTy>
struct CoopVecConstructor<ElTy, 2> {
  static vk::nv::CooperativeVector<ElTy, 2> Construct(vector<ElTy, 2> v) {
    using CV = vk::nv::CooperativeVector<ElTy, 2>;
    CV result;
    result._vector = __builtin_spv_ConstructCooperativeVector_2<typename CV::SpirvVectorType>(v[0], v[1]);
    return result;
  }
};

template <typename ElTy>
struct CoopVecConstructor<ElTy, 4> {
  static vk::nv::CooperativeVector<ElTy, 4> Construct(vector<ElTy, 4> v) {
    using CV = vk::nv::CooperativeVector<ElTy, 4>;
    CV result;
    result._vector = __builtin_spv_ConstructCooperativeVector_4<typename CV::SpirvVectorType>(v[0], v[1], v[2], v[3]);
    return result;
  }
};

template <typename ElTy>
struct CoopVecConstructor<ElTy, 8> {
  static vk::nv::CooperativeVector<ElTy, 8> Construct(vector<ElTy, 8> v) {
    using CV = vk::nv::CooperativeVector<ElTy, 8>;
    CV result;
    result._vector = __builtin_spv_ConstructCooperativeVector_8<typename CV::SpirvVectorType>(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]);
    return result;
  }
};

template <typename ElTy>
struct CoopVecConstructor<ElTy, 16> {
  static vk::nv::CooperativeVector<ElTy, 16> Construct(vector<ElTy, 16> v) {
    using CV = vk::nv::CooperativeVector<ElTy, 16>;
    CV result;
    result._vector = __builtin_spv_ConstructCooperativeVector_16<typename CV::SpirvVectorType>(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12], v[13], v[14], v[15]);
    return result;
  }
};

//
// Helpers: convert between vector and vk::nv::CooperativeVector
//
template <typename ElTy, int ElCount>
vk::nv::CooperativeVector<ElTy, ElCount> ToCooperativeVector(vector<ElTy, ElCount> v) {
  return CoopVecConstructor<ElTy, ElCount>::Construct(v);
}

template <typename ElTy, int ElCount>
vector<ElTy, ElCount> ToVector(vk::nv::CooperativeVector<ElTy, ElCount> cv) {
  vector<ElTy, ElCount> v;
  [unroll] for (uint32_t i = 0; i < ElCount; ++i) {
    v[i] = cv.Get(i);
  }
  return v;
}

//
// CoopMul — SPIR-V version (uses CooperativeVector)
//
template <typename MatrixBuffer, typename InType, typename OutType,
          DataType MatRefType, uint in_dim, uint out_dim>
vector<OutType, out_dim> CoopMul(
    MatrixBuffer mat_buffer,
    uint mat_offset,
    vector<InType, in_dim> input_vec
) {
    vk::nv::CooperativeVector<OutType, out_dim> result =
        vk::nv::cooperativeVectorMatrixMul<OutType, InType, out_dim, in_dim>(
            ToCooperativeVector(input_vec),
            ComponentTypeMap<MatRefType>::value,
            mat_buffer, mat_offset,
            ComponentTypeMap<MatRefType>::value,
            /*stride*/ 0,
            vk::CooperativeVectorMatrixLayoutInferencingOptimalNV,
            /*transpose*/ false);
    return ToVector(result);
}

//
// CoopMulAdd — SPIR-V version
//
template <typename MatrixBuffer, typename BiasBuffer, typename InType,
          typename OutType, DataType MatRefType, DataType BiasRefType,
          uint in_dim, uint out_dim>
vector<OutType, out_dim> CoopMulAdd(
    MatrixBuffer mat_buffer,
    uint mat_offset,
    BiasBuffer bias_buffer,
    uint bias_offset,
    vector<InType, in_dim> input_vec
) {
    vk::nv::CooperativeVector<OutType, out_dim> result =
        vk::nv::cooperativeVectorMatrixMulAdd<OutType, InType, out_dim, in_dim>(
            ToCooperativeVector(input_vec),
            ComponentTypeMap<MatRefType>::value,
            mat_buffer, mat_offset,
            ComponentTypeMap<MatRefType>::value,
            bias_buffer, bias_offset,
            ComponentTypeMap<BiasRefType>::value,
            /*stride*/ 0,
            vk::CooperativeVectorMatrixLayoutInferencingOptimalNV,
            /*transpose*/ false);
    return ToVector(result);
}

//
// CoopOuterProductAccum — SPIR-V version
//
template <typename MatrixBuffer, typename ElTy, int MatrixM, int MatrixN,
          DataType MatrixDT>
void CoopOuterProductAccum(
  MatrixBuffer buffer,
  uint buffer_offset,
  vector<ElTy, MatrixM> v1,
  vector<ElTy, MatrixN> v2
){
  vk::nv::cooperativeVectorOuterProductAccumulate(
      ToCooperativeVector(v1), ToCooperativeVector(v2),
      buffer, buffer_offset, /*stride*/ 0,
      vk::CooperativeVectorMatrixLayoutTrainingOptimalNV,
      ComponentTypeMap<MatrixDT>::value);
}

//
// CoopVectorAccumulate — SPIR-V version
//
template <typename ElTy, int ElCount>
void CoopVectorAccumulate(RWByteAddressBuffer Buffer, uint Offset,
                          vector<ElTy, ElCount> InputVector) {
  vk::nv::cooperativeVectorReduceSumAccumulate(
      ToCooperativeVector(InputVector), Buffer, Offset);
}

} // namespace linalg
} // namespace dx

#else // __spirv__

// DirectX path: existing code, unchanged

#if ((__SHADER_TARGET_MAJOR > 6) ||                                            \
     (__SHADER_TARGET_MAJOR == 6 && __SHADER_TARGET_MINOR >= 9)) &&            \
    (__HLSL_VERSION >= 2021)

namespace dx {
namespace linalg {

// NOTE: can't be an enum class because we get this error:
//     error: non-type template argument of type 'dx::linalg::DataType' is not
//     an integral constant expression
//
enum DataType {
  DATA_TYPE_SINT16 = 2,           // ComponentType::I16
  DATA_TYPE_UINT16 = 3,           // ComponentType::U16
  DATA_TYPE_SINT32 = 4,           // ComponentType::I32
  DATA_TYPE_UINT32 = 5,           // ComponentType::U32
  DATA_TYPE_FLOAT16 = 8,          // ComponentType::F16
  DATA_TYPE_FLOAT32 = 9,          // ComponentType::F32
  DATA_TYPE_SINT8_T4_PACKED = 17, // ComponentType::PackedS8x32
  DATA_TYPE_UINT8_T4_PACKED = 18, // ComponentType::PackedU8x32
  DATA_TYPE_UINT8 = 19,           // ComponentType::U8
  DATA_TYPE_SINT8 = 20,           // ComponentType::I8
  DATA_TYPE_FLOAT8_E4M3 = 21,     // ComponentType::F8_E4M3
                                  // (1 sign, 4 exp, 3 mantissa bits)
  DATA_TYPE_FLOAT8_E5M2 = 22,     // ComponentType::F8_E5M2
                                  // (1 sign, 5 exp, 2 mantissa bits)
};

enum MatrixLayout {
  MATRIX_LAYOUT_ROW_MAJOR = 0,
  MATRIX_LAYOUT_COLUMN_MAJOR = 1,
  MATRIX_LAYOUT_MUL_OPTIMAL = 2,
  MATRIX_LAYOUT_OUTER_PRODUCT_OPTIMAL = 3
};

//
// Helper for signedness
//
namespace details {

template <typename T> struct IsUnsigned {};

#define _SPECIALIZE_ISUNSIGNED(type, value)                                    \
  template <> struct IsUnsigned<type> {                                        \
    static const bool Value = value;                                           \
  }

_SPECIALIZE_ISUNSIGNED(uint8_t4_packed, true);
_SPECIALIZE_ISUNSIGNED(int8_t4_packed, false);
_SPECIALIZE_ISUNSIGNED(uint32_t, true);
_SPECIALIZE_ISUNSIGNED(int32_t, false);
_SPECIALIZE_ISUNSIGNED(float32_t, false);

#ifdef __HLSL_ENABLE_16_BIT
_SPECIALIZE_ISUNSIGNED(uint16_t, true);
_SPECIALIZE_ISUNSIGNED(int16_t, false);
_SPECIALIZE_ISUNSIGNED(float16_t, false);
#else  // //__HLSL_ENABLE_16_BIT
_SPECIALIZE_ISUNSIGNED(half, false);
#endif //__HLSL_ENABLE_16_BIT

#undef _SPECIALIZE_ISUNSIGNED

} // namespace details

//
// (RW)MatrixRef
//

template <typename BufferTy, DataType DT, uint M, uint K, MatrixLayout ML,
          bool Transpose>
struct MatrixRefImpl {
  BufferTy Buffer;
  uint StartOffset;
  uint Stride;
};

template <DataType DT, uint M, uint K, MatrixLayout ML, bool Transpose = false>
using MatrixRef = MatrixRefImpl<ByteAddressBuffer, DT, M, K, ML, Transpose>;

template <DataType DT, uint M, uint K, MatrixLayout ML, bool Transpose = false>
using RWMatrixRef = MatrixRefImpl<RWByteAddressBuffer, DT, M, K, ML, Transpose>;

//
// (RW)VectorRef
//

template <typename BufferTy, DataType DT> struct VectorRefImpl {
  BufferTy Buffer;
  uint StartOffset;
};

template <DataType DT> using VectorRef = VectorRefImpl<ByteAddressBuffer, DT>;

template <DataType DT>
using RWVectorRef = VectorRefImpl<RWByteAddressBuffer, DT>;

//
// Vector
//

template <typename T, int N, DataType DT> struct InterpretedVector {
  vector<T, N> Data;
};

template <DataType DT, typename T, int N>
InterpretedVector<T, N, DT> MakeInterpretedVector(vector<T, N> Vec) {
  InterpretedVector<T, N, DT> IV = {Vec};
  return IV;
}

//
// Mul
//

template <typename OutputElTy, typename InputElTy, int InputElCount,
          typename MatrixBufferTy, DataType InputDT, DataType MatrixDT,
          uint MatrixM, uint MatrixK, MatrixLayout MatrixLayout,
          bool MatrixTranspose>
vector<OutputElTy, MatrixM>
Mul(MatrixRefImpl<MatrixBufferTy, MatrixDT, MatrixM, MatrixK, MatrixLayout,
                  MatrixTranspose>
        Matrix,
    InterpretedVector<InputElTy, InputElCount, InputDT> InputVector) {

  vector<OutputElTy, MatrixM> OutputVector;

  __builtin_MatVecMul(
      /*out*/ OutputVector, details::IsUnsigned<OutputElTy>::Value,
      InputVector.Data, details::IsUnsigned<InputElTy>::Value, InputDT,
      Matrix.Buffer, Matrix.StartOffset, MatrixDT, MatrixM, MatrixK,
      MatrixLayout, MatrixTranspose, Matrix.Stride);

  return OutputVector;
}

//
// MulAdd
//

template <typename OutputElTy, typename InputElTy, int InputElCount,
          typename MatrixBufferTy, DataType InputDT, DataType MatrixDT,
          uint MatrixM, uint MatrixK, MatrixLayout MatrixLayout,
          bool MatrixTranspose, typename BiasVectorBufferTy,
          DataType BiasVectorDT>
vector<OutputElTy, MatrixM>
MulAdd(MatrixRefImpl<MatrixBufferTy, MatrixDT, MatrixM, MatrixK, MatrixLayout,
                     MatrixTranspose>
           Matrix,
       InterpretedVector<InputElTy, InputElCount, InputDT> InputVector,
       VectorRefImpl<BiasVectorBufferTy, BiasVectorDT> BiasVector) {

  vector<OutputElTy, MatrixM> OutputVector;

  __builtin_MatVecMulAdd(
      /*out*/ OutputVector, details::IsUnsigned<OutputElTy>::Value,
      InputVector.Data, details::IsUnsigned<InputElTy>::Value, InputDT,
      Matrix.Buffer, Matrix.StartOffset, MatrixDT, MatrixM, MatrixK,
      MatrixLayout, MatrixTranspose, Matrix.Stride, BiasVector.Buffer,
      BiasVector.StartOffset, BiasVectorDT);

  return OutputVector;
}

//
// OuterProductAccumulate
//

template <typename ElTy, int MatrixM, int MatrixN, DataType MatrixDT,
          MatrixLayout MatrixLayout>
void OuterProductAccumulate(
    vector<ElTy, MatrixM> InputVector1, vector<ElTy, MatrixN> InputVector2,
    RWMatrixRef<MatrixDT, MatrixM, MatrixN, MatrixLayout, false> Matrix) {
  __builtin_OuterProductAccumulate(InputVector1, InputVector2, Matrix.Buffer,
                                   Matrix.StartOffset, MatrixDT, MatrixLayout,
                                   Matrix.Stride);
}

//
// VectorAccumulate
//

template <typename ElTy, int ElCount>
void CoopVectorAccumulate(RWByteAddressBuffer Buffer, uint Offset,vector<ElTy, ElCount> InputVector) {
  __builtin_VectorAccumulate(InputVector, Buffer, Offset);
}
template <typename MatrixBuffer, typename BiasBuffer, typename InType, typename OutType, DataType MatRefType, DataType BiasRefType, uint in_dim, uint out_dim>
vector<OutType, out_dim> CoopMulAdd(
    MatrixBuffer mat_buffer,
    uint mat_offset,
    BiasBuffer bias_buffer,
    uint bias_offset,
    vector<InType, in_dim> input_vec
) {
    MatrixRefImpl<MatrixBuffer, MatRefType, out_dim, in_dim, MATRIX_LAYOUT_MUL_OPTIMAL, false> mat = {mat_buffer, mat_offset, 0};
    VectorRefImpl<BiasBuffer, BiasRefType> bias = {bias_buffer, bias_offset};
    return MulAdd<OutType>(mat, MakeInterpretedVector<MatRefType>(input_vec), bias);
}

template <typename MatrixBuffer,  typename InType, typename OutType, DataType MatRefType, uint in_dim, uint out_dim>
vector<OutType, out_dim> CoopMul(
    MatrixBuffer mat_buffer,
    uint mat_offset,
    vector<InType, in_dim> input_vec
) {
    MatrixRefImpl<MatrixBuffer, MatRefType, out_dim, in_dim, MATRIX_LAYOUT_MUL_OPTIMAL, false> mat = {mat_buffer, mat_offset, 0};
    return Mul<OutType>(mat, MakeInterpretedVector<MatRefType>(input_vec));
}
template <typename MatrixBuffer, typename ElTy, int MatrixM, int MatrixN, DataType MatrixDT>
void CoopOuterProductAccum(
  MatrixBuffer buffer,
  uint buffer_offset,
  vector<ElTy, MatrixM> InputVector1, vector<ElTy, MatrixN> InputVector2
){
  RWMatrixRef<MatrixDT, MatrixM, MatrixN, MATRIX_LAYOUT_OUTER_PRODUCT_OPTIMAL, false> Matrix = {buffer, buffer_offset, 0};
  OuterProductAccumulate<ElTy, MatrixM, MatrixN, MatrixDT, MATRIX_LAYOUT_OUTER_PRODUCT_OPTIMAL>(InputVector1, InputVector2, Matrix);
}
} // namespace linalg
} // namespace dx
#endif // SM 6.9 check and HV version check

#endif // __spirv__

//1

struct _CBType{
uint4 v;
};
[[vk::push_constant]] ConstantBuffer<_CBType> dsp_c:register(b0);
RWByteAddressBuffer _b0:register(u0);
[numthreads(256,1,1)]
void main(uint3 thdId:SV_GroupThreadId,uint3 dspId:SV_DispatchThreadID,uint3 grpId:SV_GroupId){
if(dspId.x>=dsp_c.v.x) return;
uint l1=(uint)0;
vector<float,8> l2;
float l3=(float)0;
uint l4=(uint)0;
float l5=(float)0;
uint l6=(uint)0;
float l7=(float)0;
uint l8=(uint)0;
float l9=(float)0;
uint l10=(uint)0;
float l11=(float)0;
uint l12=(uint)0;
float l13=(float)0;
uint l14=(uint)0;
float l15=(float)0;
uint l16=(uint)0;
float l17=(float)0;
uint l18=(uint)0;
l3=0x1.0000000000000p+0f;
l4=0u;
l2[l4]=l3;
l5=0x1.0000000000000p+1f;
l6=1u;
l2[l6]=l5;
l7=0x1.8000000000000p+1f;
l8=2u;
l2[l8]=l7;
l9=0x1.0000000000000p+2f;
l10=3u;
l2[l10]=l9;
l11=0x1.4000000000000p+2f;
l12=4u;
l2[l12]=l11;
l13=0x1.8000000000000p+2f;
l14=5u;
l2[l14]=l13;
l15=0x1.c000000000000p+2f;
l16=6u;
l2[l16]=l15;
l17=0x1.0000000000000p+3f;
l18=7u;
l2[l18]=l17;
l1=0u;
dx::linalg::CoopVectorAccumulate<float,8>(_b0,l1,l2);
}
