#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
git -C "$repo_dir" diff --quiet && git -C "$repo_dir" diff --cached --quiet || {
  echo 'Refusing to package a tree with tracked changes; commit first.' >&2
  exit 1
}
version=$(tr -d '[:space:]' < "$repo_dir/VERSION")
case "$version" in
  ''|*[!0-9.]*|.*|*.) echo "Invalid VERSION: $version" >&2; exit 1 ;;
esac
dist_dir=${1:-"$repo_dir/dist"}
mkdir -p "$dist_dir"
archive="$dist_dir/apple-fm-terminal-$version.tar.gz"
latest_archive="$dist_dir/apple-fm-terminal.tar.gz"
checksum="$dist_dir/SHA256SUMS"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/apple-fm-terminal-package.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
mkdir "$tmp_dir/apple-fm-terminal-$version"
cp "$repo_dir/apple-fm.zsh" "$repo_dir/README.md" "$repo_dir/STATUS.md" "$repo_dir/VERSION" "$repo_dir/install.sh" "$tmp_dir/apple-fm-terminal-$version/"
tar -czf "$archive" -C "$tmp_dir" "apple-fm-terminal-$version"
cp "$archive" "$latest_archive"
cp "$repo_dir/install.sh" "$dist_dir/install.sh"
name=$(basename "$archive")
hash=$(shasum -a 256 "$archive" | awk '{print $1}')
: > "$checksum.tmp"
printf '%s  %s\n' "$hash" "$name" >> "$checksum.tmp"
latest_hash=$(shasum -a 256 "$latest_archive" | awk '{print $1}')
printf '%s  %s\n' "$latest_hash" "$(basename "$latest_archive")" >> "$checksum.tmp"
installer_hash=$(shasum -a 256 "$dist_dir/install.sh" | awk '{print $1}')
printf '%s  %s\n' "$installer_hash" install.sh >> "$checksum.tmp"
mv "$checksum.tmp" "$checksum"
printf 'Created %s\nCreated %s\nUpdated %s\n' "$archive" "$latest_archive" "$checksum"
