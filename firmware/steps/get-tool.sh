#!/bin/sh
# shellcheck shell=dash
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/lib/platform.sh"

VERSION="${FWZ_VERSION:-v1.0.0}"
BASE="${FWZ_BASE_URL:-https://github.com/enricleon-selfhosted/bticino-c100x/releases/download/$VERSION}"
DEST="$ROOT/.tools"

say() { printf '%s\n' "$*" >&2; }   # stdout is the path, so talking goes to stderr

if [ -n "${FWZ:-}" ] && [ -x "$FWZ" ]; then printf '%s' "$FWZ"; exit 0; fi
for built in "$ROOT/build/fwz" "$ROOT/tools/fwz/build/fwz"; do
    [ -x "$built" ] && { say "   using the fwz you built"; printf '%s' "$built"; exit 0; }
done

case "$(uname -m 2>/dev/null)" in
    x86_64|amd64)        arch=x64 ;;
    aarch64|arm64)       arch=arm64 ;;
    armv7l|armv6l)       arch=armv7 ;;
    *) say "STOP: fwz is not built for $(uname -m). Build it: cmake -B build tools/fwz && cmake --build build"
       exit 1 ;;
esac

case "$(platform)" in
    macos)       os=macos;   ext="" ;;
    linux|wsl)   os=linux;   ext="" ;;
    windows)     os=windows; ext=".exe" ;;
    *) say "STOP: fwz is not built for this system."; exit 1 ;;
esac

NAME="fwz-$os-$arch$ext"
TOOL="$DEST/$NAME"
[ -x "$TOOL" ] && { printf '%s' "$TOOL"; exit 0; }

mkdir -p "$DEST"
say "   fetching fwz for $os $arch"
CURL="$(find_tool curl || true)"
[ -n "$CURL" ] || { say "STOP: this needs curl."; exit 1; }
"$CURL" -fsSL --retry 5 --retry-delay 3 --retry-connrefused --connect-timeout 30 \
    -o "$TOOL.part" "$BASE/$NAME" || {
    say "STOP: could not download $BASE/$NAME"
    say "      Check your connection, or build it: cmake -B build tools/fwz && cmake --build build"
    exit 1
}

if "$CURL" -fsSL -o "$DEST/sums.txt" "$BASE/sha256sums.txt" 2>/dev/null; then
    want=$(awk -v n="$NAME" '$2 == n || $2 == "*"n {print $1}' "$DEST/sums.txt" | head -1)
    if [ -n "$want" ]; then
        if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$TOOL.part" | cut -d' ' -f1)
        elif command -v shasum >/dev/null 2>&1; then got=$(shasum -a 256 "$TOOL.part" | cut -d' ' -f1)
        else got=""; say "   no way to check the checksum on this machine"
        fi
        if [ -n "$got" ] && [ "$got" != "$want" ]; then
            rm -f "$TOOL.part"
            say "STOP: the downloaded fwz is not the published one."
            say "      expected $want"
            say "      got      $got"
            exit 1
        fi
        [ -n "$got" ] && say "   checksum ok"
    fi
else
    say "   WARNING: no checksum list published for $VERSION, cannot verify"
fi

mv "$TOOL.part" "$TOOL"
chmod +x "$TOOL"
printf '%s' "$TOOL"
