#!/bin/sh
# shellcheck shell=dash
set -eu

if [ -n "${ZSH_VERSION:-}" ]; then
    echo "Run this with sh, not zsh:   sh ./install.sh" >&2
    exit 1
fi

main() {
    HERE="$(cd "$(dirname "$0")" && pwd)"

    if [ ! -d "$HERE/firmware" ]; then
        fetch_and_restart "$@"
        exit $?
    fi

    . "$HERE/lib/platform.sh"
    CONFIG="$HERE/config.yaml"
    ASK=1
    PASS_THROUGH=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --yes)      ASK=0; ASSUME_YES=1; export ASSUME_YES ;;
            --dry-run)  PASS_THROUGH="$PASS_THROUGH --dry-run" ;;
            --firmware) shift; PASS_THROUGH="$PASS_THROUGH --firmware $1" ;;
            --docker)   PASS_THROUGH="$PASS_THROUGH --docker" ;;
            -h|--help)  sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
            *) echo "unknown option: $1" >&2; exit 2 ;;
        esac
        shift
    done

    say() { printf "\n\033[1m%s\033[0m\n" "$1"; }
    get() { "$HERE/lib/read-config.sh" "$CONFIG" "$1" 2>/dev/null; }

    ask() {
        key="$1"; question="$2"; fallback="$3"; secret="${4:-}"
        current="$(get "$key")"
        [ -z "$current" ] && current="$fallback"
        if [ "$ASK" = 0 ]; then
            printf '%s' "$current"
            return
        fi
        shown="$current"
        [ -n "$secret" ] && [ -n "$current" ] && shown="(unchanged)"
        printf "  %s [%s]: " "$question" "$shown" > /dev/tty
        read -r reply < /dev/tty || reply=""
        [ -z "$reply" ] && reply="$current"
        printf '%s' "$reply"
    }

    if [ "$ASK" = 1 ]; then
    cat <<'INTRO'

  This builds a firmware image for your intercom.

  A few questions, once. They are saved, so building again asks nothing.
  Press enter to keep what is in the brackets.

INTRO
    fi

    say "Your MQTT broker"
    MQTT_GUESS=$(local_ip)
    MQTT_HOST=$(ask mqtt.host        "address"                "$MQTT_GUESS")
    MQTT_PORT=$(ask mqtt.port        "port"                   "1883")
    MQTT_USER=$(ask mqtt.username    "username"               "")
    MQTT_PASS=$(ask mqtt.password    "password"               "" secret)
    MQTT_TOPIC=$(ask mqtt.topic      "topic prefix"           "bticinocontroller")
    MQTT_INT=$(ask mqtt.status_interval "seconds between health reports" "60")

    say "Getting in"
    if [ "$ASK" = 1 ]; then
        echo "  A key is the safe way. The password is a fallback for when you lose the key,"
        echo "  and the one this project ships with is PUBLIC -- it is in the projects this is"
        echo "  built on. Change it, or leave it and know what you are leaving."
    fi
    DEFAULT_KEY=""
    for k in "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ecdsa.pub"; do
        [ -r "$k" ] && { DEFAULT_KEY="$(cat "$k")"; break; }
    done
    SSH_KEY=$(ask device.ssh_public_key "your public ssh key" "$DEFAULT_KEY")
    DEFAULT_PASS="$(get device.root_password)"
    GENERATED_PASS=0
    if [ -z "$DEFAULT_PASS" ]; then
        DEFAULT_PASS="$(random_password)"
        GENERATED_PASS=1
        [ -n "$DEFAULT_PASS" ] || die "this machine has no /dev/urandom, so set device.root_password in config.yaml yourself"
    fi
    ROOT_PASS=$(ask device.root_password "fallback password" "$DEFAULT_PASS")
    [ "$ROOT_PASS" = "$DEFAULT_PASS" ] || GENERATED_PASS=0

    say "Bticino's cloud"
    if [ "$ASK" = 1 ]; then
        echo "  off  the unit talks to nothing outside your house. The Door Entry app and"
        echo "       remote access stop working."
        echo "  on   nothing is cut. Everything here still works and you keep the app."
        echo
        echo "  Either way you must pair a NEW unit with the app first: that pairing is what"
        echo "  gives it its phone identity. Cutting comes after, on its own."
    fi
    CLOUD=$(ask cloud.mode "cut Bticino's cloud? (off = cut, on = keep)" "off")
    BLOCK=$(ask cloud.block_updates "also stop it downloading new firmware? (yes/no)" "no")

    say "The door"
    DOOR_OPEN=$(ask door.open_sequence  "the command that opens it"  "*8*19*20##")
    DOOR_CLOSE=$(ask door.close_sequence "the command that closes it" "*8*20*20##")

    say "The picture"
    if [ "$ASK" = 1 ]; then
        echo "  Describes the video before any of it arrives, so a viewer joining a ring in"
        echo "  progress can decode it. The default is a Classe 100X at 640x480 and is right"
        echo "  for that model. Leave it unless your picture is a different size."
    fi
    FMTP=$(ask video.fmtp "video parameters" "packetization-mode=1;profile-level-id=42401E;sprop-parameter-sets=Z0JAHqaAoD2Q,aM48gA==")

    say "Starting up"
    if [ "$ASK" = 1 ]; then
        echo "  The unit starts its programs before the wireless is ready, and anything that"
        echo "  reaches out in that gap fails. Sixty seconds is what a real unit needed."
    fi
    DELAY=$(ask device.startup_delay "seconds to wait before starting" "60")

    ask device.model      "model"            "C100X" >/dev/null
    ask device.firmware   "firmware version" "1.5.8" >/dev/null

    BAD=""
    [ -z "$MQTT_HOST" ] && BAD="$BAD\n  - the broker address is empty"
    case "$MQTT_HOST" in *…*|*"..."*) BAD="$BAD\n  - the broker address is still a placeholder" ;; esac
    case "$SSH_KEY" in
        "")             BAD="$BAD\n  - no ssh key: you would have only the password to get in" ;;
        *AAAA...*)      BAD="$BAD\n  - the ssh key is still the placeholder from the example" ;;
        ssh-ed25519*)   BAD="$BAD\n  - that is an ed25519 key, and the intercom's ssh server predates it.\n    It would install and never let you in. Use an RSA or ecdsa key:\n      ssh-keygen -t rsa -b 4096" ;;
        ssh-rsa*|ssh-dss*|ecdsa-sha2-*) ;;
        *)              BAD="$BAD\n  - that does not look like a key the intercom can use (rsa, dss or ecdsa)" ;;
    esac
    if [ -n "$BAD" ]; then
        printf "\nSTOP, these need sorting first:%b\n\n" "$BAD" >&2
        [ "$ASK" = 0 ] && echo "Run ./install.sh without --yes to be asked." >&2
        exit 1
    fi

    cat > "$CONFIG" <<EOF
# Written by install.sh. Edit by hand or run install.sh again.
# Ignored by git on purpose: your passwords are in here.

mqtt:
  host: $MQTT_HOST
  port: $MQTT_PORT
  username: $MQTT_USER
  password: $MQTT_PASS
  topic: $MQTT_TOPIC
  status_interval: $MQTT_INT

device:
  model: C100X
  firmware: 1.5.8
  ssh_public_key: "$SSH_KEY"
  root_password: $ROOT_PASS
  startup_delay: $DELAY

cloud:
  mode: $CLOUD
  block_updates: $BLOCK

door:
  open_sequence: "$DOOR_OPEN"
  close_sequence: "$DOOR_CLOSE"

video:
  fmtp: "$FMTP"
EOF
    chmod 600 "$CONFIG"

    if [ "$ASK" = 1 ]; then
        echo
        echo "  Saved to config.yaml. Next time: ./install.sh --yes"
    fi

    if [ "$GENERATED_PASS" = 1 ]; then
        echo
        echo "  The fallback password for this unit is:  $ROOT_PASS"
        echo "  It is in config.yaml as well. You need it only if you lose the ssh key."
    fi

    if [ "$ROOT_PASS" = "pwned123" ]; then
    cat <<'WARN'

  ┌──────────────────────────────────────────────────────────────────────┐
  │  You kept the default password.                                      │
  │                                                                      │
  │  It is published in the projects this one is built on, so anybody     │
  │  who knows about them knows it. On a device that sits on your         │
  │  network permanently, that is worth thinking about for a moment.     │
  │                                                                      │
  │  Change it in config.yaml and build again, or carry on knowingly.    │
  └──────────────────────────────────────────────────────────────────────┘

WARN
    fi

    # shellcheck disable=SC2086
    exec "$HERE/firmware/build.sh" $PASS_THROUGH

}

fetch_and_restart() {
    command -v git >/dev/null 2>&1 || {
        echo "This needs git to fetch the project. Install it and try again." >&2
        exit 1
    }
    target="${TARGET:-$HOME/bticino-c100x-local}"
    if [ -d "$target/.git" ]; then
        echo "Already at $target. Updating."
        git -C "$target" pull --ff-only
    else
        echo "Fetching into $target"
        git clone --depth 1 "${REPO_URL:-https://github.com/enricleon-selfhosted/bticino-c100x.git}" "$target"
    fi
    echo
    if [ -r /dev/tty ]; then
        sh "$target/install.sh" "$@" < /dev/tty
    else
        echo "No terminal here, so it cannot ask anything. Run it yourself:"
        echo "    cd $target && ./install.sh"
        exit 1
    fi
}

main "$@"