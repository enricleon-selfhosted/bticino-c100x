#!/bin/sh
# shellcheck shell=dash
set -eu

ROOT="$1"
OUT="$2"

docker run --rm \
    -v "$ROOT:/repo" \
    -e OUT=/out \
    -e WORK=/out/work \
    -v "$OUT:/out" \
    debian:bookworm-slim sh -eu -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends \
            curl ca-certificates xz-utils make file >/dev/null
        sh /repo/tools/ffmpeg-speex/build.sh
        chown -R "$(stat -c %u /out):$(stat -c %g /out)" /out 2>/dev/null || true
    '
