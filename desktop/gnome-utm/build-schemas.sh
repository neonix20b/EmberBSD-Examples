#!/bin/sh
# Build a session-local compatibility overlay; never edit package-owned schemas.
set -eu
umask 022
PATH=/usr/pkg/bin:/usr/X11R7/bin:/bin:/usr/bin
export PATH
[ "$#" = 2 ] || { echo 'usage: sh build-schemas.sh GNOME_40_ARCHIVE EMPTY_OUTPUT_DIR' >&2; exit 1; }
archive=$1
output=$2
expected=f1b83bf023c0261eacd0ed36066b76f4a520bbcb14bb69c402b7959257125685
[ "$(sha256 -q "$archive")" = "$expected" ] || { echo 'Source archive SHA256 mismatch.' >&2; exit 1; }
mkdir -p "$output"
[ -z "$(ls -A "$output")" ] || { echo 'Output directory must be empty.' >&2; exit 1; }
scriptdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp=$(mktemp -d /tmp/emberbsd-gnome-schemas.XXXXXXXX)
trap 'rm -rf "$temp"' EXIT HUP INT TERM
tar -xJf "$archive" -C "$temp"
source=$temp/gsettings-desktop-schemas-40.0
installed=/usr/pkg/share/glib-2.0/schemas
cp "$installed"/org.gnome.desktop*.xml "$output/"
for legacy in "$source"/schemas/*.gschema.xml.in; do
    name=$(basename "$legacy" .in)
    if [ -f "$installed/$name" ]; then
        xsltproc --nonet --stringparam legacy "$legacy" \
            "$scriptdir/merge-schemas.xsl" "$installed/$name" > "$output/$name"
    else
        cp "$legacy" "$output/$name"
    fi
done
cp "$source/COPYING" "$source/AUTHORS" "$output/"
# The current schemas name fonts and wallpaper absent from this package branch.
# Session-local defaults leave explicit user preferences intact.
cat > "$output/90-emberbsd-gnome.gschema.override" <<'EOF'
[org.gnome.desktop.interface]
font-name='Cantarell 11'
monospace-font-name='DejaVu Sans Mono 10'
[org.gnome.desktop.background]
picture-uri='file:///usr/pkg/share/backgrounds/gnome/Tree.jpg'
EOF
glib-compile-schemas --strict "$output"
GSETTINGS_SCHEMA_DIR="$output" gsettings range org.gnome.desktop.wm.keybindings toggle-shaded
GSETTINGS_SCHEMA_DIR="$output" gsettings range org.gnome.desktop.interface accent-color
echo 'GNOME 40 compatibility schemas compiled successfully.'
