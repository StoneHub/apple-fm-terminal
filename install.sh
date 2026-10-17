#!/bin/sh
set -eu
install_dir=${APPLE_FM_INSTALL_DIR:-"${HOME:?HOME must be set}/.local/share/apple-fm-terminal"}
python=${APPLE_FM_PYTHON:-$(command -v python3 || true)}
mode=latest
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
[ -n "$python" ] || { echo 'Python 3.9 or later is required for session capture and setup.' >&2; exit 1; }
"$python" -c 'import sys; sys.exit(sys.version_info < (3, 9))' || { echo 'Python 3.9 or later is required.' >&2; exit 1; }
if [ "$mode" = uninstall ]; then
  exec "$python" "$install_dir/scripts/management.py" uninstall ${yes:+"$yes"}
fi
[ "$(uname -s)" = Darwin ] || { echo 'macOS is required.' >&2; exit 1; }
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/apple-fm-terminal-install.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
if [ "$mode" = latest ]; then
  release_base=https://github.com/StoneHub/apple-fm-terminal/releases/latest/download
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
  mkdir "$tmp_dir/unpack"
  "$python" - "$archive" "$tmp_dir/unpack" <<'PY'
import sys, tarfile
from pathlib import Path
with tarfile.open(sys.argv[1]) as archive:
    for member in archive.getmembers():
        path = Path(member.name)
        if path.is_absolute() or '..' in path.parts or member.issym() or member.islnk() or not (member.isfile() or member.isdir()):
            raise SystemExit('Unsupported archive entry; extraction refused.')
    archive.extractall(sys.argv[2])
PY
  directory=$(find "$tmp_dir/unpack" -type f -name terminal-session -exec dirname {} \; | sed -n '1p')
fi
[ -n "$directory" ] && [ -f "$directory/scripts/install.py" ] || { echo 'This is not a Terminal Ask package; build the new package first.' >&2; exit 1; }
"$python" "$directory/scripts/install.py" "$directory" "$install_dir" ${yes:+"$yes"}
