#!/usr/bin/env python3
"""Copy the package payload, then run its normal install wizard."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

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
        if not file.is_file(): continue
        relative = file.relative_to(source)
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
    (target/"installed-files.json").write_text(json.dumps(inventory))
    link.parent.mkdir(parents=True, exist_ok=True)
    if not link.is_symlink(): link.symlink_to(target/"apple-fm-terminal")
    print("Installed package:", target, flush=True)
    command = [sys.executable, str(target/"scripts/management.py"), "setup"]
    if yes: command.append("--yes")
    return subprocess.call(command)

if __name__ == "__main__":
    try: sys.exit(main())
    except (ValueError, OSError) as error:
        print("Apple FM:", error, file=sys.stderr)
        sys.exit(1)
