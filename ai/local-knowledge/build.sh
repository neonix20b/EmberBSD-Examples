#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: sh build.sh OUTPUT_EXECUTABLE' >&2; exit 2; }
[ ! -e "$1" ] || { echo 'Output already exists.' >&2; exit 2; }
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
pkgconf=${PKG_CONFIG:-pkg-config}
command -v "$pkgconf" >/dev/null
cflags=$("$pkgconf" --cflags sqlite3)
libs=$("$pkgconf" --libs sqlite3)
"${CC:-cc}" -std=c99 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -O2 \
    ${CPPFLAGS:-} ${CFLAGS:-} $cflags "$here/knowledge.c" ${LDFLAGS:-} $libs -o "$1"
