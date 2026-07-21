#!/bin/sh
# shellcheck shell=dash
set -eu

PAYLOAD="$1"; OVERLAY="$2"; SSH_KEY="$3"; PASS_HASH="$4"
HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/../image.manifest"

KEYFILE="$(dirname "$PAYLOAD")/authorized_keys"
[ -n "$SSH_KEY" ] && printf '%s\n' "$SSH_KEY" > "$KEYFILE"

tab()  { printf '%s\n' "$*" | sed 's/ ~ /\t/g'; }   # ~ marks a field break, for readability
trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

while IFS='|' read -r kind a b c d; do
    kind=$(trim "${kind:-}")
    case "$kind" in ''|\#*) continue ;; esac
    a=$(trim "${a:-}"); b=$(trim "${b:-}"); c=$(trim "${c:-}"); d=$(trim "${d:-}")

    case "$kind" in
        note)    printf '%s\n' "$a" ;;
        append)  b=$(printf '%s' "$b" | sed "s|{HASH}|$PASS_HASH|")
                 tab "append ~ $a ~ $b ~ $c" ;;
        mkdir)   tab "mkdir ~ $a ~ $b ~ 0 ~ 0" ;;
        keydir)  [ -n "$SSH_KEY" ] && tab "mkdir ~ $a ~ $b ~ 0 ~ 0" ;;
        key)     [ -n "$SSH_KEY" ] && tab "put ~ $KEYFILE ~ $a ~ $b ~ 0 ~ 0" ;;
        put)     tab "put ~ $PAYLOAD/$a ~ $b ~ $c ~ 0 ~ 0" ;;
        overlay) if [ -f "$OVERLAY/$a" ]; then
                     [ -n "$d" ] && tab "mkdir ~ $(dirname "$b") ~ $d ~ 0 ~ 0"
                     tab "put ~ $OVERLAY/$a ~ $b ~ $c ~ 0 ~ 0"
                 fi ;;
        symlink) tab "symlink ~ $a ~ $b" ;;
        rm)      tab "rm ~ $a" ;;
        putdir)
            [ -d "$PAYLOAD/$a" ] || { echo "STOP: image.manifest wants putdir $a and $PAYLOAD/$a was never staged" >&2; exit 1; }
            for f in "$PAYLOAD/$a"/*; do
                [ -f "$f" ] || continue
                base=$(basename "$f")
                mode="$c"
                if [ "$c" = auto ]; then
                    case "$base" in *.sh) mode=0755 ;; *) mode=0644 ;; esac
                fi
                tab "put ~ $f ~ $b/$base ~ $mode ~ 0 ~ 0"
            done ;;
        *)  echo "STOP: image.manifest has an unknown kind: $kind" >&2; exit 1 ;;
    esac
done < "$MANIFEST"
