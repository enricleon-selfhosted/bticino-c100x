#!/bin/sh
# shellcheck shell=dash
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/platform.sh"
. "$HERE/../lib/require-tools.sh"
ROOT="$(cd "$HERE/.." && pwd)"
CONFIG="${CONFIG:-$ROOT/config.yaml}"
WORK="$HERE/build"

DRY_RUN=0
FIRMWARE=""
MODE=auto
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)  DRY_RUN=1 ;;
        --firmware) shift; FIRMWARE="$1" ;;
        --docker)   MODE=docker ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

say()  { printf "\n== %s\n" "$1"; }
step() { printf "   %s\n" "$1"; }
die()  { printf "\nSTOP: %s\n" "$1" >&2; exit 1; }

[ -f "$CONFIG" ] || die "no answers yet. Run ./install.sh from the top of this repository."

[ "$DRY_RUN" = 1 ] || require_tools $HOST_TOOLS || exit 1

get() { "$ROOT/lib/read-config.sh" "$CONFIG" "$1"; }

MODEL="$(get device.model)";        MODEL="${MODEL:-C100X}"
VERSION="$(get device.firmware)";   VERSION="${VERSION:-1.5.8}"
SSH_KEY="$(get device.ssh_public_key)"
ROOT_PASS="$(get device.root_password)"

say "Building for $MODEL $VERSION"

mkdir -p "$WORK"
if [ -n "$FIRMWARE" ]; then
    [ -r "$FIRMWARE" ] || die "cannot read $FIRMWARE"
    cp "$FIRMWARE" "$WORK/stock.fwz"
    step "using $FIRMWARE"
else
    . "$HERE/steps/firmware-versions.sh"
    URL="$(firmware_url "$MODEL" "$VERSION")"
    [ -n "$URL" ] || die "no download known for $MODEL $VERSION. Pass one with --firmware."
    if [ ! -f "$WORK/stock.fwz" ]; then
        step "downloading (about 100 MB)"
        curl -sL -o "$WORK/stock.fwz" "$URL" || die "the download failed"
    else
        step "already downloaded"
    fi
fi

EXPECTED="$(firmware_md5 "$MODEL" "$VERSION" 2>/dev/null || true)"
ACTUAL="$(md5_of "$WORK/stock.fwz")"
if [ -n "$EXPECTED" ] && [ "$EXPECTED" != "$ACTUAL" ]; then
    die "the firmware is not the one expected.
  expected $EXPECTED
  got      $ACTUAL
Either it has been changed at the source, or the download was damaged. Check before going on."
fi
step "checksum $ACTUAL"

if [ "$DRY_RUN" = 1 ]; then
    say "Dry run: stopping before anything is unpacked"
    exit 0
fi

say "Gathering what goes inside"
PAYLOAD="$WORK/payload"
rm -rf "$PAYLOAD"; mkdir -p "$PAYLOAD/payload"

BUILT="$ROOT/device/build/source/dist/bundle-webrtc.js"
SHIPPED="$ROOT/device/controller/bundle.js"
if [ -f "$BUILT" ]; then
    CONTROLLER="$BUILT"
    step "controller  yours, from device/build/"
elif [ -f "$SHIPPED" ]; then
    CONTROLLER="$SHIPPED"
    step "controller  the one shipped with this project"
    WANT="$(cat "$ROOT/device/controller/bundle.js.md5" 2>/dev/null || true)"
    GOT="$(md5_of "$SHIPPED")"
    [ -z "$WANT" ] || [ "$WANT" = "$GOT" ] || die "device/controller/bundle.js is not the file
this project shipped.
  expected $WANT
  got      $GOT
Rebuild it with device/build-controller.sh, or check out a clean copy."
else
    die "no controller to install. device/controller/bundle.js is missing from this checkout."
fi
cp "$CONTROLLER" "$PAYLOAD/payload/bundle.js"
cp "$ROOT/device/payload/run.sh"    "$PAYLOAD/payload/run.sh"
cp "$ROOT/device/patch-aswm.sh"     "$PAYLOAD/payload/patch-aswm.sh"
cp "$ROOT/device/setup.sh"          "$PAYLOAD/setup.sh"
mkdir -p "$PAYLOAD/converge.d"
cp "$ROOT/device/converge.d/"*       "$PAYLOAD/converge.d/"
cp "$ROOT/device/go2rtc.yaml"       "$PAYLOAD/payload/go2rtc.yaml"
step "controller  $(md5_of "$PAYLOAD/payload/bundle.js" | cut -c1-8)"

if [ "$MODE" = docker ]; then
    check_cmd docker || die "--docker was asked for, but docker is not installed."
    step "using a container (asked for)"
    mkdir -p "$ROOT/.tools"
    if ! docker run --rm -v "$ROOT:/repo" -w /repo -e ASSUME_YES=1 \
            -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" alpine:3.19 sh -c '
                set -e
                apk add -q --no-cache cmake gcc musl-dev make git
                cmake -B /tmp/b tools/fwz -DCMAKE_BUILD_TYPE=Release
                cmake --build /tmp/b -j4
                cp /tmp/b/fwz .tools/fwz-container
                chown "$HOST_UID:$HOST_GID" .tools/fwz-container
            ' > "$WORK/container.log" 2>&1; then
        echo
        echo "STOP: the container could not build the tool. The last of what it said:"
        tail -15 "$WORK/container.log"
        exit 1
    fi
    TOOL="$ROOT/.tools/fwz-container"
else
    TOOL="$("$HERE/steps/get-tool.sh")" || exit 1
fi

"$HERE/steps/fetch-runtime.sh" "$PAYLOAD/payload" "$TOOL" || die "could not assemble the runtime"
step "runtime     $(du -h "$PAYLOAD/payload/runtime.tar.gz" | cut -f1)"

"$HERE/steps/write-answers.sh" "$CONFIG" > "$PAYLOAD/setup.conf"
step "answers     $(wc -l < "$PAYLOAD/setup.conf") settings"

say "Opening the firmware"

HASH="$("$TOOL" passwd root "$ROOT_PASS")"

"$HERE/steps/write-changes.sh" "$PAYLOAD" "$HERE/overlay" "$SSH_KEY" "$HASH" > "$WORK/changes.txt"
step "$(grep -cvE '^#|^$' "$WORK/changes.txt") changes to make"

OUT="$WORK/$MODEL-$VERSION-local.fwz"
mkdir -p "$WORK/unpack"
"$TOOL" build --in "$WORK/stock.fwz" --out "$OUT" --model "$MODEL" \
        --changes "$WORK/changes.txt" --work "$WORK/unpack" || die "the firmware could not be built"

say "Done"
echo "   $OUT"
echo "   $(md5_of "$OUT")"
echo
cat <<'END'

Flash it with MyHomeSuite, which is Bticino's own tool.

If this is a brand new unit, pair it with the Door Entry app afterwards, exactly as you
would with any unit out of the box. That pairing is what gives it its phone identity, and
nothing here can work before it has happened. The unit sets itself up on the next restart.

If the unit was already paired, it stays paired: that lives on a partition a flash does not
touch, so it is ready as soon as it comes back up.

Then Home Assistant. Install this repository through HACS, add "Bticino Classe 100X" under
Settings, Devices and services, and give it the intercom's address. Until that is done the
unit is on your network doing nothing you can see.
END
