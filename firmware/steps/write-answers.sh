#!/bin/sh
# shellcheck shell=dash
set -eu
CONFIG="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
get() { "$HERE/../../lib/read-config.sh" "$CONFIG" "$1"; }
esc() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }
w()   { printf "%s='%s'\n" "$1" "$(esc "$2")"; }

echo "# Written by the installer. Edit config.yaml and build again instead of this."
w MQTT_HOST              "$(get mqtt.host)"
w MQTT_PORT              "$(get mqtt.port)"
w MQTT_USER              "$(get mqtt.username)"
w MQTT_PASS              "$(get mqtt.password)"
w MQTT_TOPIC             "$(get mqtt.topic)"
w MQTT_INTERVAL          "$(get mqtt.status_interval)"
w CLOUD_MODE             "$(get cloud.mode)"
w BLOCK_FIRMWARE_UPDATES "$(get cloud.block_updates)"
w VIDEO_FMTP             "$(get video.fmtp)"
w DOOR_OPEN              "$(get door.open_sequence)"
w DOOR_CLOSE             "$(get door.close_sequence)"
w STARTUP_DELAY          "$(get device.startup_delay)"
