///////////////////////////////////////////////////////////////////////////////
// dxc/WslStubCompat/unknwnbase.h
//
// Compatibility stand-in for DirectX-Headers' include/wsl/stubs/unknwnbase.h.
// See dxc/WslStubCompat/basetsd.h for the rationale.
//
// The real stub header declares a C-style IUnknown with an explicit lpVtbl
// member, which conflicts with the C++ IUnknown that dxc/WinAdapter.h provides
// and that DXC's own COM interfaces derive from.  WinAdapter.h's IUnknown is the
// one the D3D reflection interfaces in d3d12shader.h must inherit, so nothing
// beyond the base layer is needed here.
//
///////////////////////////////////////////////////////////////////////////////

#pragma once

#include "basetsd.h"
