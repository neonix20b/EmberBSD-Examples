#!/bin/sh
set -eu
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ember-ai-smoke-test.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
mkdir "$work/bin" "$work/assets"
for executable in llama-completion llama-server whisper-cli; do
    printf '#!/bin/sh\nexit 37\n' > "$work/bin/$executable"
    chmod +x "$work/bin/$executable"
done
if AI_BIN="$work/bin" sh "$recipe/smoke.sh" "$work/assets" "$work/missing"; then
    echo 'Accepted missing models.' >&2; exit 1
fi
[ ! -e "$work/missing/SUCCESS" ]
printf model > "$work/assets/SmolLM2-135M-Instruct-Q4_K_M.gguf"
printf model > "$work/assets/ggml-tiny.bin"
printf wav > "$work/assets/jfk.wav"
status=0
AI_BIN="$work/bin" sh "$recipe/smoke.sh" "$work/assets" "$work/failed" || status=$?
[ "$status" -eq 37 ] || { echo "Engine status was lost: $status" >&2; exit 1; }
[ ! -e "$work/failed/SUCCESS" ]
if AI_BIN="$work/bin" AI_PORT=0 sh "$recipe/smoke.sh" "$work/assets" "$work/bad-port"; then
    echo 'Accepted port zero.' >&2; exit 1
fi
echo 'PASS: missing inputs, engine exit status, invalid port, no false success'
