#!/usr/bin/env python3
"""Copy DXC DLL files from build directories to local bin folders."""

import shutil
import sys
from pathlib import Path


def copy_dlls(src_dir: Path, dst_dir: Path) -> None:
    """Copy all .dll files from src_dir to dst_dir."""
    if not src_dir.exists():
        print(
            f"WARNING: Source directory does not exist, skipping: {src_dir}", file=sys.stderr)
        return

    dll_files = list(src_dir.glob("*.dll"))
    if not dll_files:
        print(f"WARNING: No .dll files found in: {src_dir}", file=sys.stderr)
        return

    dst_dir.mkdir(parents=True, exist_ok=True)

    for dll in dll_files:
        try:
            dest_path = dst_dir / dll.name
            shutil.copy2(dll, dest_path)
            print(f"Copied: {dll} -> {dest_path}")
        except Exception as e:
            print(f"ERROR: Failed to copy {dll}: {e}", file=sys.stderr)


def main() -> None:
    if len(sys.argv) < 2:
        print("ERROR: Destination path argument is required.", file=sys.stderr)
        return

    base_build = Path("build")
    base_dst = Path(sys.argv[1])

    copy_dlls(base_build / "bin", base_dst / 'bin' / "debug")
    copy_dlls(base_build / "bin", base_dst / 'bin' / "release")


if __name__ == "__main__":
    main()
