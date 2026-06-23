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


def run(cmd, **kwargs):
    """Run a command and print it."""
    print("\n>>>", " ".join(str(c) for c in cmd), flush=True)
    subprocess.run(cmd, check=True, **kwargs)


def find_clang():
    """Locate the LLVM Clang compiler executables on the current platform.

    Returns a ``(cc, cxx)`` tuple of absolute paths. On Windows, the
    clang-cl driver (``clang-cl.exe``) is used for both C and C++ so that
    Clang's MSVC-compatible command-line is used. On Unix-like systems,
    ``cc`` is ``clang`` and ``cxx`` is ``clang++`` when present in the same
    directory, otherwise the same path as ``cc``. Returns ``None`` if clang
    cannot be found on ``PATH``.
    """
    is_windows = platform.system() == "Windows"
    if is_windows:
        cc_name = "clang-cl.exe"
        cxx_name = "clang-cl.exe"
    else:
        cc_name = "clang"
        cxx_name = "clang++"

    cc = shutil.which(cc_name)
    if not cc:
        return None
    cc = Path(cc).resolve()

    cxx = cc.with_name(cxx_name)
    if not cxx.exists():
        cxx = cc
    return cc, cxx


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
        help="CMake generator (default: 'Visual Studio 17 2022' on Windows, Ninja otherwise).",
    )
    parser.add_argument(
        "--targets",
        default="dxc,dxcompiler,dxv,dxilconv",
        help="Comma-separated list of CMake targets to build (default: dxc,dxcompiler,dxv,dxilconv).",
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
        "--clang",
        default="auto",
        choices=["auto", "on", "off"],
        help=(
            "Use the LLVM Clang compiler. 'auto' uses Clang if it is found on "
            "PATH, 'on' requires Clang to be available, and 'off' disables it "
            "(default: auto)."
        ),
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

    if args.clean and build_dir.exists():
        print(f"Removing existing build directory: {build_dir}")
        shutil.rmtree(build_dir)

    generator_explicit = args.generator is not None
    generator = args.generator

    vs_version = None if args.vs_version in (None, "latest") else int(args.vs_version)

    if generator is None:
        if platform.system() == "Windows":
            # Detect the installed VS version rather than hard-coding 2022.
            vs_generators = {
                2022: "Visual Studio 17 2022",
                2019: "Visual Studio 16 2019",
            }
            if args.vs_version in vs_generators:
                requested_year = int(args.vs_version)
                if find_msvc(requested_year, "**/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe"):
                    generator = vs_generators[requested_year]
                    vs_version = requested_year
                else:
                    print(
                        f"WARNING: Visual Studio {requested_year} was requested but "
                        "not found; falling back to auto-detection",
                        file=sys.stderr,
                    )
            # Auto-detect the newest installed VS if not already set.
            if generator is None:
                for year in (2022, 2019):
                    cl_path = find_msvc(year, "**/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe")
                    if cl_path:
                        generator = vs_generators[year]
                        vs_version = year
                        break
            if generator is None:
                print(
                    "WARNING: could not detect a Visual Studio installation; "
                    "falling back to 'Visual Studio 17 2022'",
                    file=sys.stderr,
                )
                generator = "Visual Studio 17 2022"
        else:
            generator = "Ninja"

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
    if generator.startswith("Visual Studio"):
        configure_cmd.extend(["-T", "host=x64"])

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

    clang_paths = None
    if args.clang != "off":
        clang_paths = find_clang()
        if clang_paths is None:
            if args.clang == "on":
                print("ERROR: --clang=on requested but clang was not found on PATH", file=sys.stderr)
                return 1
        else:
            cc, cxx = clang_paths
            # The Visual Studio generator ignores CMAKE_C_COMPILER/
            # CMAKE_CXX_COMPILER; use Ninja so clang is actually invoked.
            if platform.system() == "Windows" and generator.startswith("Visual Studio"):
                if generator_explicit:
                    print(
                        "WARNING: --clang is used with the Visual Studio generator, "
                        "which ignores CMAKE_C_COMPILER. Use --generator Ninja to "
                        "compile with clang.",
                        file=sys.stderr,
                    )
                else:
                    if shutil.which("ninja") is None:
                        print(
                            "ERROR: --clang selected the Ninja generator, but ninja "
                            "was not found on PATH",
                            file=sys.stderr,
                        )
                        return 1
                    generator = "Ninja"
                    # Rebuild the configure command with the new generator.
                    configure_cmd[configure_cmd.index("-G") + 1] = generator
                    if "-T" in configure_cmd:
                        t_index = configure_cmd.index("-T")
                        configure_cmd.pop(t_index)
                        configure_cmd.pop(t_index)
                    print(f"Switched generator to Ninja for Clang: {cc}")
                    print(
                        "NOTE: DXC's Windows build assumes MSVC; building with "
                        "standalone clang on Windows may require DXC CMake fixes."
                    )

            configure_cmd.append(f"-DCMAKE_C_COMPILER={cc}")
            configure_cmd.append(f"-DCMAKE_CXX_COMPILER={cxx}")
            print(f"Using Clang compilers: C={cc}, CXX={cxx}")

    if platform.system() == "Windows" and generator == "Ninja":
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

    run(configure_cmd)

    targets = [t.strip() for t in args.targets.split(",") if t.strip()]
    if not targets:
        print("ERROR: no targets specified", file=sys.stderr)
        return 1

    # The Ninja generator on Windows does not automatically order the ETW
    # header generation before consumers that include dxcetw.h. Build the
    # DxcEtw target first when it is not already requested.
    if platform.system() == "Windows" and generator == "Ninja" and "DxcEtw" not in targets:
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

    # Visual Studio places binaries under <build>/<Config>/bin, while
    # single-config generators such as Ninja place them under <build>/bin.
    vs_bin_dir = build_dir / args.build_type / "bin"
    single_config_bin_dir = build_dir / "bin"
    bin_dir = vs_bin_dir if vs_bin_dir.exists() else single_config_bin_dir
    print("\n=== Verifying generated binaries ===")
    target_binaries = {
        "dxc": bin_dir / "dxc.exe",
        "dxv": bin_dir / "dxv.exe",
        "dxcompiler": bin_dir / "dxcompiler.dll",
        "dxilconv": bin_dir / "dxilconv.dll",
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
