#!/usr/bin/env python3
"""Stage this task's installable payload under build/package."""
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
destination = root/"build/package"
destination.mkdir(parents=True, exist_ok=True)
files = ["apple-fm-terminal", "terminal-session", "shell/help.zsh", "scripts/management.py", "scripts/install.py", "install.sh", "README.md", "STATUS.md", "VERSION"]
for relative in files:
    target = destination/relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root/relative, target)
binary_dir = subprocess.check_output(["swift", "build", "-c", "release", "--scratch-path", str(root/"build/swift"), "--show-bin-path"], text=True, cwd=root).strip()
shutil.copy2(Path(binary_dir)/"apple-fm-terminal-model", destination/"apple-fm-terminal-model")
print(destination)
