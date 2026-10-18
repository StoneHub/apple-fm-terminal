#!/bin/sh
set -eu
install_dir=${APPLE_FM_INSTALL_DIR:-"${HOME:?HOME must be set}/.local/share/apple-fm-terminal"}
mode=download
archive=
checksums=
directory=
yes=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --directory) directory=$2; mode=directory; shift 2;;
    --archive) archive=$2; mode=archive; shift 2;;
    --checksums) checksums=$2; shift 2;;
    --yes) yes=--yes; shift;;
    --install|--update) shift;;
    --uninstall) mode=uninstall; shift;;
    --help|-h) printf '%s\n' 'Usage: install.sh [--directory PACKAGE | --archive FILE [--checksums FILE]] [--yes]' '       install.sh --uninstall [--yes]'; exit 0;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2;;
  esac
done
if [ "$mode" = uninstall ]; then
  exec "$install_dir/apple-fm-terminal" uninstall ${yes:+"$yes"}
fi
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || { echo 'This preview requires an Apple Silicon Mac running natively.' >&2; exit 1; }
major=$(/usr/bin/sw_vers -productVersion | cut -d . -f 1)
[ "$major" -ge 26 ] || { echo 'This preview requires macOS 26 or later.' >&2; exit 1; }
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/apple-fm-terminal-install.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
if [ "$mode" = download ]; then
  # Pin the preview; never accidentally install the legacy latest release.
  release_base=https://github.com/StoneHub/apple-fm-terminal/releases/download/v0.3.0-preview.1
  archive="$tmp_dir/apple-fm-terminal.tar.gz"
  checksums="$tmp_dir/SHA256SUMS"
  curl -fsSL "$release_base/apple-fm-terminal.tar.gz" -o "$archive"
  curl -fsSL "$release_base/SHA256SUMS" -o "$checksums"
fi
if [ "$mode" != directory ]; then
  if [ -n "$checksums" ]; then
    name=$(basename "$archive")
    expected=$(awk -v name="$name" '$2 == name { print $1; exit }' "$checksums")
    actual=$(shasum -a 256 "$archive" | awk '{print $1}')
    [ -n "$expected" ] && [ "$actual" = "$expected" ] || { echo 'Archive checksum verification failed.' >&2; exit 1; }
  fi
  # Bootstrap uses only macOS tools. Our archives have no links or special files.
  # Validate names and entry types before extracting or executing the runtime.
  /usr/bin/tar -tzf "$archive" > "$tmp_dir/names"
  awk '/^\// || /(^|\/)\.\.(\/|$)/ {bad=1} END {exit bad}' "$tmp_dir/names" || { echo 'Unsafe archive path; extraction refused.' >&2; exit 1; }
  /usr/bin/tar -tvzf "$archive" > "$tmp_dir/types"
  awk 'substr($0,1,1)!="-" && substr($0,1,1)!="d" {bad=1} END {exit bad}' "$tmp_dir/types" || { echo 'Unsupported archive entry; extraction refused.' >&2; exit 1; }
  mkdir "$tmp_dir/unpack"
  COPYFILE_DISABLE=1 /usr/bin/tar --exclude '._*' --exclude '.DS_Store' -xzf "$archive" -C "$tmp_dir/unpack"
  directory=$(find "$tmp_dir/unpack" -type f -name terminal-session -exec dirname {} \; | sed -n '1p')
fi
[ -n "$directory" ] && [ -f "$directory/scripts/install.py" ] || { echo 'This is not a Terminal Ask package.' >&2; exit 1; }
python="$directory/runtime/bin/python3"
# Explicit override supports development/test fixtures only; release packages
# always carry their own interpreter and never discover one on PATH.
[ -x "$python" ] || python=${APPLE_FM_PYTHON:-}
[ -n "$python" ] && [ -x "$python" ] || { echo 'The private runtime is missing. Download the complete preview package.' >&2; exit 1; }
"$python" -I -B "$directory/scripts/install.py" "$directory" "$install_dir" ${yes:+"$yes"}
