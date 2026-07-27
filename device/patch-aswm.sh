#!/bin/sh
# shellcheck shell=dash
set -u

SRC="${1:-}"
DST="${2:-}"

if [ -z "$SRC" ] || [ -z "$DST" ]; then
    echo "usage: patch-aswm.sh <original> <patched>" >&2
    exit 2
fi
[ -r "$SRC" ] || { echo "cannot read $SRC" >&2; exit 2; }

WORK="${TMPDIR:-/var/tmp}/patch-aswm.$$"
mkdir -p "$WORK" || { echo "cannot make a working directory" >&2; exit 2; }
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

HEX="$WORK/hex"
PLAN="$WORK/plan"

to_hex() {
    od -An -v -tx1 "$1" | tr -d ' \n' > "$HEX"
}

PATCHES="
start the phone service anyway (inner check)|000053e30500001a0130a0e30400a0e1183285e5|7|ea
start the phone service anyway (outer check)|0c3194e5000053e31100001a043095e5|8|0000a0e1
hand the ring to the local service|003091e5011002e22900000a000051e3|8|0000a0e1
stop the phone ports being switched off|080bcded0a1bcded8844ffeb0800a0e1|8|0000a0e1
"

find_hex() {
    awk -v p="$1" '
        {
            n = 0; pos = 0; start = 1
            while ((i = index(substr($0, start), p)) > 0) {
                pos = start + i - 1
                n++
                start = pos + 1
            }
            print n, pos
        }' "$HEX"
}

patched_form() {
    awk -v p="$1" -v d="$2" -v r="$3" \
        'BEGIN { print substr(p, 1, 2 * d) r substr(p, 2 * d + length(r) + 1) }'
}

write_hex_at() {
    _hex="$1"; _at="$2"; _file="$3"
    while [ -n "$_hex" ]; do
        _pair=$(printf '%s' "$_hex" | cut -c1-2)
        _hex=$(printf '%s' "$_hex" | cut -c3-)
        printf "\\$(printf '%03o' $((0x$_pair)))" \
            | dd of="$_file" bs=1 seek="$_at" conv=notrunc 2>/dev/null || return 1
        _at=$((_at + 1))
    done
    return 0
}

cat "$SRC" > "$DST" || { echo "cannot write $DST" >&2; exit 2; }
SIZE=$(wc -c < "$DST")
echo "read $SIZE bytes from $SRC"

to_hex "$DST"

: > "$PLAN"

echo "$PATCHES" | while IFS='|' read -r name pattern delta repl; do
    [ -n "$name" ] || continue
    # shellcheck disable=SC2046
    set -- $(find_hex "$pattern")
    hits=$1; pos=$2

    if [ "$hits" = "0" ]; then
        done_form=$(patched_form "$pattern" "$delta" "$repl")
        # shellcheck disable=SC2046
        set -- $(find_hex "$done_form")
        if [ "$1" = "1" ]; then
            printf 'same|%s|0|0\n' "$name" >> "$PLAN"
            continue
        fi
    fi

    if [ "$hits" != "1" ]; then
        printf 'stop|%s|%s|0\n' "$name" "$hits" >> "$PLAN"
        continue
    fi

    if [ $(( (pos - 1) % 2 )) -ne 0 ]; then
        printf 'stop|%s|misaligned|0\n' "$name" >> "$PLAN"
        continue
    fi

    at=$(( (pos - 1) / 2 + delta ))
    printf 'do|%s|%s|%s\n' "$name" "$at" "$repl" >> "$PLAN"
    printf '  found  %-42s at 0x%x\n' "$name" "$(( (pos - 1) / 2 ))"
done

if grep -q '^stop|' "$PLAN" 2>/dev/null; then
    echo "STOP: this firmware is not one the patterns were written for."
    grep '^stop|' "$PLAN" | while IFS='|' read -r _ name detail _; do
        echo "      '$name' matched $detail times, expected exactly one."
    done
    echo "      Nothing has been written. The unit keeps its original program."
    rm -f "$DST"
    exit 1
fi

FOUND=$(grep -c '^do|' "$PLAN" 2>/dev/null)
SAME=$(grep -c '^same|' "$PLAN" 2>/dev/null)
: "${FOUND:=0}" "${SAME:=0}"
if [ "$(( FOUND + SAME ))" != "4" ]; then
    echo "STOP: found $(( FOUND + SAME )) of the four places, expected all four."
    rm -f "$DST"
    exit 1
fi

while IFS='|' read -r kind name at repl; do
    case "$kind" in
        same) printf '  same   %-42s already patched\n' "$name" ;;
        do)
            if write_hex_at "$repl" "$at" "$DST"; then
                printf '  wrote  %-42s 0x%x: %s\n' "$name" "$at" "$repl"
            else
                echo "STOP: could not write $name"
                rm -f "$DST"
                exit 1
            fi
            ;;
    esac
done < "$PLAN"

NEWSIZE=$(wc -c < "$DST")
if [ "$NEWSIZE" != "$SIZE" ]; then
    echo "STOP: the file came back $NEWSIZE bytes, not $SIZE"
    rm -f "$DST"
    exit 1
fi

to_hex "$DST"
BAD=0
while IFS='|' read -r kind name at repl; do
    [ "$kind" = "do" ] || continue
    got=$(cut -c$(( at * 2 + 1 ))-$(( at * 2 + ${#repl} )) "$HEX")
    if [ "$got" != "$repl" ]; then
        echo "STOP: $name did not stick: wanted $repl, found $got"
        BAD=1
    fi
done < "$PLAN"

if [ "$BAD" != "0" ]; then
    rm -f "$DST"
    exit 1
fi

echo "wrote $NEWSIZE bytes to $DST"
echo "all four verified in the written file"
exit 0
