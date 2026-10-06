#!/bin/sh
# Build the native GEM/PRIME lifetime probe against the private libdrm.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: sh build-memory.sh ABSOLUTE_GRAPHICS_PREFIX OUTPUT' >&2; exit 2; }
prefix=$1
case "$prefix" in /*) ;; *) echo 'Prefix must be absolute.' >&2; exit 2 ;; esac
case "$prefix" in *[!a-zA-Z0-9_./-]*) echo 'Use a prefix without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PATH=/usr/pkg/bin:/usr/bin:/bin
PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
export PATH PKG_CONFIG_LIBDIR
unset PKG_CONFIG_PATH
[ "$(pkg-config --variable=prefix libdrm)" = "$prefix" ] || { echo 'Unexpected libdrm prefix.' >&2; exit 1; }
cflags=$(pkg-config --cflags libdrm)
libs=$(pkg-config --libs libdrm)
cc -std=c99 -D_NETBSD_SOURCE -Wall -Wextra -Werror $cflags \
    "$here/drm-memory.c" -Wl,-rpath,"$prefix/lib" $libs -o "$2"
