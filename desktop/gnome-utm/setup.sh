#!/bin/sh
# Configure a GNOME X11 session on the EmberBSD UTM framebuffer demo.
# Requires an existing non-root account; never creates credentials or autologin.
set -eu
umask 022
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
[ -x /usr/X11R7/bin/X ] || { echo 'Install the base X11 sets first.' >&2; exit 1; }
command -v pkgin >/dev/null
scriptdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
prefix=/usr/local/share/emberbsd-gnome
pkgin -y install gnome-shell gnome-session gnome-settings-daemon \
    gnome-terminal nautilus gedit gnome-backgrounds gnome-themes-standard \
    consolekit cantarell-fonts dejavu-ttf xdg-user-dirs curl libxslt pkgconf

# Known attr-2.5.2 packaging omission; do not replace package-owned files.
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
mkdir -p "$prefix/cache"
chmod 755 "$prefix" "$prefix/cache"
schemas=gsettings-desktop-schemas-40.0.tar.xz
shell=gnome-shell-40.2.tar.xz
for component in schemas shell; do
    case "$component" in
        schemas) archive=$schemas; path=gsettings-desktop-schemas/40 ;;
        shell) archive=$shell; path=gnome-shell/40 ;;
    esac
    if [ ! -f "$prefix/cache/$archive" ]; then
        curl -fL --retry 3 "https://download.gnome.org/sources/$path/$archive" \
            -o "$prefix/cache/$archive.part"
        mv "$prefix/cache/$archive.part" "$prefix/cache/$archive"
    fi
done
# Builders validate pinned SHA256 sums and reject nonempty output directories.
stage=$(mktemp -d "$prefix/.build.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
sh "$scriptdir/build-schemas.sh" "$prefix/cache/$schemas" "$stage/schemas"
sh "$scriptdir/build-typelib.sh" "$stage/typelib"
sh "$scriptdir/build-launcher.sh" "$prefix/cache/$shell" "$stage/launcher"
mkdir -p "$stage/share/applications"
sed 's|^Exec=.*|Exec=/usr/local/share/emberbsd-gnome/launcher/gnome-shell|' \
    /usr/pkg/share/applications/org.gnome.Shell.desktop \
    > "$stage/share/applications/org.gnome.Shell.desktop"
stamp=$(date -u +%Y%m%dT%H%M%SZ)-$$
for component in schemas typelib launcher share; do
    [ ! -e "$prefix/$component" ] || mv "$prefix/$component" "$prefix/$component.before-$stamp"
    mv "$stage/$component" "$prefix/$component"
done
install -m 755 "$scriptdir/session.sh" "$scriptdir/verify.sh" "$prefix/"

backup() {
    [ ! -e "$1" ] || [ -e "$1.before-emberbsd-gnome" ] || cp -p "$1" "$1.before-emberbsd-gnome"
}
backup /etc/login.conf
if ! grep -q '^emberdesktop:' /etc/login.conf; then
    cat >> /etc/login.conf <<'EOF'

# Desktop kqueue file watchers require more than the base descriptor limit.
emberdesktop:\
    :openfiles-cur=8192:\
    :openfiles-max=16384:
EOF
fi
[ ! -f /etc/login.conf.db ] || cap_mkdb /etc/login.conf
usermod -L emberdesktop "$user"
if [ "$(sysctl -n kern.maxfiles)" -lt 32768 ]; then
    backup /etc/sysctl.conf
    printf '\n# EmberBSD GNOME desktop\nkern.maxfiles=32768\n' >> /etc/sysctl.conf
    sysctl -w kern.maxfiles=32768
fi
mkdir -p /var/backups/emberbsd-gnome /etc/rc.conf.d
# rcorder scans every file in rc.d, so keep service backups elsewhere.
if [ -e /etc/rc.d/dbus ] && [ ! -e /var/backups/emberbsd-gnome/dbus ]; then
    cp -p /etc/rc.d/dbus /var/backups/emberbsd-gnome/dbus
fi
install -m 755 /usr/pkg/share/examples/rc.d/dbus /etc/rc.d/dbus
for service in dbus xdm kdm; do backup "/etc/rc.conf.d/$service"; done
printf '%s\n' 'dbus=YES' > /etc/rc.conf.d/dbus
printf '%s\n' 'xdm=YES' 'ulimit -n 8192' > /etc/rc.conf.d/xdm
printf '%s\n' 'kdm=NO' > /etc/rc.conf.d/kdm
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
mkdir -p /usr/pkg/etc/xdg/Xwayland-session.d
if [ ! -f /usr/pkg/etc/xdg/Xwayland-session.d/00-xrdb ]; then
    install -m 755 /usr/pkg/share/examples/xdg/Xwayland-session.d/00-xrdb \
        /usr/pkg/etc/xdg/Xwayland-session.d/00-xrdb
fi
pkg_admin check
# Select the new session only after all builds and package checks succeed.
backup "$home/.xsession"
cat > "$home/.xsession" <<'EOF'
#!/bin/sh
exec /usr/local/share/emberbsd-gnome/session.sh
EOF
chown "$user:$group" "$home/.xsession"
chmod 755 "$home/.xsession"
echo 'GNOME configured. Reboot, log in through XDM, then run:'
echo 'sh /usr/local/share/emberbsd-gnome/verify.sh'
