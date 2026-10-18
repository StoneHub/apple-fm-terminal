#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec /bin/sh "$root/install.sh" --directory "$root"
