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
    ldd "$(command -v labwc)"
    ldd "$(command -v kate)"
} > "$session/libraries.txt"
status=0
kate --new --block "$session/input.txt" > "$session/client.log" 2>&1 || status=$?
printf '%s\n' "$status" > "$session/client.status"
exit "$status"
