#!/usr/bin/env python3
"""Build DirectXShaderCompiler with CMake.

This script configures the project using the DXC PredefinedParams CMake cache
script, disables test targets that require extra dependencies (TAEF, gtest),
builds a set of common targets, and verifies that the expected binaries exist.
"""

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

if sys.platform == "win32":
    import ctypes
    import winreg


def _expand_registry_string(value: str) -> str:
    """Expand a REG_EXPAND_SZ value using the Windows API.

    ``os.path.expandvars`` only expands against the current process
    environment, which may be stale.  The Windows API
    ``ExpandEnvironmentStringsW`` performs a fresh expansion against
    the *system* and *user* environment blocks, giving the correct
    result even for variables that were changed externally.
    """
    if "%" not in value:
        return value
    try:
        nchars = ctypes.windll.kernel32.ExpandEnvironmentStringsW(value, None, 0)
        if nchars == 0:
            return value
        buf = ctypes.create_unicode_buffer(nchars)
        ctypes.windll.kernel32.ExpandEnvironmentStringsW(value, buf, nchars)
        return buf.value
    except Exception:
        return os.path.expandvars(value)


def _read_registry_value(hive: int, subkey: str, name: str):
    """Read a named value from the registry.

    Returns ``(value, reg_type)``.  *value* may be ``None`` when the
    value does not exist or cannot be read.  *reg_type* is the Windows
    registry type constant (e.g. ``winreg.REG_SZ``).
    """
    try:
        with winreg.OpenKey(hive, subkey, 0, winreg.KEY_READ) as key:
            val, reg_type = winreg.QueryValueEx(key, name)
            if isinstance(val, str):
                return val, reg_type
            return None, None
    except (FileNotFoundError, OSError):
        return None, None


def _merge_dedup_paths(*sources: str) -> str:
    """Merge semicolon-separated sources, deduplicating case-insensitively."""
    seen: set[str] = set()
    merged: list[str] = []
    for src in sources:
        for part in src.split(";"):
            part = part.strip()
            if part and part.lower() not in seen:
                seen.add(part.lower())
                merged.append(part)
    return ";".join(merged)


def refresh_windows_env() -> None:
    """Refresh ``os.environ["PATH"]`` and ``os.environ["PATHEXT"]``
    from the Windows registry.

    Reads both the system (HKLM) and user (HKCU) values, expands
    REG_EXPAND_SZ entries via the Windows API, and merges them into the
    current process environment.

    After calling this function, ``shutil.which`` and ``subprocess.Popen``
    can locate binaries installed by external package managers (WinGet,
    MSI, etc.) without restarting the process.
    """
    if sys.platform != "win32":
        return

    # --- PATH ---
    sys_val, sys_type = _read_registry_value(
        winreg.HKEY_LOCAL_MACHINE,
        r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
        "Path",
    )
    usr_val, usr_type = _read_registry_value(
        winreg.HKEY_CURRENT_USER,
        r"Environment",
        "Path",
    )

    path_parts: list[str] = []
    if sys_val:
        if sys_type == winreg.REG_EXPAND_SZ:
            sys_val = _expand_registry_string(sys_val)
        path_parts.append(sys_val)
    if usr_val:
        if usr_type == winreg.REG_EXPAND_SZ:
            usr_val = _expand_registry_string(usr_val)
        path_parts.append(usr_val)

    if path_parts:
        os.environ["PATH"] = _merge_dedup_paths(*path_parts)

    # --- PATHEXT ---
    sys_val, sys_type = _read_registry_value(
        winreg.HKEY_LOCAL_MACHINE,
        r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
        "PATHEXT",
    )
    usr_val, usr_type = _read_registry_value(
        winreg.HKEY_CURRENT_USER,
        r"Environment",
        "PATHEXT",
    )

    pathext_parts: list[str] = []
    if sys_val:
        if sys_type == winreg.REG_EXPAND_SZ:
            sys_val = _expand_registry_string(sys_val)
        pathext_parts.append(sys_val)
    if usr_val:
        if usr_type == winreg.REG_EXPAND_SZ:
            usr_val = _expand_registry_string(usr_val)
        pathext_parts.append(usr_val)

    if pathext_parts:
        os.environ["PATHEXT"] = _merge_dedup_paths(*pathext_parts)


def run(cmd, **kwargs):
    """Run a command and print it."""
    print("\n>>>", " ".join(str(c) for c in cmd), flush=True)
    subprocess.run(cmd, check=True, **kwargs)


def find_vswhere():
    """Locate ``vswhere.exe`` or download it if necessary.

    Returns the absolute path to ``vswhere.exe``, or ``None`` if it cannot
    be located and downloading fails.
    """
    # Check PATH first.
    vswhere = shutil.which("vswhere")
    if vswhere:
        return Path(vswhere).resolve()

    # Standard installer location.
    standard = Path(
        os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    ) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
    if standard.exists():
        return standard

    # Try to download a stable copy into a local cache.
    cache_dir = Path(__file__).resolve().parent / ".build_cache"
    cache_dir.mkdir(exist_ok=True)
    cached = cache_dir / "vswhere.exe"
    if cached.exists():
        return cached

    vswhere_version = "3.1.7"
    url = (
        f"https://github.com/microsoft/vswhere/releases/download/"
        f"{vswhere_version}/vswhere.exe"
    )
    try:
        import urllib.request

        print(f"Downloading vswhere.exe from {url}...")
        urllib.request.urlretrieve(url, cached)
        return cached
    except Exception as e:
        print(f"WARNING: failed to download vswhere.exe: {e}", file=sys.stderr)
        return None


def find_msvc(version, pattern):
    """Find MSVC/Visual Studio installation paths using ``vswhere``.

    ``version`` may be ``None`` (latest), ``2019``/``16``, or ``2022``/``17``.
    ``pattern`` is a file search pattern such as ``**/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe``.
    Returns a list of matching paths sorted by version, or ``None`` on failure.
    If ``version`` is specified, returns only the single best match.
    """
    vswhere = find_vswhere()
    if vswhere is None:
        return None

    if version is None:
        version_args = []
    elif version == 2019 or version == 16:
        version_args = ["-version", "[16.0,17.0)"]
    elif version == 2022 or version == 17:
        version_args = ["-version", "[17.0,18.0)"]
    else:
        print(f"WARNING: unsupported MSVC version {version}; using latest", file=sys.stderr)
        version_args = ["-latest"]

    args = [
        str(vswhere),
        "-format", "json",
        "-utf8",
        "-nologo",
        "-sort",
        "-products", "*",
        "-find", pattern,
    ] + version_args

    try:
        output = subprocess.check_output(args)
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"WARNING: vswhere failed: {e}", file=sys.stderr)
        return None

    try:
        results = json.loads(output.decode("utf-8"))
    except json.JSONDecodeError as e:
        print(f"WARNING: failed to parse vswhere output: {e}", file=sys.stderr)
        return None

    if not results:
        return None

    def parse_msvc_version_from_path(path):
        try:
            path = path.replace("\\", "/").lower().replace(pattern.lower(), "")
            parts = [p for p in path.split("/") if p]
            return [int(x) for x in parts[-1].split(".")]
        except Exception:
            return [0, 0, 0]

    results = [p.replace("\\", "/") for p in results]
    results = sorted(results, key=parse_msvc_version_from_path)
    if version is None:
        return results
    return results[-1]


def find_vcvars_bat(version):
    """Return the path to ``vcvars64.bat`` for the requested VS version.

    ``version`` may be ``None`` (latest), ``2019``/``16``, or ``2022``/``17``.
    Returns ``None`` if not found.
    """
    vcvars = find_msvc(version, "**/Auxiliary/Build/vcvars64.bat")
    if vcvars is None:
        return None
    if isinstance(vcvars, list):
        vcvars = vcvars[0]
    return Path(vcvars)


def load_vcvars_env(version):
    """Load the MSVC environment variables from ``vcvars64.bat``.

    ``version`` may be ``None`` (latest), ``2019``/``16``, or ``2022``/``17``.
    Returns a dictionary of environment variables, or ``None`` if loading fails.
    """
    vcvars = find_vcvars_bat(version)
    if vcvars is None:
        return None

    try:
        output = subprocess.check_output(
            [str(vcvars), "&&", sys.executable, "-c",
             "import os; import json; print('[[ENVIRON]] =', json.dumps(dict(os.environ)))"],
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"WARNING: failed to run vcvars64.bat: {e}", file=sys.stderr)
        return None

    try:
        text = output.decode("utf-8")
        marker = "[[ENVIRON]] = "
        idx = text.rfind(marker)
        if idx < 0:
            print("WARNING: vcvars environment marker not found", file=sys.stderr)
            return None
        env = json.loads(text[idx + len(marker):])
    except json.JSONDecodeError as e:
        print(f"WARNING: failed to parse vcvars environment: {e}", file=sys.stderr)
        return None

    # vcvars64.bat does not put the DIA SDK on INCLUDE/LIB, but DXC needs it.
    # vcvars64.bat is at <VS root>/VC/Auxiliary/Build/vcvars64.bat.
    vs_root = vcvars.parent.parent.parent.parent
    dia_sdk = vs_root / "DIA SDK"
    if dia_sdk.exists():
        include_dirs = [str(dia_sdk / "include")]
        lib_dirs = [str(dia_sdk / "lib" / "amd64")]
        if env.get("INCLUDE"):
            env["INCLUDE"] = ";".join(include_dirs + env["INCLUDE"].split(";"))
        else:
            env["INCLUDE"] = ";".join(include_dirs)
        if env.get("LIB"):
            env["LIB"] = ";".join(lib_dirs + env["LIB"].split(";"))
        else:
            env["LIB"] = ";".join(lib_dirs)

    return env


def find_windows_sdk_bin_dir():
    """Return the x64 Windows SDK bin directory, or None if not found.

    The Ninja generator on Windows does not set up the Visual Studio
    environment automatically, so tools such as ``mc.exe``, ``rc.exe`` and
    ``mt.exe`` must be available on ``PATH``.
    """
    sdk_root = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"))
    sdk_bin = sdk_root / "Windows Kits" / "10" / "bin"
    if not sdk_bin.exists():
        return None

    versions = sorted(
        (d for d in sdk_bin.iterdir() if d.is_dir() and d.name[0].isdigit()),
        reverse=True,
    )
    for version in versions:
        candidate = version / "x64"
        if (candidate / "mc.exe").exists():
            return candidate
    return None


def main(argv=None):
    if sys.platform == "win32":
        refresh_windows_env()

    parser = argparse.ArgumentParser(
        description="Configure and build DirectXShaderCompiler with CMake."
    )
    parser.add_argument(
        "--build-dir",
        default="build",
        help="Build directory, relative to the repository root (default: build).",
    )
    parser.add_argument(
        "--build-type",
        default="Release",
        choices=["Release", "Debug", "RelWithDebInfo", "MinSizeRel"],
        help="CMake build type (default: Release).",
    )
    parser.add_argument(
        "--generator",
        default=None,
        help="CMake generator (default: Ninja). Only Ninja is supported.",
    )
    parser.add_argument(
        "--targets",
        default="dxc,dxcompiler,dxv,dxildll",
        help="Comma-separated list of CMake targets to build (default: dxc,dxcompiler,dxv,dxildll).",
    )
    parser.add_argument(
        "--jobs",
        "-j",
        type=int,
        default=None,
        help="Number of parallel build jobs.",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Remove the build directory before configuring.",
    )
    parser.add_argument(
        "-rebuild",
        action="store_true",
        default=False,
        help="Force CMake reconfigure even if the build directory is already configured.",
    )
    parser.add_argument(
        "--enable-spirv-codegen",
        dest="enable_spirv_codegen",
        action="store_true",
        default=True,
        help="Enable SPIR-V code generation (default).",
    )
    parser.add_argument(
        "--disable-spirv-codegen",
        dest="enable_spirv_codegen",
        action="store_false",
        help="Disable SPIR-V code generation.",
    )
    parser.add_argument(
        "--spirv-build-tests",
        action="store_true",
        default=False,
        help="Build SPIR-V tests (default: False).",
    )
    parser.add_argument(
        "--coverage",
        action="store_true",
        default=False,
        help="Enable DXC code coverage instrumentation (default: False).",
    )
    parser.add_argument(
        "--parallel-link-jobs",
        type=int,
        default=None,
        help="Limit concurrent link jobs (Ninja only).",
    )
    parser.add_argument(
        "--parallel-compile-jobs",
        type=int,
        default=None,
        help="Limit concurrent compile jobs (Ninja only).",
    )
    parser.add_argument(
        "--werror",
        action="store_true",
        default=False,
        help="Treat warnings as errors (default: False).",
    )
    parser.add_argument(
        "--use-lld",
        action="store_true",
        default=False,
        help="Use the LLD linker (default: False).",
    )
    parser.add_argument(
        "--sanitizer",
        default=None,
        help="Enable sanitizers (e.g. 'Address;Undefined').",
    )
    parser.add_argument(
        "--enable-libcxx",
        action="store_true",
        default=False,
        help="Use libc++ (default: False).",
    )
    parser.add_argument(
        "--split-dwarf",
        action="store_true",
        default=False,
        help="Enable split DWARF for faster linking (default: False).",
    )
    parser.add_argument(
        "--vs-version",
        default=None,
        choices=["2019", "2022", "latest"],
        help=(
            "Visual Studio version to use on Windows (default: latest). "
            "Also accepts numeric years 2019/2022 or 'latest'."
        ),
    )
    args = parser.parse_args(argv)

    repo_root = Path(__file__).resolve().parent
    build_dir = (repo_root / args.build_dir).resolve()
    cache_script = repo_root / "cmake" / "caches" / "PredefinedParams.cmake"

    if not cache_script.exists():
        print(f"ERROR: DXC cache script not found: {cache_script}", file=sys.stderr)
        return 1

    if (args.clean or args.rebuild) and build_dir.exists():
        print(f"Removing existing build directory: {build_dir}")
        shutil.rmtree(build_dir)

    # Determine whether we need to run CMake configure.
    # If the build directory already has a CMake cache, skip configure
    # and go straight to incremental compile.
    cache_file = build_dir / "CMakeCache.txt"
    needs_configure = not cache_file.exists() or args.rebuild
    if not args.clean and not args.rebuild and cache_file.exists():
        print(
            "Build directory already configured; skipping CMake configure "
            "and proceeding to incremental compile."
        )

    generator = args.generator if args.generator is not None else "Ninja"

    vs_version = None if args.vs_version in (None, "latest") else int(args.vs_version)

    if generator != "Ninja":
        print(
            f"ERROR: Only the Ninja generator is supported, got '{generator}'.",
            file=sys.stderr,
        )
        return 1

    if shutil.which("ninja") is None:
        print(
            "ERROR: ninja was not found on PATH. Install Ninja and add it to PATH.",
            file=sys.stderr,
        )
        return 1

    if platform.system() == "Windows":
        cl_path = find_msvc(vs_version, "**/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe")
        if cl_path is None:
            print(
                "ERROR: MSVC cl.exe was not found. Install Visual Studio with the "
                "Desktop development with C++ workload.",
                file=sys.stderr,
            )
            return 1
        if isinstance(cl_path, list):
            cl_path = cl_path[-1]
        cl_path = Path(cl_path.replace("/", "\\"))
        print(f"Using MSVC compiler: {cl_path}")
    else:
        cl_path = None

    configure_cmd = [
        "cmake",
        "-S", str(repo_root),
        "-B", str(build_dir),
        "-C", str(cache_script),
        "-G", generator,
        "-DCMAKE_BUILD_TYPE=" + args.build_type,
        "-DHLSL_INCLUDE_TESTS=OFF",
        "-DSPIRV_BUILD_TESTS=OFF",
        "-DLLVM_INCLUDE_TESTS=OFF",
        "-DCLANG_INCLUDE_TESTS=OFF",
    ]
    if cl_path is not None:
        configure_cmd.append(f"-DCMAKE_C_COMPILER={cl_path}")
        configure_cmd.append(f"-DCMAKE_CXX_COMPILER={cl_path}")
    if not args.enable_spirv_codegen:
        configure_cmd.append("-DENABLE_SPIRV_CODEGEN=OFF")
    if args.spirv_build_tests:
        configure_cmd.append("-DSPIRV_BUILD_TESTS=ON")
    if args.coverage:
        configure_cmd.append("-DDXC_COVERAGE=On")
    if args.parallel_link_jobs is not None:
        configure_cmd.append(f"-DLLVM_PARALLEL_LINK_JOBS={args.parallel_link_jobs}")
    if args.parallel_compile_jobs is not None:
        configure_cmd.append(f"-DLLVM_PARALLEL_COMPILE_JOBS={args.parallel_compile_jobs}")
    if args.werror:
        configure_cmd.append("-DLLVM_ENABLE_WERROR=On")
    if args.use_lld:
        configure_cmd.append("-DLLVM_USE_LINKER=lld")
    if args.sanitizer:
        configure_cmd.append(f"-DLLVM_USE_SANITIZER={args.sanitizer}")
    if args.enable_libcxx:
        configure_cmd.append("-DLLVM_ENABLE_LIBCXX=On")
    if args.split_dwarf:
        configure_cmd.append("-DLLVM_USE_SPLIT_DWARF=On")

    if platform.system() == "Windows":
        if not os.environ.get("VSCMD_VER"):
            vs_env = load_vcvars_env(vs_version)
            if vs_env:
                for key, value in vs_env.items():
                    os.environ[key] = value
                print(f"Loaded MSVC environment from vcvars64.bat (VS {vs_version or 'latest'})")
            else:
                # Fall back to adding just the Windows SDK tools to PATH.
                sdk_bin = find_windows_sdk_bin_dir()
                if sdk_bin and str(sdk_bin) not in os.environ.get("PATH", ""):
                    os.environ["PATH"] = str(sdk_bin) + os.pathsep + os.environ.get("PATH", "")
                    print(f"Added Windows SDK tools to PATH: {sdk_bin}")

    if needs_configure:
        run(configure_cmd)
    else:
        print("Skipping configure (use --clean to force a full rebuild).")

    targets = [t.strip() for t in args.targets.split(",") if t.strip()]
    if not targets:
        print("ERROR: no targets specified", file=sys.stderr)
        return 1

    # The Ninja generator on Windows does not automatically order the ETW
    # header generation before consumers that include dxcetw.h. Build the
    # DxcEtw target first when it is not already requested.
    if platform.system() == "Windows" and "DxcEtw" not in targets:
        targets.insert(0, "DxcEtw")

    for target in targets:
        build_cmd = [
            "cmake",
            "--build", str(build_dir),
            "--config", args.build_type,
            "--target", target,
        ]
        if args.jobs is not None:
            build_cmd.extend(["-j", str(args.jobs)])
        run(build_cmd)

    # Ninja is a single-config generator, so binaries land under <build>/bin.
    bin_dir = build_dir / "bin"
    print("\n=== Verifying generated binaries ===")
    target_binaries = {
        "dxc": bin_dir / "dxc.exe",
        "dxv": bin_dir / "dxv.exe",
        "dxcompiler": bin_dir / "dxcompiler.dll",
        "dxilconv": bin_dir / "dxilconv.dll",
        "dxildll": bin_dir / "dxil.dll",
    }

    missing = []
    for target in targets:
        path = target_binaries.get(target)
        if path is None:
            continue
        if path.exists():
            size = path.stat().st_size
            print(f"OK  {target}: {path} ({size} bytes)")
        else:
            print(f"MISSING {target}: {path}")
            missing.append(target)

    if missing:
        print(f"\nERROR: missing binaries: {', '.join(missing)}", file=sys.stderr)
        return 1

    print("\nBuild completed successfully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
