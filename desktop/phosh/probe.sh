#!/bin/sh
# Build private prerequisites and attempt a native Phosh build.
set -eu
umask 077
PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/bin
LANG=C.UTF-8
export PATH LANG

[ "$#" -le 1 ] || { echo 'Usage: sh probe.sh [archive-directory]' >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || { echo 'Run on EmberBSD/NetBSD.' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as an ordinary user.' >&2; exit 2; }
for tool in cc meson ninja pkg-config tar patch sha256 glib-mkenums gdbus-codegen; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
python=${PYTHON:-/usr/pkg/bin/python3.13}
[ -x "$python" ] || { echo 'Set PYTHON to an absolute Python 3 interpreter path.' >&2; exit 2; }
case "$python" in /*) ;; *) echo 'PYTHON must be an absolute path.' >&2; exit 2 ;; esac
jobs=${JOBS:-3}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be a positive integer.' >&2; exit 2 ;; esac
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
archive_dir=${1:-}
mkdir -p "$HOME/.cache"
probe_dir=$(mktemp -d "$HOME/.cache/emberbsd-phosh.XXXXXXXX")
printf 'Probe directory: %s\n' "$probe_dir"
mkdir "$probe_dir/tools"
ln -s "$python" "$probe_dir/tools/python3"
PATH="$probe_dir/tools:$PATH"
PKG_CONFIG_PATH="$probe_dir/install/lib/pkgconfig:/usr/pkg/lib/pkgconfig:/usr/pkg/share/pkgconfig"
LD_LIBRARY_PATH="$probe_dir/install/lib:/usr/pkg/lib"
export PATH PKG_CONFIG_PATH LD_LIBRARY_PATH
unset GMOBILE_DT_COMPATIBLES

run()
{
    stage=$1
    shift
    printf '%s ...\n' "$stage"
    status=0
    "$@" > "$probe_dir/$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        cat "$probe_dir/$stage.log"
        printf '\n%s failed (%s). Logs: %s\n' "$stage" "$status" "$probe_dir" >&2
        echo 'No Phosh shell has been built or installed.' >&2
        exit "$status"
    fi
}

source_archive()
{
    name=$1
    url=$2
    expected=$3
    archive="$probe_dir/$name.tar.xz"
    if [ -n "$archive_dir" ]; then
        cp "$archive_dir/$name.tar.xz" "$archive"
    else
        command -v curl >/dev/null || { echo 'Missing tool: curl' >&2; exit 2; }
        curl -fLsS --connect-timeout 20 --max-time 300 "$url" -o "$archive"
    fi
    actual=$(sha256 -q "$archive")
    [ "$actual" = "$expected" ] || { echo "Source SHA256 mismatch: $name" >&2; exit 2; }
    printf '%s  %s\nSource: %s\n' "$actual" "$name.tar.xz" "$url" >> "$probe_dir/sources.txt"
    tar -xJf "$archive" -C "$probe_dir"
}

{
    uname -srvm
    cc --version
    meson --version
    "$python" --version
    /usr/sbin/pkg_info
    printf '\nDependency inventory before the private builds:\n'
    for dep in gnome-bluetooth-3.0 gmobile gtk+-wayland-3.0 libfeedback-0.0 libnm mm-glib libsystemd libelogind; do
        printf '%s: ' "$dep"
        pkg-config --modversion "$dep" || :
    done
} > "$probe_dir/environment.txt" 2>&1

source_archive phosh-0.58.0 \
    https://sources.phosh.mobi/releases/phosh/phosh-0.58.0.tar.xz \
    b936af34ebed15b29d4f941c48aa328a47da9c2e51cbf6ef89040a90f522ed73
source_archive gnome-bluetooth-46.2 \
    https://download.gnome.org/sources/gnome-bluetooth/46/gnome-bluetooth-46.2.tar.xz \
    1b48feec75b8b4f1a6e564cce7cc4ebd35b3225cb8d8be93c8efc44894003635
source_archive gmobile-0.1.0 \
    https://sources.phosh.mobi/releases/gmobile/gmobile-0.1.0.tar.xz \
    47172e7b245fbb30b40c02135d2ff36987e36a8e825f9bf5932acd2aa6eabfcd

run bluetooth-setup meson setup "$probe_dir/bluetooth-build" "$probe_dir/gnome-bluetooth-46.2" \
    --prefix="$probe_dir/install" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dsendto=false -Dgtk_doc=false -Dintrospection=false
run bluetooth-build meson compile -C "$probe_dir/bluetooth-build" -j "$jobs"
run bluetooth-test meson test -C "$probe_dir/bluetooth-build" --no-rebuild --print-errorlogs
run bluetooth-install meson install -C "$probe_dir/bluetooth-build" --no-rebuild

# Correct a Linux-only test expectation; the library implementation is unchanged.
cp "$script_dir/gmobile-device-tree-test.patch" "$probe_dir/"
run gmobile-patch patch -d "$probe_dir/gmobile-0.1.0" -p1 < "$probe_dir/gmobile-device-tree-test.patch"
run gmobile-setup meson setup "$probe_dir/gmobile-build" "$probe_dir/gmobile-0.1.0" \
    --prefix="$probe_dir/install" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dexamples=false -Dtests=true -Dgtk_doc=false -Dintrospection=false
run gmobile-build meson compile -C "$probe_dir/gmobile-build" -j "$jobs"
run gmobile-test meson test -C "$probe_dir/gmobile-build" --no-rebuild --print-errorlogs
run gmobile-install meson install -C "$probe_dir/gmobile-build" --no-rebuild

run phosh-setup meson setup "$probe_dir/phosh-build" "$probe_dir/phosh-0.58.0" \
    --prefix="$probe_dir/install" --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dtests=false -Dphoc_tests=disabled -Dgtk_doc=false -Dman=false
run phosh-build meson compile -C "$probe_dir/phosh-build" -j "$jobs"
printf 'Phosh compiled. It was not installed or run. Logs: %s\n' "$probe_dir"
