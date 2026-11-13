///////////////////////////////////////////////////////////////////////////////
// dxc/WslStubCompat/rpcndr.h
//
// Compatibility stand-in for DirectX-Headers' include/wsl/stubs/rpcndr.h.
// See dxc/WslStubCompat/basetsd.h for the rationale.
//
// The real stub header pulls in the duplicate Win32 type layer and installs a
// template-based __uuidof that replaces the one from dxc/WinAdapter.h.  DXC
// relies on WinAdapter.h's emulation (for example
// IsEqualIID(__uuidof(ID3D12ShaderReflection), iid) in DxilContainerReflection),
// so this shim deliberately provides only the bookkeeping the IDL-generated
// headers check for.
//
///////////////////////////////////////////////////////////////////////////////

#pragma once

#include "basetsd.h"

// d3dcommon.h and friends verify the presence and level of this macro and
// #error out without it.  DirectX-Headers' stub defines it with no value.
#ifndef __RPCNDR_H_VERSION__
#define __RPCNDR_H_VERSION__
#endif

#ifdef CONST_VTABLE
#define CONST_VTBL const
#else
#define CONST_VTBL
#endif
