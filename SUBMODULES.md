# External submodules: the LuisaGroup redirects are intentional

**Do not revert this.** This file exists because a previous agent already reverted
the submodule update once (commit `8f2689c14591c06595f8d93d86064d6228310439`,
`Revert "update ext"`), and the fix that made the newer revisions usable landed
afterwards in `ee24c4715b0258c237d06b9b2fb82faee5d87708`. If you are looking at a
dirty `.gitmodules` or a submodule update that changes `external/*`, read this page
before touching anything.

The submodule URLs point at `https://github.com/LuisaGroup/*` on purpose, and the
pinned revisions are the LuisaGroup forks' `main`. Neither the URLs nor the pins are
an accident, a stale fork, or something to "clean up" back to the KhronosGroup /
microsoft upstreams.

## Current state

| submodule | URL in `.gitmodules` | pinned commit | description |
| --- | --- | --- | --- |
| `external/DirectX-Headers` | `https://github.com/LuisaGroup/DirectX-Headers` | `61c7718954ec73dbdd43c723240fe1a0452a3724` | `v1.608.2b-203-g61c7718`, "Update headers" |
| `external/SPIRV-Headers` | `https://github.com/LuisaGroup/SPIRV-Headers` | `6efe5ae6b7c6ad29da3f2cc3f164b9c3d72b78b1` | `v1.202609.0-11-g6efe5ae` |
| `external/SPIRV-Tools` | `https://github.com/LuisaGroup/SPIRV-Tools` | `c6bbc3aa899353b7cab3978b9098f9c78677d437` | `v2022.4-1483-gc6bbc3aa`, "Merge branch 'KhronosGroup:main' into main" |
| `external/googletest` | `https://github.com/google/googletest` | (declared, not checked out here) | left on upstream on purpose, see below |

`git submodule status` must print exactly these three lines, with **no** leading `+`
(worktree differs from the gitlink) and **no** leading `-` (not initialized):

```
 61c7718954ec73dbdd43c723240fe1a0452a3724 external/DirectX-Headers (v1.608.2b-203-g61c7718)
 6efe5ae6b7c6ad29da3f2cc3f164b9c3d72b78b1 external/SPIRV-Headers (v1.202609.0-11-g6efe5ae)
 c6bbc3aa899353b7cab3978b9098f9c78677d437 external/SPIRV-Tools (v2022.4-1483-gc6bbc3aa)
```

A leading `+` means somebody checked out a different revision without committing the
gitlink - either commit the new revision deliberately (see "Updating a submodule")
or restore it with `git submodule update`, but do not leave the tree half-updated.

## Why the URLs were redirected

1. **This repository is the LuisaGroup fork.** `origin` is
   `https://github.com/LuisaGroup/DirectXShaderCompiler`; the dependencies it builds
   against are pinned to the same org. Everything a build needs then has the same
   owner, and an upstream rename, transfer, force-push or branch rewrite cannot
   silently change what a commit hash means for us.
2. **The forks are not plain mirrors.** `LuisaGroup/SPIRV-Tools` `main` currently
   carries 27 commits beyond the shared history - extra optimization passes,
   cooperative-matrix operator support, an LCSSA/opt fix, Linux build fixes, `xmake`
   build files and the current upstream merge. The pinned revision `c6bbc3aa` *is* that
   fork `main`; its `upstream/main` comparison point is contained in the fork, while the
   fork-only patches are not present in upstream. Re-pointing the submodule at
   KhronosGroup would eventually drop LuisaGroup patches that this tree builds against.
3. **The forks are the place where a header can be patched if needed.**
   `LuisaGroup/DirectX-Headers` and `LuisaGroup/SPIRV-Headers` happen to be exact
   mirrors right now (`main` == upstream `main`, i.e. `61c7718` and `6efe5ae`), but
   they are redirected anyway so that a DXC-side workaround can be carried in the
   header project instead of being bolted onto this repository's CMake.
4. **Fresh clones keep working.** Every pinned hash is reachable from the LuisaGroup
   remote - at the time of writing each pin equals that fork's `main` - so
   `git submodule update --init` in a clean checkout resolves without touching GitHub's
   upstream projects. A pin that only exists in an upstream repository would break
   exactly that step, so **never pin a commit that the LuisaGroup fork does not have**.

## Why the older revisions must not come back

- `a1c961abe` ("update ext") bumped the three submodules to
  `61c7718` / `6efe5ae` / `3eb9e88e`.
- `8f2689c14` (`Revert "update ext"`) undid it and pinned the older
  `f0ac6ce` / `fef168c5` / `e36f0f9e`, because the newer DirectX-Headers rewrote
  `include/wsl/stubs` (for MinGW) and dropped the `DXC_*_DEFINED` escape hatches. Every
  non-Windows translation unit that reached `d3d12shader.h` then saw two definitions of
  `ULONG`, `BOOL`, `LONG`, `GUID`, `HRESULT`, `LARGE_INTEGER`, `STATSTG`, `IUnknown` and
  a template-based `__uuidof` that replaced the `dxc/WinAdapter.h` one, so
  `DxilContainerReflection.cpp`, `D3DReflectionDumper.cpp`, `D3DReflectionStrings.cpp`
  and `RDATDumper.cpp` stopped compiling.
- `ee24c4715` ("[linux] Fix non-Windows build with current DirectX-Headers") fixed the
  actual problem instead of downgrading: it added
  `include/dxc/WslStubCompat/{basetsd,rpcndr,unknwnbase}.h` and put that directory
  ahead of `external/DirectX-Headers/include/wsl/stubs` on the include path. WinAdapter.h
  keeps ownership of the Win32 types, DirectX-Headers only contributes the D3D
  declarations, and it still works with the older header revision because the shims
  shadow its stubs.

The pins in this tree and `include/dxc/WslStubCompat/` are a matched pair: the newer
headers need the shim, and the shim exists only to support these newer headers. Do not
revert either half alone.

## Rules for the next agent

- Do **not** change `.gitmodules` back to `KhronosGroup/SPIRV-Headers`,
  `KhronosGroup/SPIRV-Tools` or `microsoft/DirectX-Headers`, and do not "normalize"
  the LuisaGroup URLs away. The redirect is the point of this file.
- Do **not** reset the gitlinks to `f0ac6ce17822498ed2311f5374b08243bc0b16b1`
  (DirectX-Headers), `fef168c54ed2e37c314eb251806aaf9877f38465` (SPIRV-Headers) or
  `e36f0f9e7819d4575fe1e0396938a7312f2b5da6` (SPIRV-Tools). Those are the pre-fix
  revisions from the reverted commit.
- Do **not** delete `include/dxc/WslStubCompat/` or the `if (NOT WIN32)` include-order
  block in `CMakeLists.txt` next to the `external` `add_subdirectory`; that is the
  build-side half of this change.
- If a submodule update breaks the build, **fix forward** the way `ee24c4715` does
  (compatibility header, CMake include order, source-level adaptation). Do not
  downgrade the pin and do not redirect the URL.
- `external/googletest` intentionally stays on `https://github.com/google/googletest`:
  there is no LuisaGroup fork of it (GitHub returns `Repository not found` for
  `LuisaGroup/googletest`). It is declared in `.gitmodules` but not checked out in this
  tree, and the build directories here configure with `HLSL_INCLUDE_TESTS=OFF`. If a
  fork is ever created, redirect it here **and** update this document in the same
  commit.
- Locally, each submodule clone keeps `origin` = the LuisaGroup URL and an `upstream`
  remote = the original repository (`KhronosGroup/*`, `microsoft/DirectX-Headers`) for
  comparison only. `upstream` is local clone configuration and is not part of any
  commit - do not commit a submodule change that depends on it.

## Updating a submodule (safe procedure)

```bash
git submodule sync                                   # apply .gitmodules URLs to .git/config and submodule clones
git -C external/SPIRV-Tools fetch origin
git -C external/SPIRV-Tools checkout origin/main     # or an explicit fork branch/tag
git add external/SPIRV-Tools                         # record the new gitlink
```

Then, in the same commit:

1. Confirm `git submodule status` shows no `+`/`-` and that the new hash exists in the
   LuisaGroup remote (`git -C external/<name> merge-base --is-ancestor <sha> origin/main`,
   or simply `git ls-remote <LuisaGroup URL> refs/heads/main`).
2. Update the pin table at the top of this file.
3. Rebuild and smoke-test (see below). A submodule bump is a build change, not a
   bookkeeping change.

## Verification performed when this document was added

- `git submodule status`: all three submodules clean, every pin identical to that fork's
  `main` on the LuisaGroup remote.
- Windows, Release, MSVC 19.44 + Ninja (`build/`): `cmake --build build --target dxc`
  succeeds, including a forced recompile of the same four reflection translation units.
  Note that `cl.exe` takes its standard include paths from the environment, so this
  must be run from a VS developer prompt (`vcvars64.bat`); a plain shell fails with
  `fatal error C1083: cannot open include file: 'stdint.h'`, which is an environment
  problem, not a submodule problem.
- WSL2 Ubuntu, gcc 15 + Ninja (`build-wsl-release/`):
  `cmake --build build-wsl-release --target dxc` succeeds, and the four translation units
  named in `ee24c4715` were force-recompiled against the pinned DirectX-Headers and
  linked into `libdxcompiler.so` without conflicts:
  `lib/HLSL/DxilContainerReflection.cpp`, `lib/DxilContainer/D3DReflectionDumper.cpp`,
  `lib/DxilContainer/D3DReflectionStrings.cpp`, `lib/DxilContainer/RDATDumper.cpp`.
- `dxc -T ps_6_0 -spirv` on both builds emits the same 400-byte SPIR-V module, so the
  SPIRV-Headers/SPIRV-Tools pins link and run.
