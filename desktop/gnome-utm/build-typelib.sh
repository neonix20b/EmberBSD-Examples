#!/bin/sh
# Repair a private copy of the tested GNOME Shell 40 GIR; keep package files intact.
set -eu
umask 022
PATH=/usr/pkg/bin:/usr/pkg/sbin:/bin:/usr/bin
export PATH
[ "$#" = 1 ] || { echo 'usage: sh build-typelib.sh EMPTY_OUTPUT_DIR' >&2; exit 1; }
pkg_info -e 'gnome-shell-40.2*' >/dev/null
output=$1
mkdir -p "$output"
[ -z "$(ls -A "$output")" ] || { echo 'Output directory must be empty.' >&2; exit 1; }
scriptdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
xsltproc --nonet "$scriptdir/fix-shell-gir.xsl" \
    /usr/pkg/share/gnome-shell/Shell-0.1.gir > "$output/Shell-0.1.gir"
g-ir-compiler --includedir=/usr/pkg/share/gnome-shell \
    --includedir=/usr/pkg/lib/mutter-8 --includedir=/usr/pkg/share/gir-1.0 \
    "$output/Shell-0.1.gir" -o "$output/Shell-0.1.typelib"
GI_TYPELIB_PATH="$output:/usr/pkg/lib/gnome-shell:/usr/pkg/lib/mutter-8"
LD_LIBRARY_PATH=/usr/pkg/lib/gnome-shell:/usr/pkg/lib/mutter-8
export GI_TYPELIB_PATH LD_LIBRARY_PATH
gjs -c 'const Shell = imports.gi.Shell;
if (typeof Shell.App.prototype.get_app_info !== "function" || !("app_info" in Shell.App.prototype))
    throw new Error("Shell.App app_info introspection is missing");
print("Shell.App app_info introspection passed.");'
