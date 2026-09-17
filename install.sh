#!/bin/sh
set -eu

repo='StoneHub/apple-fm-terminal'
release_base="https://github.com/$repo/releases/latest/download"
install_dir=${APPLE_FM_INSTALL_DIR:-"${HOME:?HOME must be set}/.local/share/apple-fm-terminal"}
config_dir=${ZDOTDIR:-"${HOME:?HOME must be set}"}
zshrc="$config_dir/.zshrc"
mode=latest
archive_arg=
checksum_arg=

die() { printf 'apple-fm-terminal: %s\n' "$*" >&2; exit 1; }
usage() {
  printf '%s\n' \
    'Usage: install.sh [--install|--update] [--archive PATH [--checksums PATH]]' \
    '       install.sh --help'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install|--update) mode=latest; shift ;;
    --archive) [ "$#" -ge 2 ] || die '--archive requires a path'; mode=local; archive_arg=$2; shift 2 ;;
    --checksums) [ "$#" -ge 2 ] || die '--checksums requires a path'; checksum_arg=$2; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[ "$(uname -s)" = Darwin ] || die 'macOS is required (Darwin was not detected).'
[ -x /usr/bin/fm ] || die '/usr/bin/fm is unavailable; install on a supported macOS system with Apple FM enabled.'
[ -n "${HOME:-}" ] || die 'HOME must be set.'

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/apple-fm-terminal-install.XXXXXX") || die 'could not create a temporary directory.'
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT HUP INT TERM

if [ "$mode" = latest ]; then
  archive_arg="$tmp_dir/apple-fm-terminal.tar.gz"
  checksum_arg="$tmp_dir/SHA256SUMS"
  curl -fsSL "$release_base/apple-fm-terminal.tar.gz" -o "$archive_arg" || die 'could not download the latest release archive.'
  curl -fsSL "$release_base/SHA256SUMS" -o "$checksum_arg" || die 'could not download the latest checksum manifest.'
  archive_name=$(basename "$archive_arg")
  expected=$(awk -v name="$archive_name" '$2 == name || $2 == "*" name { print $1; exit }' "$checksum_arg")
  [ -n "$expected" ] || die 'latest checksum manifest does not name the downloaded archive.'
  actual=$(shasum -a 256 "$archive_arg" | awk '{print $1}')
  [ "$actual" = "$expected" ] || die 'latest release checksum verification failed.'
else
  [ -f "$archive_arg" ] || die "archive not found: $archive_arg"
  if [ -n "$checksum_arg" ]; then
    [ -f "$checksum_arg" ] || die "checksum manifest not found: $checksum_arg"
    archive_name=$(basename "$archive_arg")
    expected=$(awk -v name="$archive_name" '$2 == name || $2 == "*" name { print $1; exit }' "$checksum_arg")
    [ -n "$expected" ] || die 'checksum manifest does not name the local archive.'
    actual=$(shasum -a 256 "$archive_arg" | awk '{print $1}')
    [ "$actual" = "$expected" ] || die 'local archive checksum verification failed.'
  fi
fi

mkdir "$tmp_dir/unpack"
tar -xzf "$archive_arg" -C "$tmp_dir/unpack" || die 'could not unpack the release archive.'
package_dir=$(find "$tmp_dir/unpack" -type f -name apple-fm.zsh -exec dirname {} \; | sed -n '1p')
[ -n "$package_dir" ] || die 'release archive has no package directory.'
[ -f "$package_dir/apple-fm.zsh" ] || die 'release archive is missing apple-fm.zsh.'
[ -f "$package_dir/VERSION" ] || die 'release archive is missing VERSION.'

mkdir -p "$install_dir"
cp "$package_dir/apple-fm.zsh" "$package_dir/install.sh" "$package_dir/README.md" "$package_dir/STATUS.md" "$package_dir/VERSION" "$install_dir/"
chmod 644 "$install_dir/apple-fm.zsh" "$install_dir/README.md" "$install_dir/STATUS.md" "$install_dir/VERSION"
chmod 755 "$install_dir/install.sh"

mkdir -p "$config_dir"
start='# >>> apple-fm-terminal >>>'
end='# <<< apple-fm-terminal <<<'
if [ -f "$zshrc" ] && grep -qF "$start" "$zshrc"; then
  grep -qF "$end" "$zshrc" || die "$zshrc has an incomplete apple-fm-terminal block; refusing to edit it."
  awk -v start="$start" -v end="$end" '$0 == start {skip=1; next} $0 == end {skip=0; next} !skip {print}' "$zshrc" > "$tmp_dir/zshrc"
else
  [ -f "$zshrc" ] && cp "$zshrc" "$tmp_dir/zshrc" || : > "$tmp_dir/zshrc"
fi
shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
quoted_install=$(shell_quote "$install_dir/apple-fm.zsh")
quoted_installer=$(shell_quote "$install_dir/install.sh")
quoted_version=$(shell_quote "$install_dir/VERSION")
{
  cat "$tmp_dir/zshrc"
  printf '\n%s\n' "$start"
  printf 'if [ -r %s ]; then\n  source %s\n  apple-fm-enable\nfi\napple-fm-update() { %s --update "$@"; }\napple-fm-version() { cat %s; }\n%s\n' "$quoted_install" "$quoted_install" "$quoted_installer" "$quoted_version" "$end"
} > "$tmp_dir/zshrc.new"
if [ -e "$zshrc" ]; then
  cat "$tmp_dir/zshrc.new" > "$zshrc"
else
  mv "$tmp_dir/zshrc.new" "$zshrc"
fi

printf 'Installed Apple FM terminal %s in %s\n' "$(tr -d '[:space:]' < "$install_dir/VERSION")" "$install_dir"
printf 'Enabled it for new zsh sessions through %s\n' "$zshrc"
