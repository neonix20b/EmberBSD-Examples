#!/bin/sh
# Origin: EmberBSD; AI-assisted native DRM session probe.
set -eu
umask 077
[ "$#" -eq 2 ] || { echo 'Usage: sh run.sh ABSOLUTE_GRAPHICS_PREFIX software|virgl' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as the existing desktop user.' >&2; exit 2; }
[ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] || {
    echo 'Use a text console after logging out and stopping the display manager.' >&2
    exit 2
}
prefix=$1
case "$prefix" in /*) ;; *) echo 'Prefix must be absolute.' >&2; exit 2 ;; esac
case "$prefix" in *[!a-zA-Z0-9_./-]*) echo 'Use a prefix without whitespace or shell metacharacters.' >&2; exit 2 ;; esac
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
mkdir "$session/runtime" "$session/config"
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
LD_LIBRARY_PATH="$prefix/lib:/usr/pkg/lib:/usr/X11R7/lib"
LIBGL_DRIVERS_PATH="$prefix/lib/dri"
export XDG_RUNTIME_DIR XDG_SESSION_TYPE WLR_BACKENDS WLR_DRM_DEVICES
export LIBSEAT_BACKEND WLR_RENDERER QT_QPA_PLATFORM GDK_BACKEND
export LD_LIBRARY_PATH LIBGL_DRIVERS_PATH
ldd "$prefix/bin/labwc" > "$session/libraries.txt"
printf 'Native DRM session; mode: %s; logs and saved file: %s\n' "$2" "$session"
echo 'Save a sentence in Kate, test menus/modifiers, then close Kate to exit.'
echo 'Ctrl+Alt+Escape also exits. Keep an SSH recovery connection available.'
status=0
seatd-launch -l debug -- dbus-run-session -- "$prefix/bin/labwc" \
    -d -C "$session/config" -S "kate --new --block $session/input.txt" \
    > "$session/session.log" 2>&1 || status=$?
printf 'Session exited with status %s; evidence retained at %s\n' "$status" "$session"
exit "$status"
