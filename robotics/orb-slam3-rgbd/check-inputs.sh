#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" = 5 ] || { echo 'Usage: check-inputs.sh ABS_BINARY ABS_DATA ABS_VOCABULARY ABS_SETTINGS ABS_NEW_WORK' >&2; exit 2; }
binary=$1
data=$2
vocabulary=$3
settings=$4
work=$5
for path in "$@"; do case "$path" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac; done
[ ! -e "$work" ] && [ ! -L "$work" ] || { echo 'Work already exists.' >&2; exit 2; }
mkdir "$work"
expect_failure()
{
    case_name=$1
    pattern=$2
    result=0
    "$binary" "$work/$case_name" "$vocabulary" "$settings" "$work/output-$case_name" --validate-only \
        > "$work/$case_name.log" 2>&1 || result=$?
    [ "$result" = 1 ] && grep -F "$pattern" "$work/$case_name.log" >/dev/null || {
        cat "$work/$case_name.log" >&2; echo "Unexpected result: $case_name" >&2; exit 1;
    }
    [ ! -e "$work/output-$case_name" ] || { echo 'Invalid input created results.' >&2; exit 1; }
    echo "PASS $case_name"
}
for case_name in missing-png corrupt-png bad-list; do
    mkdir "$work/$case_name"
    cp "$data/rgb.txt" "$data/groundtruth.txt" "$work/$case_name/"
    ln -s "$data/rgb" "$work/$case_name/rgb"
    ln -s "$data/depth" "$work/$case_name/depth"
done
# All selected images must exist and decode before any SLAM worker is started.
awk '/^[^#]/ && !changed { $2="missing.png"; changed=1 } { print }' "$data/depth.txt" > "$work/missing-png/depth.txt"
expect_failure missing-png 'missing image:'
awk '/^[^#]/ && !changed { $2="corrupt.png"; changed=1 } { print }' "$data/depth.txt" > "$work/corrupt-png/depth.txt"
printf 'This is not a PNG.\n' > "$work/corrupt-png/corrupt.png"
expect_failure corrupt-png 'invalid PNG:'
cp "$data/depth.txt" "$work/bad-list/depth.txt"
printf 'not-a-timestamp image.png\n' >> "$work/bad-list/rgb.txt"
expect_failure bad-list 'invalid input line'
