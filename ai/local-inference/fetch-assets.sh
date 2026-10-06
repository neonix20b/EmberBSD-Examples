#!/bin/sh
# Explicit, checksum-verified acquisition; inference never calls this script.
set -eu
umask 077
[ "$#" -ge 1 ] || { echo 'Usage: sh fetch-assets.sh DIRECTORY [ASSET_ID ...]' >&2; exit 2; }
destination=$1
shift
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
manifest=${ASSET_MANIFEST:-$recipe/assets.tsv}
[ -f "$manifest" ] || { echo "Missing asset manifest: $manifest" >&2; exit 2; }
[ "$#" -gt 0 ] || set -- smollm2-135m whisper-tiny jfk
mkdir -p "$destination"
destination=$(CDPATH= cd -- "$destination" && pwd)
temporary=
trap '[ -z "$temporary" ] || rm -f "$temporary"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

hash()
{
    if command -v sha256 >/dev/null 2>&1; then
        sha256 -q "$1"
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{ print $1 }'
    else
        shasum -a 256 "$1" | awk '{ print $1 }'
    fi
}

verify()
{
    [ -f "$1" ] && [ ! -L "$1" ] &&
        [ "$(wc -c < "$1" | tr -d '[:space:]')" = "$bytes" ] &&
        [ "$(hash "$1")" = "$expected" ]
}

for requested in "$@"; do
    record=$(awk -F '\t' -v id="$requested" '$1 == id { print; count++ } END { if (count != 1) exit 1 }' "$manifest") || {
        echo "Unknown or duplicate asset: $requested" >&2; exit 2
    }
    IFS="$(printf '\t')" read -r asset expected bytes filename url license <<EOF
$record
EOF
    case "$expected" in ''|*[!a-f0-9]*) echo 'Invalid SHA256 in manifest.' >&2; exit 2 ;; esac
    [ "${#expected}" -eq 64 ] || { echo 'Invalid SHA256 length.' >&2; exit 2; }
    case "$bytes" in ''|0|*[!0-9]*) echo 'Invalid byte count.' >&2; exit 2 ;; esac
    case "$filename" in ''|.*|*[!a-zA-Z0-9_.-]*) echo 'Invalid asset filename.' >&2; exit 2 ;; esac
    case "$url" in https://*) ;; *) echo 'Asset URL must use HTTPS.' >&2; exit 2 ;; esac
    target=$destination/$filename
    if [ -e "$target" ] || [ -L "$target" ]; then
        verify "$target" || { echo "Corrupt cached asset; preserve and inspect: $target" >&2; exit 1; }
        printf 'Verified existing %s (%s)\n' "$asset" "$license"
        continue
    fi
    temporary=$(mktemp "$destination/.download.XXXXXXXX")
    curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 1800 "$url" -o "$temporary"
    verify "$temporary" || { echo "Size or SHA256 mismatch: $asset" >&2; exit 1; }
    # Link without overwriting: a concurrent downloader may have finished first.
    if ! ln "$temporary" "$target" 2>/dev/null; then
        verify "$target" || { echo "Destination changed during download: $target" >&2; exit 1; }
    fi
    rm -f "$temporary"
    temporary=
    printf 'Verified %s (%s)\n' "$asset" "$license"
done
