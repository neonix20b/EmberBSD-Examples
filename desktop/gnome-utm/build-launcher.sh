#!/bin/sh
# Rebuild only upstream GNOME Shell's C launcher against installed libraries.
set -eu
umask 022
PATH=/usr/pkg/bin:/usr/pkg/sbin:/bin:/usr/bin
export PATH
[ "$#" = 2 ] || { echo 'usage: sh build-launcher.sh GNOME_SHELL_ARCHIVE EMPTY_OUTPUT_DIR' >&2; exit 1; }
pkg_info -e 'gnome-shell-40.2*' >/dev/null
archive=$1
output=$2
expected=4e9d829b039fa0add33bb6583fc7b4e028ed8dcff7af8a577e09cc66988c281c
[ "$(sha256 -q "$archive")" = "$expected" ] || { echo 'Source archive SHA256 mismatch.' >&2; exit 1; }
mkdir -p "$output"
[ -z "$(ls -A "$output")" ] || { echo 'Output directory must be empty.' >&2; exit 1; }
scriptdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp=$(mktemp -d /tmp/emberbsd-gnome-launcher.XXXXXXXX)
trap 'rm -rf "$temp"' EXIT HUP INT TERM
tar -xJf "$archive" -C "$temp"
source=$temp/gnome-shell-40.2
patch -d "$source" -p0 < "$scriptdir/netbsd-main.patch"
patch -d "$source" -p0 < "$scriptdir/launcher-typelib.patch"
cat > "$source/config.h" <<'EOF'
#define GETTEXT_PACKAGE "gnome-shell"
#define VERSION "40.2"
#define PACKAGE_VERSION "40.2"
#define LOCALEDIR "/usr/pkg/share/locale"
#define GNOME_SHELL_PKGLIBDIR "/usr/pkg/lib/gnome-shell"
#define MUTTER_TYPELIB_DIR "/usr/pkg/lib/mutter-8"
#define CLUTTER_ENABLE_EXPERIMENTAL_API
#define COGL_ENABLE_EXPERIMENTAL_API
EOF
# pkg-config emits compiler arguments, intentionally subject to word splitting.
# Match the installed NetBSD libraries' native gettext ABI, not pkgsrc libintl.8.
cc -O2 -I"$source" -I"$source/src" "$source/src/main.c" \
    $(pkg-config --cflags --libs libmutter-8 mutter-clutter-x11-8 \
        mutter-cogl-pango-8 gjs-1.0 gobject-introspection-1.0 gtk+-3.0 atk-bridge-2.0 | \
        sed 's/-lintl/\/usr\/lib\/libintl.so.1/g') \
    -L/usr/pkg/lib/gnome-shell -lgnome-shell -lst-1.0 \
    -Wl,-rpath,/usr/pkg/lib/gnome-shell -Wl,-rpath,/usr/pkg/lib/mutter-8 \
    -Wl,-rpath,/usr/pkg/lib -o "$output/gnome-shell"
cp "$source/COPYING" "$output/"
"$output/gnome-shell" --version
