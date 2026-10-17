#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$repo_dir"
./scripts/build-install.sh --build-only
version=$(tr -d '[:space:]' < VERSION)
dist_dir=${1:-"$repo_dir/dist"}
mkdir -p "$dist_dir"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/apple-fm-package.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
cp -R build/package "$tmp_dir/apple-fm-terminal-$version"
tar -czf "$dist_dir/apple-fm-terminal-$version.tar.gz" -C "$tmp_dir" "apple-fm-terminal-$version"
cp "$dist_dir/apple-fm-terminal-$version.tar.gz" "$dist_dir/apple-fm-terminal.tar.gz"
cp install.sh "$dist_dir/install.sh"
(cd "$dist_dir" && shasum -a 256 "apple-fm-terminal-$version.tar.gz" apple-fm-terminal.tar.gz install.sh > SHA256SUMS)
printf 'Created local package in %s. Publication is separate.\n' "$dist_dir"
