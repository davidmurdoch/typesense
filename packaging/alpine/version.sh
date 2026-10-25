#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
upstream=$(sed -n 's/^pkgver=//p' "$root/packaging/alpine/APKBUILD")
[[ "$upstream" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "Invalid APKBUILD pkgver" >&2; exit 1; }
tag=${1:-}
revision=0
release=false
if [[ -n "$tag" ]]; then
    pattern="^v${upstream//./\\.}-alpine\\.([1-9][0-9]*)$"
    [[ "$tag" =~ $pattern ]] || { echo "Expected v${upstream}-alpine.N with N greater than zero" >&2; exit 1; }
    revision=${BASH_REMATCH[1]}
    release=true
fi
printf 'upstream=%s\nrevision=%s\npackage_version=%s-r%s\nrelease=%s\ntag=%s\ncommit=%s\nepoch=%s\n' \
    "$upstream" "$revision" "$upstream" "$revision" "$release" "$tag" \
    "$(git -C "$root" rev-parse HEAD)" "$(git -C "$root" show -s --format=%ct HEAD)"
