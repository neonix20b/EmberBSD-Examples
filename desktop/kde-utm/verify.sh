#!/bin/sh
# Run inside the logged-in desktop's terminal; also inspect the UTM window.
set -eu
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin
export PATH
uname -a
sysctl kern.boottime
xdpyinfo | sed -n '/dimensions:/p'
pgrep -u "$(id -u)" -x kwin >/dev/null
pgrep -u "$(id -u)" -f '(^|[ /])plasma-desktop( |$)' >/dev/null
pkg_info -e 'kde-workspace4-*'
pkg_info -e 'kde-baseapps4-*'
for app in dolphin konsole kate; do
    "$app" --version
done
testfile=$(mktemp "$HOME/.emberbsd-desktop-check.XXXXXXXX")
trap 'rm -f "$testfile"' EXIT HUP INT TERM
printf 'EmberBSD desktop write check\n' > "$testfile"
grep -q 'EmberBSD desktop write check' "$testfile"
curl -fIsS --max-time 30 https://www.netbsd.org/ >/dev/null
echo 'Desktop processes, X11, home writes, DNS and HTTPS passed.'
echo 'Also verify visible rendering, keyboard, pointer, application windows and a reboot.'
