#!/bin/sh
# Run in a terminal inside the GNOME session.
set -eu
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin:/bin:/sbin:/usr/bin:/usr/sbin
export PATH
uname -a
sysctl kern.boottime
xdpyinfo | sed -n '/dimensions:/p'
glxinfo -B
pgrep -u "$(id -u)" -f '^/usr/local/share/emberbsd-gnome/launcher/gnome-shell' >/dev/null
gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell \
    --method org.freedesktop.DBus.Peer.Ping
for package in gnome-session gnome-shell mutter gnome-terminal nautilus gedit; do
    pkg_info -e "$package"
done
testfile=$(mktemp "$HOME/.emberbsd-gnome-check.XXXXXXXX")
trap 'rm -f "$testfile"' EXIT HUP INT TERM
printf 'EmberBSD GNOME write check\n' > "$testfile"
grep -q 'EmberBSD GNOME write check' "$testfile"
curl -fIsS --max-time 30 https://www.netbsd.org/ >/dev/null
echo 'GNOME shell, session bus, X11, OpenGL, home writes, DNS and HTTPS passed.'
echo 'Also check the visible desktop, keyboard, pointer, applications and login after reboot.'
