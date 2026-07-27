#!/usr/bin/env python3
"""Generate a compile_commands.json file for DXC LSP support.

This script configures the DirectXShaderCompiler project with CMake, enabling
CMAKE_EXPORT_COMPILE_COMMANDS, and writes the resulting database to
.vscode/compile_commands.json so VS Code language servers such as clangd can
use it. It only configures the project; it does not build any targets.

The default generator is Ninja because it reliably produces
compile_commands.json. On Windows, if the MSVC compiler (cl.exe) is not already
available, the script automatically locates Visual Studio with vswhere and
loads the VC environment before configuring.
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


def find_vs_vcvars():
    """Return the path to vcvarsall.bat for the newest VS installation, if any."""
    program_files_x86 = os.environ.get("ProgramFiles(x86)")
    if not program_files_x86:
        return None
    vswhere = Path(program_files_x86) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
    if not vswhere.exists():
        return None
    try:
        result = subprocess.run(
            [
                str(vswhere),
                "-latest",
                "-products", "*",
                "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                "-property", "installationPath",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        install_path = result.stdout.strip().splitlines()[0]
        vcvars = Path(install_path) / "VC" / "Auxiliary" / "Build" / "vcvarsall.bat"
        if vcvars.exists():
            return str(vcvars)
    except (subprocess.CalledProcessError, IndexError):
        pass
    return None


def setup_msvc_env(arch="x64"):
    """Update os.environ with the MSVC environment for the requested architecture.

    Returns True if the environment was successfully loaded.
    """
    vcvars = find_vs_vcvars()
    if not vcvars:
        return False

    # Run vcvarsall.bat and capture the resulting environment.
    cmd = f'"{vcvars}" {arch} && set'
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print(f"WARNING: failed to load VC environment: {e}", file=sys.stderr)
        return False

    for line in result.stdout.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ[key.upper()] = value
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Generate compile_commands.json for DXC LSP support."
    )
    parser.add_argument(
        "--build-dir",
        default="build-lsp",
        help="Build directory, relative to the repository root (default: build-lsp).",
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
        help="CMake generator (default: Ninja).",
    )
    parser.add_argument(
        "--arch",
        default="x64",
        help="MSVC architecture to use when loading VC environment (default: x64).",
    )
    parser.add_argument(
        "--output",
        default=".vscode/compile_commands.json",
        help="Destination for the generated compile_commands.json "
             "(default: .vscode/compile_commands.json).",
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

    cache_file = build_dir / "CMakeCache.txt"
    if cache_file.exists() and args.generator is None:
        # Pick up the generator from an existing configuration so we do not
        # conflict with it.
        with cache_file.open("r", encoding="utf-8", errors="ignore") as f:
            generator = "Ninja"
            for line in f:
                if line.startswith("CMAKE_GENERATOR:"):
                    generator = line.split("=", 1)[-1].strip()
                    break
    else:
        generator = args.generator if args.generator is not None else "Ninja"

    if generator.startswith("Visual Studio"):
        print(
            "WARNING: The Visual Studio generator does not reliably emit "
            "compile_commands.json. Consider using Ninja instead.",
            file=sys.stderr,
        )

    # On Windows with Ninja, ensure the MSVC toolchain is available so CMake's
    # host-triple detection succeeds.
    if platform.system() == "Windows" and "Ninja" in generator:
        cl_on_path = shutil.which("cl.exe") is not None
        if not cl_on_path:
            print("MSVC compiler not found on PATH; loading Visual Studio environment...")
            if not setup_msvc_env(args.arch):
                print(
                    "ERROR: unable to load the Visual Studio C++ environment. "
                    "Please run this script from a Developer Command Prompt for VS "
                    "or ensure vswhere.exe and Visual Studio are installed.",
                    file=sys.stderr,
                )
                return 1
            print("Visual Studio environment loaded.")

    configure_cmd = [
        "cmake",
        "-S", str(repo_root),
        "-B", str(build_dir),
        "-C", str(cache_script),
        "-G", generator,
        "-DCMAKE_BUILD_TYPE=" + args.build_type,
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
        "-DHLSL_INCLUDE_TESTS=OFF",
        "-DSPIRV_BUILD_TESTS=OFF",
        "-DLLVM_INCLUDE_TESTS=OFF",
        "-DCLANG_INCLUDE_TESTS=OFF",
    ]

    if not args.enable_spirv_codegen:
        configure_cmd.append("-DENABLE_SPIRV_CODEGEN=OFF")
    if args.spirv_build_tests:
        configure_cmd.append("-DSPIRV_BUILD_TESTS=ON")
    if args.coverage:
        configure_cmd.append("-DDXC_COVERAGE=On")
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

    run(configure_cmd)

    source_db = build_dir / "compile_commands.json"
    if not source_db.exists():
        print(f"ERROR: CMake did not generate {source_db}", file=sys.stderr)
        print(
            "This usually happens when using a generator that does not support "
            "CMAKE_EXPORT_COMPILE_COMMANDS (e.g. older Visual Studio generators). "
            "Re-run with --generator Ninja.",
            file=sys.stderr,
        )
        return 1

    output_path = repo_root / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Normalize paths to forward slashes for better cross-platform compatibility
    # with language servers.
    with source_db.open("r", encoding="utf-8") as f:
        commands = json.load(f)

    for entry in commands:
        if "directory" in entry:
            entry["directory"] = Path(entry["directory"]).as_posix()
        if "file" in entry:
            entry["file"] = Path(entry["file"]).as_posix()

    with output_path.open("w", encoding="utf-8") as f:
        json.dump(commands, f, indent=2)
        f.write("\n")

    print(f"\nWrote {len(commands)} compile commands to {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
