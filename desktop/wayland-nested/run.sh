#!/bin/sh
# Run an upstream Qt compositor inside X11, with a native Wayland Kate client.
# Run as the desktop user from an existing X11 session, not as root.
set -eu
umask 077
PATH=/usr/pkg/bin:/usr/pkg/qt6/bin:/usr/X11R7/bin:/bin:/usr/bin
export PATH
[ "$(id -u)" -ne 0 ] || { echo 'Run as the desktop user.' >&2; exit 1; }
[ -n "${DISPLAY:-}" ] || { echo 'An active X11 DISPLAY is required.' >&2; exit 1; }
for command in qml kate curl sha256; do command -v "$command" >/dev/null; done
mkdir -p "$HOME/.cache"
workdir=$(mktemp -d "$HOME/.cache/emberbsd-wayland.XXXXXXXX")
upstream=https://raw.githubusercontent.com/qt/qtwayland/v6.11.1
curl -fLsS "$upstream/examples/wayland/minimal-qml/main.qml" -o "$workdir/main.qml"
curl -fLsS "$upstream/LICENSES/BSD-3-Clause.txt" -o "$workdir/LICENSE"
[ "$(sha256 -q "$workdir/main.qml")" = 24bb1e92588ab689711dd557e67dd0abf9de5282fc3895d9a72b3ee2b2a312cb ]
[ "$(sha256 -q "$workdir/LICENSE")" = 9f0490f18656c6f2435bd14f603ef0c96434d1825615363dce43abb42ed1dcce ]
mkdir "$workdir/runtime"
XDG_RUNTIME_DIR=$workdir/runtime
WAYLAND_DISPLAY=emberbsd-wayland-test
QT_QUICK_BACKEND=software
LANG=C.UTF-8
export XDG_RUNTIME_DIR WAYLAND_DISPLAY QT_QUICK_BACKEND LANG
compositor_pid=
client_pid=
cleanup() {
    [ -z "$client_pid" ] || kill "$client_pid" 2>/dev/null || :
    [ -z "$compositor_pid" ] || kill "$compositor_pid" 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
QT_QPA_PLATFORM=xcb qml "$workdir/main.qml" > "$workdir/compositor.log" 2>&1 &
compositor_pid=$!
attempt=0
while [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; do
    if ! kill -0 "$compositor_pid" 2>/dev/null || [ "$attempt" -ge 15 ]; then
        cat "$workdir/compositor.log" >&2
        echo "Compositor failed; files retained in $workdir" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 1
done
(
    unset DISPLAY
    QT_QPA_PLATFORM=wayland
    export QT_QPA_PLATFORM
    # --block also prevents Kate from forking away from this process.
    exec kate --new --block "$workdir/input.txt"
) > "$workdir/client.log" 2>&1 &
client_pid=$!
printf 'Compositor PID: %s; Wayland client PID: %s\n' "$compositor_pid" "$client_pid"
printf 'Test files: %s\n' "$workdir"
echo 'Type and save a test sentence in Kate, then open a menu with the mouse.'
echo 'Close Kate or press Ctrl+C here to stop this test.'
wait "$client_pid"
client_pid=
