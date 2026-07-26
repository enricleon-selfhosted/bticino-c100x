#!/bin/sh
# shellcheck shell=dash
set -eu

TAG="${TAG:-v2024.9.1}"
REPO="https://github.com/slyoldfox/c300x-controller.git"
OFFICIAL_MD5="34ec1c43bc2a96d76129267f563671f7"

USE_DOCKER=0
while [ $# -gt 0 ]; do
    case "$1" in
        --docker) USE_DOCKER=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/platform.sh"
SRC="$HERE/build/source"
PATCHES="$HERE/patches"
IMAGE="node:18"
WANT_MAJOR=18

decir() { printf "\n== %s\n" "$1"; }

YOUR_NODE=""
if check_cmd node && check_cmd npm; then
    YOUR_NODE="$(node --version 2>/dev/null || true)"
fi
if [ "${USE_DOCKER:-0}" = 1 ]; then
    check_cmd docker || { echo "STOP: --docker was asked for, and docker is not here." >&2; exit 1; }
    RUNNER=docker
else
    case "$YOUR_NODE" in
        v$WANT_MAJOR.*) RUNNER=local ;;
        *)
            echo "STOP: this needs node $WANT_MAJOR." >&2
            echo >&2
            if [ -n "$YOUR_NODE" ]; then
                echo "  Your node is $YOUR_NODE. It would build a different file, and the check" >&2
                echo "  against the published release would fail and tell you nothing useful." >&2
            else
                echo "  There is no node on this machine." >&2
            fi
            echo >&2
            echo "  Either install node $WANT_MAJOR, or run this again with --docker." >&2
            echo >&2
            echo "  Neither is needed to install: device/controller/bundle.js is this same" >&2
            echo "  file, already built, and that is what install.sh uses." >&2
            exit 1 ;;
    esac
fi

in_node() {
    if [ "$RUNNER" = local ]; then
        ( cd "$SRC" && "$@" )
    else
        docker run --rm -v "$SRC:/src" -w /src --user "$(id -u):$(id -g)" -e HOME=/tmp \
            "$IMAGE" "$@"
    fi
}

decir "Cloning $TAG"
rm -rf "$SRC"
git clone -q --branch "$TAG" --depth 1 "$REPO" "$SRC"

decir "Installing dependencies"
[ "$RUNNER" = local ] && echo "   using your node $YOUR_NODE" || echo "   using node $WANT_MAJOR in a container"
in_node npm ci --no-audit --no-fund >/dev/null

decir "Building unpatched, to check the toolchain reproduces upstream"
in_node sh -c "npm run build:sipbundle:prod >/dev/null 2>&1 && npm run build:prod >/dev/null 2>&1"
got="$(md5_of "$SRC/dist/bundle-webrtc.js")"
if [ "$got" != "$OFFICIAL_MD5" ]; then
    echo "STOP: the unpatched build does not match the published release."
    echo "  expected $OFFICIAL_MD5"
    echo "  got      $got"
    echo "Fix this before trusting a patched build: if the starting point differs, so will"
    echo "everything built on top of it, and you will not know which difference is yours."
    exit 1
fi
echo "   matches the published release: $got"

decir "Applying patches"
for p in "$PATCHES"/*.patch; do
    if ! git -C "$SRC" apply --check "$p" 2>/dev/null; then
        echo "STOP: does not apply cleanly: $(basename "$p")"
        echo "The source has moved. Read the patch and redo it by hand rather than forcing it."
        exit 1
    fi
    git -C "$SRC" apply "$p"
    echo "   $(basename "$p")"
done
cp "$PATCHES/volume.js" "$SRC/lib/apis/volume.js"
echo "   lib/apis/volume.js (new file)"

decir "Building patched"
rm -f "$SRC/dist/bundle-webrtc.js"
in_node npm run build:prod > "$SRC/build.log" 2>&1 || {
    echo "STOP: the patched build failed."; tail -20 "$SRC/build.log"; exit 1; }
grep -E 'compiled|ERROR' "$SRC/build.log" | tail -3

in_node node --check dist/bundle-webrtc.js

decir "Done"
echo "   $SRC/dist/bundle-webrtc.js"
echo "   $(md5_of "$SRC/dist/bundle-webrtc.js")"
echo
echo "Copy it to device/controller/bundle.js here, then build and flash as usual."
echo "On a unit you are editing by hand it goes to"
echo "  /home/bticino/cfg/extra/intercom/bundle.js"
echo "IMPORTANT: it is bundle-WEBRTC that goes there, not bundle.js from the same folder."
echo "Only the webrtc one carries the RTSP server, and installing the other one leaves you"
echo "with an intercom that answers the API but never shows a picture."
