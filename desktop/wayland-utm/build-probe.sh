#!/bin/sh
# Build against the private graphics stack produced by EmberBSD Ports.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: sh build-probe.sh ABSOLUTE_GRAPHICS_PREFIX OUTPUT' >&2; exit 2; }
prefix=$1
case "$prefix" in /*) ;; *) echo 'Prefix must be absolute.' >&2; exit 2 ;; esac
case "$prefix" in *[!a-zA-Z0-9_./-]*) echo 'Use a prefix without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
script=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PATH=/usr/pkg/bin:/usr/bin:/bin
PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig:/usr/X11R7/lib/pkgconfig"
export PATH PKG_CONFIG_LIBDIR
unset PKG_CONFIG_PATH
for component in egl glesv2 gbm libdrm; do
    actual=$(pkg-config --variable=prefix "$component")
    [ "$actual" = "$prefix" ] || { echo "Unexpected $component prefix: $actual" >&2; exit 1; }
done
cflags=$(pkg-config --cflags egl glesv2 gbm)
libs=$(pkg-config --libs egl glesv2 gbm)
# pkg-config output is intentionally split into compiler arguments.
cc -std=c99 -D_NETBSD_SOURCE -Wall -Wextra -Werror \
    $cflags "$script/egl-readback.c" -Wl,-rpath,"$prefix/lib" $libs -o "$2"
