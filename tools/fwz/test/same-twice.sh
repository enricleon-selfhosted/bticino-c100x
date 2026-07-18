#!/bin/sh
# shellcheck shell=dash
set -eu

STOCK="${1:?usage: same-twice.sh <stock.fwz>}"
FWZ="${FWZ:-./build/fwz}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf 'mkdir\t/opt\t0755\t0\t0\nmkdir\t/opt/intercom\t0755\t0\t0\n' > "$TMP/changes.txt"

for run in 1 2; do
    mkdir -p "$TMP/w$run"
    "$FWZ" build --in "$STOCK" --out "$TMP/out$run.fwz" --model C100X \
                 --changes "$TMP/changes.txt" --work "$TMP/w$run" >/dev/null
    printf '   run %s: %s\n' "$run" "$(md5sum "$TMP/out$run.fwz" | cut -d' ' -f1)"
done

if cmp -s "$TMP/out1.fwz" "$TMP/out2.fwz"; then
    echo "   same both times"
else
    echo "   they differ -- something is writing memory into the image again"
    exit 1
fi
