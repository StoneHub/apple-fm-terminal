#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"
swift build -c release --scratch-path build/swift
python3 scripts/stage.py
if [ "${1:-}" = --build-only ]; then exit 0; fi
exec ./install.sh --directory "$repo_dir/build/package" "$@"
