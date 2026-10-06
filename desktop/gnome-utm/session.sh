#!/bin/sh
# X11 GNOME session for the software-rendered UTM framebuffer.
set -eu
PATH=/usr/pkg/bin:/usr/X11R7/bin:/bin:/usr/bin
export PATH
LANG=C.UTF-8
XDG_SESSION_TYPE=x11
XDG_CURRENT_DESKTOP=GNOME
XDG_SESSION_DESKTOP=gnome
DESKTOP_SESSION=gnome
XDG_DATA_DIRS=/usr/local/share/emberbsd-gnome/share:/usr/pkg/share:/usr/local/share:/usr/share
XCURSOR_PATH=/usr/pkg/share/icons:/usr/X11R7/lib/X11/icons
LIBGL_ALWAYS_SOFTWARE=1
GALLIUM_DRIVER=llvmpipe
export LANG XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP
export DESKTOP_SESSION XDG_DATA_DIRS XCURSOR_PATH
export LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER
GSETTINGS_SCHEMA_DIR=/usr/local/share/emberbsd-gnome/schemas
export GSETTINGS_SCHEMA_DIR
GI_TYPELIB_PATH=/usr/local/share/emberbsd-gnome/typelib:/usr/pkg/lib/gnome-shell:/usr/pkg/lib/mutter-8
export GI_TYPELIB_PATH
XDG_RUNTIME_DIR="$HOME/.cache/emberbsd-gnome/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export XDG_RUNTIME_DIR
ulimit -n 8192
exec ck-launch-session dbus-run-session -- gnome-session --session=gnome
