#!/bin/sh
# Run on the ROS host after sourcing ROS and the example's install setup.
set -eu
[ "$#" = 3 ] || { echo 'Usage: smoke-ros.sh BIN_DIRECTORY tcp/DEVICE:PORT NEW_RESULTS' >&2; exit 2; }
bin=$1
endpoint=$2
output=$3
[ -x "$bin/robot-bridge" ] && [ -x "$bin/robot-probe" ]
command -v timeout >/dev/null
mkdir "$output"
bridge=
cleanup() {
    if [ -n "$bridge" ]; then
        kill -CONT "$bridge" 2>/dev/null || :
        kill -TERM "$bridge" 2>/dev/null || :
        n=0
        while kill -0 "$bridge" 2>/dev/null && [ "$n" -lt 5 ]; do
            sleep 1
            n=$((n + 1))
        done
        kill -KILL "$bridge" 2>/dev/null || :
        wait "$bridge" 2>/dev/null || :
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-86}
RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}
export ROS_DOMAIN_ID RMW_IMPLEMENTATION
{
    uname -a
    printf 'ROS_DISTRO=%s\nROS_DOMAIN_ID=%s\nRMW_IMPLEMENTATION=%s\n' \
        "${ROS_DISTRO:-unset}" "$ROS_DOMAIN_ID" "$RMW_IMPLEMENTATION"
} > "$output/environment.txt"
"$bin/robot-bridge" "$endpoint" > "$output/bridge.log" 2>&1 &
bridge=$!
timeout 80 "$bin/robot-probe" --save "$output/old-command.bin" > "$output/initial.log" 2>&1
kill -0 "$bridge"
# Stop both transport threads and ROS callbacks beyond the default 10 s lease.
# The bridge must recover without process restart after being continued.
kill -STOP "$bridge"
sleep 22
kill -CONT "$bridge"
timeout 80 "$bin/robot-probe" --reconnect "$output/old-command.bin" > "$output/reconnect.log" 2>&1
kill -0 "$bridge"
cleanup
bridge=
printf 'PASS: ROS round trip, command rejection and peer recovery\n' > "$output/SUCCESS"
cat "$output/SUCCESS"
