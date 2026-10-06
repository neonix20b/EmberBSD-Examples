#!/bin/sh
# Configure an installed NetBSD 11/aarch64 userland with an EmberBSD kernel.
# An existing non-root local account is required; credentials are not changed.
set -eu
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/pkg/bin:/usr/pkg/sbin:/usr/X11R7/bin
export PATH
[ "$(id -u)" = 0 ] || { echo 'Run as root.' >&2; exit 1; }
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ] || exit 1
case "$(uname -r)" in 11.0*) ;; *) echo 'NetBSD 11 userland required.' >&2; exit 1 ;; esac
[ "$#" = 1 ] || { echo 'usage: sh setup.sh EXISTING_USER' >&2; exit 1; }
user=$1
case "$user" in ''|*[!a-zA-Z0-9_-]*) echo 'Invalid user name.' >&2; exit 1 ;; esac
[ "$(id -u "$user")" -ne 0 ] || { echo 'Use a non-root desktop account.' >&2; exit 1; }
home=$(getent passwd "$user" | cut -d: -f6)
[ -d "$home" ] || { echo 'Home directory missing.' >&2; exit 1; }
group=$(id -gn "$user")
command -v pkgin >/dev/null || { echo 'Install and configure pkgin first.' >&2; exit 1; }
pkgin -y install kde-workspace4 kde-baseapps4 kde-wallpapers4 dolphin konsole kate
# The tested attr package omits the intermediate targets of two man aliases.
# Add compatibility names without changing or replacing package-owned files.
if pkg_info -e attr-2.5.2 >/dev/null 2>&1; then
    for op in get set; do
        man=/usr/pkg/man/man3
        if [ "$(readlink "$man/attr_${op}f.3")" = "attr_${op}.3" ] &&
            [ -f "$man/attr_attr_${op}.3" ] &&
            [ ! -e "$man/attr_${op}.3" ] && [ ! -L "$man/attr_${op}.3" ]; then
            ln -s "attr_attr_${op}.3" "$man/attr_${op}.3"
        fi
    done
fi

backup() {
    [ ! -e "$1" ] || [ -e "$1.before-emberbsd-kde" ] || cp -p "$1" "$1.before-emberbsd-kde"
}
backup /etc/login.conf
if ! grep -q '^emberdesktop:' /etc/login.conf; then
    cat >> /etc/login.conf <<'EOF'

# KDE's kqueue file watchers need more than 1024 descriptors.
emberdesktop:\
    :openfiles-cur=8192:\
    :openfiles-max=16384:
EOF
fi
[ ! -f /etc/login.conf.db ] || cap_mkdb /etc/login.conf
usermod -L emberdesktop "$user"
backup /etc/sysctl.conf
if ! grep -q '^kern.maxfiles=32768$' /etc/sysctl.conf; then
    printf '\n# EmberBSD KDE desktop\nkern.maxfiles=32768\n' >> /etc/sysctl.conf
fi
sysctl -w kern.maxfiles=32768
mkdir -p /var/backups/emberbsd-kde
for service in dbus; do
    # rcorder scans every script in rc.d, including ordinary backup names.
    if [ -e "/etc/rc.d/$service" ] && [ ! -e "/var/backups/emberbsd-kde/$service" ]; then
        cp -p "/etc/rc.d/$service" "/var/backups/emberbsd-kde/$service"
    fi
    install -m 755 "/usr/pkg/share/examples/rc.d/$service" "/etc/rc.d/$service"
done
mkdir -p /etc/rc.conf.d
backup /etc/rc.conf.d/dbus
printf '%s\n' 'dbus=YES' > /etc/rc.conf.d/dbus
backup /etc/rc.conf.d/kdm
cat > /etc/rc.conf.d/kdm <<'EOF'
kdm=NO
EOF
backup /etc/rc.conf.d/xdm
cat > /etc/rc.conf.d/xdm <<'EOF'
xdm=YES
ulimit -n 8192
EOF
backup /etc/rc.conf
if ! grep -q '^# EmberBSD KDE desktop$' /etc/rc.conf; then
    cat >> /etc/rc.conf <<'EOF'

# EmberBSD KDE desktop
dbus=YES
xdm=YES
kdm=NO
EOF
fi
backup /etc/X11/xdm/Xservers
printf '%s\n' ':0 local /usr/X11R7/bin/X :0 -noretro -nolisten tcp vt05' > /etc/X11/xdm/Xservers
backup /etc/X11/xdm/Xresources
if ! grep -q '^! EmberBSD visible password feedback$' /etc/X11/xdm/Xresources; then
    cat >> /etc/X11/xdm/Xresources <<'EOF'

! EmberBSD visible password feedback
xlogin.Login.echoPasswd: true
xlogin.Login.echoPasswdChar: *
EOF
fi
mkdir -p /etc/X11/xorg.conf.d
backup /etc/X11/xorg.conf.d/20-emberbsd-wsfb.conf
cat > /etc/X11/xorg.conf.d/20-emberbsd-wsfb.conf <<'EOF'
Section "Device"
    Identifier "UEFI framebuffer"
    Driver "wsfb"
EndSection
EOF
mkdir -p /usr/local/share/emberbsd-kde
cat > /usr/local/share/emberbsd-kde/session-env.sh <<'EOF'
PATH=/usr/pkg/bin:/usr/X11R7/bin:/bin:/usr/bin:$PATH
KWIN_COMPOSE=N
export PATH KWIN_COMPOSE
case "${LANG:-C}" in
    C|POSIX) LANG=C.UTF-8; export LANG ;;
esac
ulimit -n 8192
EOF
backup "$home/.xprofile"
if ! grep -qs 'emberbsd-kde/session-env.sh' "$home/.xprofile"; then
    printf '\n. /usr/local/share/emberbsd-kde/session-env.sh\n' >> "$home/.xprofile"
fi
chown "$user:$group" "$home/.xprofile"
backup "$home/.xsession"
cat > "$home/.xsession" <<'EOF'
#!/bin/sh
. /usr/local/share/emberbsd-kde/session-env.sh
exec /usr/pkg/bin/startkde --failsafe
EOF
chown "$user:$group" "$home/.xsession"
chmod 755 "$home/.xsession"
su - "$user" -c '/usr/pkg/bin/kwriteconfig --file kwinrc --group Compositing --key Enabled --type bool false'
pkg_admin check
echo 'KDE configured. Reboot, log in through XDM, then run verify.sh.'
