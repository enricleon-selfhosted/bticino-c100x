#!/bin/sh
# shellcheck shell=dash
exec awk -v want="$2" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
        line = $0
        indent = match(line, /[^ ]/) - 1
        if (match(line, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/) == 0) next
        key = line
        sub(/^[[:space:]]*/, "", key)
        sub(/[[:space:]]*:.*$/, "", key)
        value = line
        sub(/^[^:]*:[[:space:]]*/, "", value)
        sub(/[[:space:]]*$/, "", value)

        if (indent == 0) { path = key } else { path = top "." key }
        if (indent == 0) top = key

        if (path == want) {
            gsub(/^"|"$/, "", value)
            gsub(/^'"'"'|'"'"'$/, "", value)
            print value
            exit
        }
    }
' "$1"
