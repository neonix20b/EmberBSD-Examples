#!/bin/sh
set -eu
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ember-ai-fetch-test.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
mkdir "$work/bin" "$work/cache"
printf abc > "$work/fixture"
printf 'fixture\tba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\t3\tfixture.bin\thttps://example.invalid/fixture\tMIT\n' > "$work/assets.tsv"
cat > "$work/bin/curl" <<'STUB'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then
        shift
        cp "$TEST_FIXTURE" "$1"
        exit "${TEST_CURL_STATUS:-0}"
    fi
    shift
done
exit 2
STUB
chmod +x "$work/bin/curl"
PATH="$work/bin:$PATH"
ASSET_MANIFEST="$work/assets.tsv"
TEST_FIXTURE="$work/fixture"
export PATH ASSET_MANIFEST TEST_FIXTURE

sh "$recipe/fetch-assets.sh" "$work/cache" fixture
cmp "$work/fixture" "$work/cache/fixture.bin"
TEST_CURL_STATUS=7 sh "$recipe/fetch-assets.sh" "$work/cache" fixture
printf bad > "$work/cache/fixture.bin"
if sh "$recipe/fetch-assets.sh" "$work/cache" fixture; then
    echo 'Accepted a corrupt cached model.' >&2; exit 1
fi
[ "$(cat "$work/cache/fixture.bin")" = bad ]
rm "$work/cache/fixture.bin"
if TEST_CURL_STATUS=7 sh "$recipe/fetch-assets.sh" "$work/cache" fixture; then
    echo 'Accepted an interrupted download.' >&2; exit 1
fi
[ ! -e "$work/cache/fixture.bin" ]
printf bad > "$work/fixture"
if sh "$recipe/fetch-assets.sh" "$work/cache" fixture; then
    echo 'Accepted an incorrect download hash.' >&2; exit 1
fi
[ ! -e "$work/cache/fixture.bin" ]
if sh "$recipe/fetch-assets.sh" "$work/cache" unknown; then
    echo 'Accepted an unknown asset.' >&2; exit 1
fi
[ -z "$(ls -A "$work/cache")" ]
echo 'PASS: acquisition, verified reuse, corrupt cache, interruption, bad hash, unknown asset'
