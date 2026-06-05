#!/usr/bin/env python3
"""Build DirectXShaderCompiler with CMake.

This script configures the project using the DXC PredefinedParams CMake cache
script, disables test targets that require extra dependencies (TAEF, gtest),
builds a set of common targets, and verifies that the expected binaries exist.
"""

import argparse
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

    generator = args.generator
    if generator is None:
        if platform.system() == "Windows":
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

    run(configure_cmd)

    targets = [t.strip() for t in args.targets.split(",") if t.strip()]
    if not targets:
        print("ERROR: no targets specified", file=sys.stderr)
        return 1

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

    bin_dir = build_dir / args.build_type / "bin"
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
