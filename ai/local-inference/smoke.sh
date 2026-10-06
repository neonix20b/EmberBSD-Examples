#!/bin/sh
# Run only local model files. Fetching is a separate, explicit operation.
set -eu
umask 077
[ "$#" -eq 2 ] || { echo 'Usage: sh smoke.sh ASSET_DIRECTORY NEW_RESULT_DIRECTORY' >&2; exit 2; }
assets=$(CDPATH= cd -- "$1" && pwd)
output=$2
threads=${AI_THREADS:-2}
port=${AI_PORT:-18080}
attempts=${AI_STARTUP_ATTEMPTS:-60}
for number in "$threads" "$port" "$attempts"; do
    case "$number" in ''|0|*[!0-9]*) echo 'Threads, port and startup attempts must be positive integers.' >&2; exit 2 ;; esac
done
[ "$port" -le 65535 ] || { echo 'Port is out of range.' >&2; exit 2; }
if [ -n "${AI_BIN:-}" ]; then
    PATH="$AI_BIN:$PATH"
    export PATH
fi
for executable in llama-completion llama-server whisper-cli curl; do
    command -v "$executable" >/dev/null 2>&1 || { echo "Missing executable: $executable" >&2; exit 2; }
done
model=${AI_TEXT_MODEL:-$assets/SmolLM2-135M-Instruct-Q4_K_M.gguf}
speech_model=${AI_SPEECH_MODEL:-$assets/ggml-tiny.bin}
audio=${AI_AUDIO:-$assets/jfk.wav}
for input in "$model" "$speech_model" "$audio"; do
    [ -s "$input" ] || { echo "Missing or empty input: $input" >&2; exit 2; }
done
mkdir "$output"
output=$(CDPATH= cd -- "$output" && pwd)
server_pid=
cleanup()
{
    if [ -n "$server_pid" ]; then
        kill -TERM "$server_pid" 2>/dev/null || :
        remaining=10
        while kill -0 "$server_pid" 2>/dev/null && [ "$remaining" -gt 0 ]; do
            sleep 1
            remaining=$((remaining - 1))
        done
        kill -KILL "$server_pid" 2>/dev/null || :
        wait "$server_pid" 2>/dev/null || :
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
{
    uname -a
    printf 'threads=%s\nport=%s\ntext_model=%s\nspeech_model=%s\naudio=%s\n' \
        "$threads" "$port" "$model" "$speech_model" "$audio"
    command -v llama-completion
    command -v whisper-cli
} > "$output/environment.txt"
for input in "$model" "$speech_model" "$audio"; do
    if command -v sha256 >/dev/null 2>&1; then
        sha256 "$input"
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$input"
    else
        shasum -a 256 "$input"
    fi
done > "$output/inputs.sha256"

# NetBSD time -l reports elapsed time and maximum resident set size.
timed()
{
    if [ "$(uname -s)" = NetBSD ]; then
        /usr/bin/time -l "$@"
    else
        command time -p "$@"
    fi
}
timed llama-completion -m "$model" -p 'The capital of France is' \
    -n 24 -c 512 -t "$threads" -ngl 0 --seed 1 --temp 0 --no-display-prompt --no-conversation \
    < /dev/null > "$output/text.txt" 2> "$output/text.log"
grep '[[:alnum:]]' "$output/text.txt" >/dev/null || { echo 'No generated text.' >&2; exit 1; }
timed whisper-cli -m "$speech_model" -f "$audio" -l en -t "$threads" -ng \
    -otxt -of "$output/transcript" > "$output/speech.stdout" 2> "$output/speech.log"
grep '[[:alnum:]]' "$output/transcript.txt" >/dev/null || { echo 'No transcript.' >&2; exit 1; }

url=http://127.0.0.1:$port
if curl --noproxy '*' --silent --max-time 2 "$url/health" -o /dev/null; then
    echo "Port already responds; choose another AI_PORT: $port" >&2
    exit 1
fi
alias_name=emberbsd-smoke-$$
llama-server -m "$model" --host 127.0.0.1 --port "$port" --alias "$alias_name" \
    -c 512 -t "$threads" -ngl 0 --parallel 1 > "$output/server.log" 2>&1 &
server_pid=$!
ready=false
while [ "$attempts" -gt 0 ]; do
    kill -0 "$server_pid" 2>/dev/null || { echo "Server exited; read $output/server.log" >&2; exit 1; }
    if curl --noproxy '*' --fail --silent --max-time 2 "$url/health" -o "$output/health.json"; then
        ready=true
        break
    fi
    attempts=$((attempts - 1))
    sleep 1
done
[ "$ready" = true ] || { echo 'Server startup timed out.' >&2; exit 1; }
curl --noproxy '*' --fail --silent --show-error --max-time 120 \
    -H 'Content-Type: application/json' \
    -d '{"prompt":"The capital of France is","n_predict":16,"temperature":0,"seed":1,"stream":false}' \
    "$url/completion" -o "$output/completion.json"
grep -E '"tokens_predicted"[[:space:]]*:[[:space:]]*[1-9][0-9]*' "$output/completion.json" >/dev/null
grep -F "$alias_name" "$output/completion.json" >/dev/null
cleanup
server_pid=
printf 'Text generation, file transcription and loopback HTTP inference passed.\n' > "$output/SUCCESS"
cat "$output/SUCCESS"
