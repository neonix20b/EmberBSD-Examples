#!/bin/sh
# Deterministic contract fixtures, not evidence of model inference.
set -eu
umask 077
[ "$#" -eq 1 ] || { echo 'Usage: sh tests/contracts.sh KNOWLEDGE_EXECUTABLE' >&2; exit 2; }
knowledge=$1
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ember-knowledge-contracts.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
fail() { echo "FAIL: $*" >&2; exit 1; }
reject()
{
    if "$@" > "$work/rejected.stdout" 2> "$work/rejected.stderr"; then
        fail "command unexpectedly passed: $*"
    fi
}
"$knowledge" index "$work/docs.db" "$here/documents/pump.txt" "$here/documents/sensor.txt"
"$knowledge" request "$work/docs.db" pump 'What is the pump interval?' fixture > "$work/request.json"
grep -F 'The amber pump service interval is seven days.' "$work/request.json" >/dev/null
if grep -F 'violet sensor' "$work/request.json" >/dev/null; then fail 'unmatched evidence included'; fi
status=0
"$knowledge" request "$work/docs.db" nonexistent 'Unknown?' fixture > "$work/absent.json" 2>/dev/null || status=$?
[ "$status" -eq 3 ] && [ ! -s "$work/absent.json" ] || fail 'missing evidence did not refuse'
reject "$knowledge" request "$work/docs.db" '"' 'Malformed?' fixture
reject "$knowledge" index "$work/docs.db" "$here/documents/pump.txt"
reject "$knowledge" index "$work/missing.db" "$work/missing.txt"
mkfifo "$work/pipe"
reject "$knowledge" index "$work/fifo.db" "$work/pipe"
printf 'binary\000data\n' > "$work/binary.txt"
reject "$knowledge" index "$work/binary.db" "$work/binary.txt"
dd if=/dev/zero of="$work/large.txt" bs=2049 count=1 2>/dev/null
reject "$knowledge" index "$work/large.db" "$work/large.txt"
cat > "$work/good.json" <<'EOF'
{"model":"fixture","truncated":false,"tokens_predicted":20,"content":"{\"source\":1,\"quote\":\"The amber pump service interval is seven days.\"}"}
EOF
"$knowledge" answer "$work/docs.db" pump "$work/good.json" fixture > "$work/answer.txt"
grep -F 'Source [1]:' "$work/answer.txt" >/dev/null
sed 's/seven days/eight days/' "$work/good.json" > "$work/bad.json"
reject "$knowledge" answer "$work/docs.db" pump "$work/bad.json" fixture
sed 's/source\\":1/source\\":2/' "$work/good.json" > "$work/bad.json"
reject "$knowledge" answer "$work/docs.db" pump "$work/bad.json" fixture
reject "$knowledge" answer "$work/docs.db" sensor "$work/good.json" fixture
reject "$knowledge" answer "$work/docs.db" pump "$work/good.json" another-server
sed 's/"truncated":false/"truncated":true/' "$work/good.json" > "$work/bad.json"
reject "$knowledge" answer "$work/docs.db" pump "$work/bad.json" fixture
printf 'invalid JSON' > "$work/bad.json"
reject "$knowledge" answer "$work/docs.db" pump "$work/bad.json" fixture
cat > "$work/bad.json" <<'EOF'
{"model":"fixture","truncated":false,"tokens_predicted":20,"content":"{\"source\":1,\"quote\":\"The amber pump service interval is seven days.\\u0000invented\"}"}
EOF
reject "$knowledge" answer "$work/docs.db" pump "$work/bad.json" fixture
cat > "$work/refused.json" <<'EOF'
{"model":"fixture","truncated":false,"tokens_predicted":10,"content":"{\"source\":0,\"quote\":\"\"}"}
EOF
status=0
"$knowledge" answer "$work/docs.db" pump "$work/refused.json" fixture > "$work/refused.txt" || status=$?
[ "$status" -eq 3 ] || fail 'model refusal was not preserved'
status=0
KNOWLEDGE_BIN="$knowledge" sh "$here/ask.sh" "$work/no-model" nonexistent 'Unknown?' \
    "$work/no-evidence" "$here/documents/pump.txt" > "$work/absent.txt" || status=$?
[ "$status" -eq 3 ] || fail 'wrapper did not preserve absence'
[ ! -e "$work/no-evidence/server.log" ] && [ ! -e "$work/no-evidence/SUCCESS" ] || fail 'absence started model/reported success'
mkdir "$work/bin"
cat > "$work/bin/llama-server" <<'EOF'
#!/bin/sh
exit 17
EOF
cat > "$work/bin/curl" <<'EOF'
#!/bin/sh
exit 7
EOF
chmod +x "$work/bin/llama-server" "$work/bin/curl"
printf 'fixture, not a model\n' > "$work/model"
reject env KNOWLEDGE_BIN="$knowledge" AI_BIN="$work/bin" AI_STARTUP_ATTEMPTS=1 \
    sh "$here/ask.sh" "$work/model" pump 'Interval?' "$work/dead-server" "$here/documents/pump.txt"
[ ! -e "$work/dead-server/SUCCESS" ] || fail 'dead server produced success'
cat > "$work/bin/llama-server" <<'EOF'
#!/bin/sh
echo $$ > "$TEST_SERVER_PID"
exec sleep 300
EOF
reject env KNOWLEDGE_BIN="$knowledge" AI_BIN="$work/bin" AI_STARTUP_ATTEMPTS=1 \
    TEST_SERVER_PID="$work/server.pid" sh "$here/ask.sh" "$work/model" pump 'Interval?' \
    "$work/timeout" "$here/documents/pump.txt"
[ ! -e "$work/timeout/SUCCESS" ] || fail 'timeout produced success'
[ -f "$work/server.pid" ] || fail 'lifecycle fixture did not start'
if kill -0 "$(cat "$work/server.pid")" 2>/dev/null; then fail 'owned server survived timeout'; fi
echo 'PASS: retrieval, absent evidence, invalid inputs, forged citations, server failure/timeout cleanup (fixtures only)'
