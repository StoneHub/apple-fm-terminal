#!/usr/bin/env python3
"""Stage this task's installable payload under build/package."""
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
destination = root/"build/package"
if destination.exists(): shutil.rmtree(destination)
destination.mkdir(parents=True)
files = ["Install.command", "apple-fm-terminal", "terminal-session", "shell/help.zsh", "scripts/management.py", "scripts/install.py", "install.sh", "README.md", "STATUS.md", "VERSION", "docs/preview-release.md", "docs/preview-release-notes.md"]
for relative in files:
    target = destination/relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root/relative, target)
binary_dir = subprocess.check_output(["swift", "build", "-c", "release", "--scratch-path", str(root/"build/swift"), "--show-bin-path"], text=True, cwd=root).strip()
shutil.copy2(Path(binary_dir)/"apple-fm-terminal-model", destination/"apple-fm-terminal-model")
print(destination)

subprocess.run(["python3", str(root/"scripts/bundle-runtime.py")], check=True)
