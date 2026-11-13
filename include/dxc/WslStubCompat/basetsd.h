///////////////////////////////////////////////////////////////////////////////
// dxc/WslStubCompat/basetsd.h
//
// Compatibility stand-in for DirectX-Headers' include/wsl/stubs/basetsd.h.
//
// Non-Windows builds take the Windows base types (ULONG, GUID, HRESULT,
// IUnknown, __uuidof, ...) from dxc/WinAdapter.h.  DirectX-Headers supplies a
// second, independent implementation of the same names in include/wsl/stubs,
// which DXC puts on the include path so that the D3D headers can resolve their
// <basetsd.h>/<rpcndr.h>/<unknwnbase.h> includes.  Previously that stub
// cooperated with WinAdapter.h through a family of DXC_*_DEFINED macros; newer
// DirectX-Headers revisions define the types unconditionally, so including both
// layers in one translation unit produces conflicting typedefs and redefinitions
// (ULONG, BOOL, LONG, GUID, HRESULT, LARGE_INTEGER, STATSTG, IUnknown, __uuidof).
//
// The three headers here live in a directory placed ahead of
// include/wsl/stubs on the include path (see CMakeLists.txt), so the D3D
// headers get their Win32 declarations from WinAdapter.h - the same layer the
// rest of DXC uses - and only one definition of each name is ever seen.
//
// Keep this header free of type definitions: WinAdapter.h owns them.
//
///////////////////////////////////////////////////////////////////////////////

#pragma once

#include "dxc/WinAdapter.h"

// DirectX-Headers' stub basetsd.h defines this to let the IDL-generated D3D
// headers spell declarations such as
//   typedef interface ID3D10Blob ID3D10Blob;
// D3DReflection.h defines it right before including d3d12shader.h; mirror it
// here so the D3D headers also work when included through another path.
#ifndef interface
#define interface struct
#endif
