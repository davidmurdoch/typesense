#!/bin/sh
# Keep the separately retained DWARF matched to the tested runtime binary.
set -eu
binary=${1:?Usage: split-debug.sh TYPESENSE_SERVER}
debug="$binary.debug"
[ -x "$binary" ] && [ ! -e "$debug" ]
objcopy --only-keep-debug "$binary" "$debug"
strip --strip-debug "$binary"
objcopy --add-gnu-debuglink="$debug" "$binary"
