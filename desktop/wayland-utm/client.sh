#!/bin/sh
# Labwc's -S does not propagate the primary client's exit status.
set -eu
[ "$#" -eq 1 ] || exit 2
session=$1
{
    printf 'LD_LIBRARY_PATH=%s\n' "${LD_LIBRARY_PATH:-}"
    printf 'LIBGL_DRIVERS_PATH=%s\n' "${LIBGL_DRIVERS_PATH:-}"
    printf 'WAYLAND_DISPLAY=%s\n' "${WAYLAND_DISPLAY:-}"
    printf 'QT_QPA_PLATFORM=%s\n' "${QT_QPA_PLATFORM:-}"
    echo 'Compositor libraries:'
    ldd "$(command -v labwc)"
} > "$session/libraries.txt"
# Packaged Qt links NetBSD's EGL.so.0/GL.so.3, whereas the private Mesa uses
# EGL.so.1/GL.so.1. Do not combine base EGL with private GBM/DRM by SONAME.
# Kate is the native SHM/input client; the separate EGL probe tests the GPU.
unset LD_LIBRARY_PATH LIBGL_DRIVERS_PATH MESA_LOADER_DRIVER_OVERRIDE
unset GALLIUM_DRIVER DRI_PRIME
LIBGL_ALWAYS_SOFTWARE=1
QT_QUICK_BACKEND=software
export LIBGL_ALWAYS_SOFTWARE QT_QUICK_BACKEND
{
    echo 'Kate libraries (packaged software/SHM client):'
    ldd "$(command -v kate)"
} >> "$session/libraries.txt"
status=0
kate --new --block "$session/input.txt" > "$session/client.log" 2>&1 || status=$?
printf '%s\n' "$status" > "$session/client.status"
exit "$status"
