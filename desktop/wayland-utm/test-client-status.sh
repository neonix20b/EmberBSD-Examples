#!/bin/sh
# Exercise the actual client wrapper with a process that exits predictably.
set -eu
umask 077
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d /tmp/emberbsd-client-status.XXXXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/success" "$work/failure"
cat > "$work/client.c" <<'EOF'
#include <stdlib.h>
int main(void) { return atoi(getenv("CLIENT_STATUS")); }
EOF
cc -Wall -Wextra -Werror "$work/client.c" -o "$work/bin/kate"
ln -s kate "$work/bin/labwc"
PATH="$work/bin:$PATH"
export PATH
CLIENT_STATUS=0 sh "$here/client.sh" "$work/success"
[ "$(cat "$work/success/client.status")" = 0 ]
status=0
CLIENT_STATUS=17 sh "$here/client.sh" "$work/failure" || status=$?
[ "$status" -eq 17 ]
[ "$(cat "$work/failure/client.status")" = 17 ]
echo 'PASS: actual client wrapper preserves success and failure status'
