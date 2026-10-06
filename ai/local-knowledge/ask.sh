#!/bin/sh
# No network acquisition: the only request target is our loopback server.
set -eu
umask 077
[ "$#" -ge 5 ] || {
    echo 'Usage: sh ask.sh MODEL FTS_QUERY QUESTION NEW_OUTPUT_DIRECTORY DOCUMENT...' >&2
    exit 2
}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
model=$1 query=$2 question=$3 output=$4
shift 4
knowledge=${KNOWLEDGE_BIN:-$here/knowledge}
port=${AI_PORT:-18081}
attempts=${AI_STARTUP_ATTEMPTS:-10}
request_timeout=${AI_REQUEST_TIMEOUT:-30}
for number in "$port" "$attempts" "$request_timeout"; do
    case "$number" in ''|0|*[!0-9]*) echo 'Timeouts and port must be positive integers.' >&2; exit 2 ;; esac
done
[ "$port" -le 65535 ] && [ "$attempts" -le 10 ] && [ "$request_timeout" -le 30 ] || {
    echo 'Port must be <=65535, startup attempts <=10, request timeout <=30.' >&2; exit 2;
}
[ -x "$knowledge" ] || { echo 'Build the knowledge executable first.' >&2; exit 2; }
mkdir "$output"
output=$(CDPATH= cd -- "$output" && pwd)
"$knowledge" index "$output/documents.db" "$@"
alias_name=emberbsd-knowledge-$$
status=0
"$knowledge" request "$output/documents.db" "$query" "$question" "$alias_name" \
    > "$output/request.json" 2> "$output/retrieval.log" || status=$?
if [ "$status" -eq 3 ]; then
    cat "$output/retrieval.log" > "$output/answer.txt"
    cat "$output/answer.txt"
    exit 3
fi
[ "$status" -eq 0 ] || { cat "$output/retrieval.log" >&2; exit "$status"; }
[ -f "$model" ] && [ -s "$model" ] || { echo 'Missing or empty local model.' >&2; exit 2; }
if [ -n "${AI_BIN:-}" ]; then PATH="$AI_BIN:$PATH"; export PATH; fi
for executable in llama-server curl; do
    command -v "$executable" >/dev/null 2>&1 || { echo "Missing executable: $executable" >&2; exit 2; }
done
server_pid=
cleanup()
{
    if [ -n "$server_pid" ]; then
        kill -TERM "$server_pid" 2>/dev/null || :
        remaining=5
        while kill -0 "$server_pid" 2>/dev/null && [ "$remaining" -gt 0 ]; do
            sleep 1
            remaining=$((remaining - 1))
        done
        kill -KILL "$server_pid" 2>/dev/null || :
        wait "$server_pid" 2>/dev/null || :
        server_pid=
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
url=http://127.0.0.1:$port
if curl --noproxy '*' --silent --max-time 1 "$url/health" -o /dev/null; then
    echo 'Port already responds; choose another AI_PORT.' >&2
    exit 1
fi
{
    uname -a
    "$knowledge" version
    printf 'threads=1\ncontext=2048\n'
    command -v llama-server
    if command -v sha256 >/dev/null 2>&1; then sha256 "$model"
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$model"
    else shasum -a 256 "$model"; fi
} > "$output/environment.txt"
nice -n 10 llama-server -m "$model" --host 127.0.0.1 --port "$port" \
    --alias "$alias_name" -c 2048 -t 1 -ngl 0 --parallel 1 \
    > "$output/server.log" 2>&1 &
server_pid=$!
ready=false
while [ "$attempts" -gt 0 ]; do
    kill -0 "$server_pid" 2>/dev/null || { echo 'Model server exited.' >&2; exit 1; }
    if curl --noproxy '*' --fail --silent --max-time 1 "$url/health" -o "$output/health.json"; then
        ready=true
        break
    fi
    attempts=$((attempts - 1))
    sleep 1
done
[ "$ready" = true ] || { echo 'Model server startup timed out.' >&2; exit 1; }
curl --noproxy '*' --fail --silent --show-error --max-time "$request_timeout" \
    --max-filesize 65536 -H 'Content-Type: application/json' \
    --data-binary "@$output/request.json" "$url/completion" -o "$output/response.json"
status=0
"$knowledge" answer "$output/documents.db" "$query" "$output/response.json" "$alias_name" \
    > "$output/answer.txt" || status=$?
cleanup
cat "$output/answer.txt"
[ "$status" -eq 0 ] || exit "$status"
printf '%s\n' 'Actual local model returned a verified quote and retrieved source.' > "$output/SUCCESS"
