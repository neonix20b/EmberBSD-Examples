#!/bin/sh
# Configure unmodified Plasma Mobile sources without changing the desktop.
set -eu
umask 077
PATH=/usr/pkg/bin:/usr/pkg/qt6/bin:/usr/bin:/bin
LANG=C.UTF-8
export PATH LANG

[ "$#" -le 1 ] || { echo 'Usage: sh probe.sh [source-archive]' >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || { echo 'Run this probe on EmberBSD/NetBSD.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user, not root.' >&2; exit 2; }
for tool in cmake ninja tar sha256; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done

version=6.5.2
expected=6eca5d046ed46acdaedc64a1508c06e81cc9a205a0ca1609e88a94e9078b8067
url="https://download.kde.org/stable/plasma/$version/plasma-mobile-$version.tar.xz"
mkdir -p "$HOME/.cache"
probe_dir=$(mktemp -d "$HOME/.cache/emberbsd-plasma-mobile.XXXXXXXX")
printf 'Probe directory: %s\n' "$probe_dir"
archive="$probe_dir/plasma-mobile-$version.tar.xz"
if [ "$#" -eq 1 ]; then
    cp "$1" "$archive"
else
    command -v curl >/dev/null || { echo 'Missing tool: curl' >&2; exit 2; }
    curl -fLsS --connect-timeout 20 --max-time 300 "$url" -o "$archive"
fi
actual=$(sha256 -q "$archive")
if [ "$actual" != "$expected" ]; then
    printf 'Source SHA256 mismatch: expected %s, got %s\n' "$expected" "$actual" >&2
    exit 2
fi
{
    printf 'Source: %s\nSHA256: %s\n' "$url" "$actual"
    uname -srvm
    cmake --version
    printf '\nInstalled Qt and KDE packages:\n'
    /usr/sbin/pkg_info | grep -E '^(qt6-|kf6-|plasma6-|extra-cmake-modules-|qcoro-)' || :
    printf '\nSession executables:\n'
    for executable in kwin_wayland plasmashell; do
        command -v "$executable" || printf '%s: not in PATH\n' "$executable"
    done
} > "$probe_dir/environment.txt"
tar -xJf "$archive" -C "$probe_dir"

result=0
cmake -S "$probe_dir/plasma-mobile-$version" -B "$probe_dir/build" -G Ninja \
    -DCMAKE_PREFIX_PATH='/usr/pkg;/usr/pkg/qt6' \
    -DCMAKE_INSTALL_PREFIX="$probe_dir/install" \
    -DBUILD_TESTING=OFF -DINSTALL_SYSTEMD_SERVICE=OFF \
    > "$probe_dir/configure.log" 2>&1 || result=$?
cat "$probe_dir/configure.log"
printf '\nCMake exit status: %s\nLogs retained in: %s\n' "$result" "$probe_dir"
if [ "$result" -eq 0 ]; then
    echo 'Configuration passed. Compilation and a running mobile session are NOT verified.'
else
    echo 'Configuration failed. No mobile shell was built or installed.' >&2
fi
exit "$result"
