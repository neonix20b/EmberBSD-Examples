#!/bin/sh
set -eu
recipe=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ember-ai-server-test.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
mkdir "$work/bin" "$work/assets"
for asset in SmolLM2-135M-Instruct-Q4_K_M.gguf ggml-tiny.bin jfk.wav; do
    printf fixture > "$work/assets/$asset"
done
cat > "$work/bin/llama-completion" <<'STUB'
#!/bin/sh
echo 'A generated answer'
STUB
cat > "$work/bin/whisper-cli" <<'STUB'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    if [ "$1" = -of ]; then
        shift
        echo 'A recognized sentence' > "$1.txt"
        exit 0
    fi
    shift
done
exit 2
STUB
cat > "$work/bin/llama-server" <<'STUB'
#!/bin/sh
echo $$ > "$TEST_PID_FILE"
trap 'exit 0' TERM INT
while :; do sleep 1; done
STUB
printf '#!/bin/sh\nexit 7\n' > "$work/bin/curl"
chmod +x "$work/bin/"*
AI_BIN=$work/bin
TEST_PID_FILE=$work/server.pid
export AI_BIN TEST_PID_FILE
if AI_STARTUP_ATTEMPTS=1 sh "$recipe/smoke.sh" "$work/assets" "$work/timeout"; then
    echo 'Accepted an unavailable server.' >&2; exit 1
fi
[ ! -e "$work/timeout/SUCCESS" ]
server=$(cat "$TEST_PID_FILE")
if kill -0 "$server" 2>/dev/null; then echo 'Timeout leaked a server.' >&2; exit 1; fi
rm "$TEST_PID_FILE"
sh "$recipe/smoke.sh" "$work/assets" "$work/cancel" &
runner=$!
remaining=10
while [ ! -s "$TEST_PID_FILE" ] && [ "$remaining" -gt 0 ]; do
    sleep 1
    remaining=$((remaining - 1))
done
[ -s "$TEST_PID_FILE" ] || { kill "$runner"; echo 'Server fixture never started.' >&2; exit 1; }
kill -TERM "$runner"
status=0
wait "$runner" || status=$?
[ "$status" -ne 0 ]
server=$(cat "$TEST_PID_FILE")
if kill -0 "$server" 2>/dev/null; then echo 'Cancellation leaked a server.' >&2; exit 1; fi
[ ! -e "$work/cancel/SUCCESS" ]
echo 'PASS: startup timeout and cancellation stop the owned server'
