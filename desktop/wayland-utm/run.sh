#!/bin/sh
# Origin: EmberBSD; AI-assisted native DRM session probe.
set -eu
umask 077
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
    echo 'Usage: sh run.sh ABSOLUTE_GRAPHICS_PREFIX software|virgl [ABSOLUTE_INPUT_PREFIX]' >&2
    exit 2
}
[ "$(id -u)" -ne 0 ] || { echo 'Run as the existing desktop user.' >&2; exit 2; }
[ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] || {
    echo 'Use a text console after logging out and stopping the display manager.' >&2
    exit 2
}
prefix=$1
case "$prefix" in /*) ;; *) echo 'Prefix must be absolute.' >&2; exit 2 ;; esac
case "$prefix" in *[!a-zA-Z0-9_./-]*) echo 'Use a prefix without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
input_prefix=
if [ "$#" -eq 3 ]; then
    input_prefix=$3
    case "$input_prefix" in /*) ;; *) echo 'Input prefix must be absolute.' >&2; exit 2 ;; esac
    case "$input_prefix" in *[!a-zA-Z0-9_./-]*) echo 'Use an input prefix without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
    [ -f "$input_prefix/lib/libinput.so.10" ] && [ -r "$input_prefix/lib/libinput.so.10" ] || {
        echo 'Private libinput.so.10 missing or unreadable in input prefix.' >&2
        exit 2
    }
fi
PATH="$prefix/bin:/usr/pkg/bin:/usr/pkg/qt6/bin:/usr/X11R7/bin:/usr/bin:/bin"
export PATH
for command in labwc seatd-launch dbus-run-session kate; do command -v "$command" >/dev/null; done
[ -x "$prefix/bin/labwc" ] || { echo 'Private labwc build missing.' >&2; exit 2; }
[ -c /dev/dri/card0 ] || { echo '/dev/dri/card0 is not a character device.' >&2; exit 2; }
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY GALLIUM_DRIVER LIBGL_ALWAYS_SOFTWARE
unset MESA_LOADER_DRIVER_OVERRIDE DRI_PRIME WLR_RENDERER_ALLOW_SOFTWARE WLR_DRM_NO_ATOMIC
case "$2" in
    software)
        WLR_RENDERER=pixman
        LIBGL_ALWAYS_SOFTWARE=1
        GALLIUM_DRIVER=softpipe
        QT_QUICK_BACKEND=software
        export LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER QT_QUICK_BACKEND
        ;;
    virgl)
        WLR_RENDERER=gles2
        unset QT_QUICK_BACKEND
        ;;
    *) echo 'Choose software or virgl.' >&2; exit 2 ;;
esac
session=$(mktemp -d "/tmp/emberbsd-wayland-$(id -u).XXXXXXXX")
script=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$session/runtime" "$session/config"
cp "$script/client.sh" "$session/client.sh"
cat > "$session/config/rc.xml" <<'EOF'
<?xml version="1.0"?>
<labwc_config>
  <keyboard>
    <default />
    <keybind key="C-A-Escape"><action name="Exit" /></keybind>
  </keyboard>
  <mouse><default /></mouse>
</labwc_config>
EOF
XDG_RUNTIME_DIR=$session/runtime
XDG_SESSION_TYPE=wayland
WLR_BACKENDS=drm,libinput
WLR_DRM_DEVICES=/dev/dri/card0
LIBSEAT_BACKEND=seatd
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland
library_path="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
if [ -n "$input_prefix" ]; then
    library_path="$input_prefix/lib:$library_path"
fi
printf 'graphics_prefix=%s\ninput_prefix=%s\nlibrary_path=%s\n' \
    "$prefix" "${input_prefix:-/usr/pkg}" "$library_path" > "$session/prefixes.txt"
LIBGL_DRIVERS_PATH="$prefix/lib/dri"
export XDG_RUNTIME_DIR XDG_SESSION_TYPE WLR_BACKENDS WLR_DRM_DEVICES
export LIBSEAT_BACKEND WLR_RENDERER QT_QPA_PLATFORM GDK_BACKEND
export LIBGL_DRIVERS_PATH
printf 'Native DRM session; mode: %s; logs and saved file: %s\n' "$2" "$session"
echo 'Save a sentence in Kate, test menus/modifiers, then close Kate to exit.'
echo 'Ctrl+Alt+Escape also exits. Keep an SSH recovery connection available.'
status=0
seatd-launch -l debug -- env LD_LIBRARY_PATH="$library_path" \
    dbus-run-session -- "$prefix/bin/labwc" \
    -d -C "$session/config" -S "/bin/sh $session/client.sh $session" \
    > "$session/session.log" 2>&1 || status=$?
# labwc exits successfully even if its primary client failed. Require the
# client's own completion receipt, written after the setuid launcher boundary.
if [ "$status" -eq 0 ]; then
    if [ ! -f "$session/client.status" ]; then
        echo 'Client did not complete; session interrupted or startup failed.' >&2
        status=1
    else
        read -r status < "$session/client.status"
        case "$status" in ''|*[!0-9]*) status=1 ;; esac
    fi
fi
printf 'Session exited with status %s; evidence retained at %s\n' "$status" "$session"
exit "$status"
