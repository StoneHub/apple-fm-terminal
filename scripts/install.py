#!/usr/bin/env python3
"""Copy the package payload, then run its normal install wizard."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

def metadata_path(path):
    return any(part.startswith('._') or part == '.DS_Store' for part in path.parts)


def clean_metadata(target, inventory):
    """Remove only real AppleDouble sidecars of this package's owned paths."""
    owned = set()
    for relative in inventory:
        path = Path(relative)
        if path.is_absolute() or '..' in path.parts:
            continue
        owned.add(path)
        owned.update(parent for parent in path.parents if parent != Path('.'))
    for relative in owned:
        sidecar = target / relative.with_name('._' + relative.name)
        if sidecar.is_symlink() or not sidecar.is_file():
            continue
        with sidecar.open('rb') as stream:
            apple_double = stream.read(4) == b'\x00\x05\x16\x07'
        if apple_double:
            sidecar.unlink()


def main():
    source = Path(sys.argv[1]).resolve()
    target = Path(sys.argv[2]).expanduser().resolve()
    yes = "--yes" in sys.argv[3:]
    if not (source/"apple-fm-terminal-model").is_file():
        raise ValueError("This archive contains only legacy autocomplete. Build the Terminal Ask package before installing it.")
    link = Path.home()/".local/bin/apple-fm-terminal"
    if (link.exists() or link.is_symlink()) and (not link.is_symlink() or link.resolve() != target/"apple-fm-terminal"):
        raise ValueError(str(link) + " belongs to another install; it was not changed.")
    target.mkdir(parents=True, exist_ok=True)
    inventory = []
    for file in source.rglob('*'):
        relative = file.relative_to(source)
        if metadata_path(relative) or not file.is_file(): continue
        dest = target/relative
        inventory.append(str(relative))
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists() and dest.read_bytes() == file.read_bytes(): continue
        descriptor, staged = tempfile.mkstemp(prefix=".install-", dir=dest.parent)
        os.close(descriptor)
        try:
            shutil.copy2(file, staged)
            os.replace(staged, dest)
        finally:
            if os.path.exists(staged): os.unlink(staged)
    clean_metadata(target, inventory)
    (target/"installed-files.json").write_text(json.dumps(inventory))
    link.parent.mkdir(parents=True, exist_ok=True)
    if not link.is_symlink(): link.symlink_to(target/"apple-fm-terminal")
    print("Installed package:", target, flush=True)
    interpreter = target/"runtime/bin/python3"
    if not interpreter.is_file(): interpreter = Path(sys.executable)  # source/test fixtures
    command = [str(interpreter), "-I", "-B", str(target/"scripts/management.py"), "setup"]
    if yes: command.append("--yes")
    return subprocess.call(command)

if __name__ == "__main__":
    try: sys.exit(main())
    except (ValueError, OSError) as error:
        print("Apple FM:", error, file=sys.stderr)
        sys.exit(1)
