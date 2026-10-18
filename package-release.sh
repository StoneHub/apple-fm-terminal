#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$repo_dir"
./scripts/build-install.sh --build-only
if [ -n "${APPLE_FM_SIGN_IDENTITY:-}" ]; then
  python3 scripts/sign-payload.py build/package
fi
version=$(tr -d '[:space:]' < VERSION)
dist_dir=${1:-"$repo_dir/dist"}
mkdir -p "$dist_dir"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/apple-fm-package.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
COPYFILE_DISABLE=1 cp -R build/package "$tmp_dir/apple-fm-terminal-$version"
# BSD tar otherwise turns macOS extended attributes into AppleDouble entries.
# Exclude existing sidecars too, including debris in an older staging folder.
COPYFILE_DISABLE=1 tar --exclude '._*' --exclude '.DS_Store' -czf "$dist_dir/apple-fm-terminal-$version.tar.gz" -C "$tmp_dir" "apple-fm-terminal-$version"
cp "$dist_dir/apple-fm-terminal-$version.tar.gz" "$dist_dir/apple-fm-terminal.tar.gz"
cp install.sh "$dist_dir/install.sh"
(cd "$dist_dir" && shasum -a 256 "apple-fm-terminal-$version.tar.gz" apple-fm-terminal.tar.gz install.sh > SHA256SUMS)
printf 'Created local package in %s. Publication is separate.\n' "$dist_dir"
