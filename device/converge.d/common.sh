# shellcheck shell=dash

: "${OPT:=$(cd "$(dirname "$0")" && pwd)}"
case "$OPT" in */converge.d) OPT=$(dirname "$OPT") ;; esac

EXTRA=/home/bticino/cfg/extra
INTERCOM="$EXTRA/intercom"
LOG="$EXTRA/setup.log"

say() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null
    echo "$*"
}
trim_log() {
    [ -f "$LOG" ] || return 0
    tail -200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
}

CONF="$OPT/setup.conf"
[ -r "$CONF" ] || CONF="$INTERCOM/setup.conf"
if [ -r "$CONF" ]; then
    # shellcheck source=/dev/null
    . "$CONF"
fi

: "${MQTT_HOST:=}"
: "${CLOUD_MODE:=on}"
: "${STARTUP_DELAY:=60}"

# shellcheck disable=SC2034  # read by the steps that source this, not here
DOMAIN=""
if [ -r /etc/flexisip/domain-registration.conf ]; then
    # shellcheck disable=SC2034
    DOMAIN=$(cut -d' ' -f1 /etc/flexisip/domain-registration.conf 2>/dev/null)
fi
