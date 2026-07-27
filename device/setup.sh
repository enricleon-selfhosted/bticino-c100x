#!/bin/sh
# shellcheck shell=dash
set -u

SELF="$0"
[ -L "$SELF" ] && SELF="$(readlink -f "$SELF" 2>/dev/null || echo "$SELF")"
OPT="$(cd "$(dirname "$SELF")" && pwd)"
export OPT

. "$OPT/converge.d/common.sh"

say "=== setup starting ==="

for step in "$OPT"/converge.d/[0-9]*; do
    [ -f "$step" ] || continue
    sh "$step"
    case "$?" in
        0)  ;;
        10) say "=== setup finished (waiting for provisioning) ==="; trim_log; exit 0 ;;
        *)  say "WARNING: $(basename "$step") did not finish cleanly; carrying on" ;;
    esac
done

say "=== setup finished ==="
trim_log
exit 0
