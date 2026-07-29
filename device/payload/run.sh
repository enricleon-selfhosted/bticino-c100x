#!/bin/sh
# shellcheck shell=dash
LOG=/var/tmp/c300x.log
LOCK=/var/tmp/.controller-start
NODE=/home/bticino/cfg/extra/node/bin/node

controller_running() {
    for c in /proc/[0-9]*/cmdline; do
        [ -r "$c" ] || continue
        case "$(tr '\0' ' ' < "$c" 2>/dev/null)" in
            *"node ./bundle.js "*|*"node.bin ./bundle.js "*) return 0 ;;
        esac
    done
    return 1
}

until ln -s $$ "$LOCK" 2>/dev/null; do
    owner=$(readlink "$LOCK" 2>/dev/null)
    [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null && exit 0
    rm -f "$LOCK"
done

if controller_running; then
    rm -f "$LOCK"
    exit 0
fi

cd "$(cd "$(dirname "$0")" && pwd)" || { rm -f "$LOCK"; exit 1; }
setsid sh -c "exec $NODE ./bundle.js" > $LOG 2>&1 < /dev/null &
rm -f "$LOCK"

exit 0
