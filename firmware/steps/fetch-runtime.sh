#!/bin/sh
# shellcheck shell=dash
set -eu

DEST="$1"
TOOL="${2:?fetch-runtime.sh needs the path to fwz as its second argument}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
MANIFEST="$HERE/runtime.manifest"
CACHE="${CACHE:-$ROOT/firmware/build/cache}"
OUT="$DEST/runtime.tar.gz"

mkdir -p "$CACHE" "$DEST"

if [ -f "$OUT" ]; then
    echo "   runtime already assembled"
    exit 0
fi

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

verify() {   # verify <file> <expected> <name>
    got=$(sha256_of "$1")
    [ -z "$got" ] && { echo "   cannot check the checksum on this machine" >&2; return 0; }
    [ "$got" = "$2" ] && return 0
    echo "STOP: $3 is not the file expected." >&2
    echo "  expected $2" >&2
    echo "  got      $got" >&2
    echo "This goes inside the firmware and runs on your intercom, so it is not something to" >&2
    echo "shrug at. Delete it from $CACHE and try again; if it keeps happening, the file" >&2
    echo "changed at the source." >&2
    return 1
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/node" "$STAGE/lib" "$STAGE/bin"

EXEC_ARGS="--exec node/bin/node --exec node/bin/node.bin"

while IFS='|' read -r name kind dest exec sha url; do
    case "$name" in ''|\#*) continue ;; esac

    var=$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')
    eval "supplied=\${$var:-}"
    built="$ROOT/tools/$name/build/$name-linux-armv7"
    if [ -n "$supplied" ] && [ -r "$supplied" ]; then
        src="$supplied"; echo "   $name: using the one you supplied"
    elif [ -r "$built" ]; then
        src="$built";    echo "   $name: using the one you built"
    else
        src="$CACHE/$name"
        if [ ! -f "$src" ]; then
            echo "   downloading $name"
            curl -sfL --retry 5 --retry-delay 3 --retry-connrefused --connect-timeout 30 \
                -o "$src.part" "$url" || {
                rm -f "$src.part"
                echo "STOP: could not download $name from $url" >&2
                exit 1
            }
            mv "$src.part" "$src"
        fi
        verify "$src" "$sha" "$name" || exit 1
    fi

    case "$kind" in
        archive) tar xzf "$src" --strip-components 1 -C "$STAGE/$dest" ;;
        file)    mkdir -p "$STAGE/$(dirname "$dest")"; cp "$src" "$STAGE/$dest" ;;
        *)       echo "STOP: $name has an unknown kind: $kind" >&2; exit 1 ;;
    esac
    [ "$exec" = "1" ] && EXEC_ARGS="$EXEC_ARGS --exec $dest"
done < "$MANIFEST"

mv "$STAGE/node/bin/node" "$STAGE/node/bin/node.bin"
cat > "$STAGE/node/bin/node" <<'WRAPPER'
#!/bin/sh
export LD_LIBRARY_PATH=/home/bticino/cfg/extra/lib:$LD_LIBRARY_PATH
exec /home/bticino/cfg/extra/node/bin/node.bin "$@"
WRAPPER

rm -rf "$STAGE/node/include" "$STAGE/node/share" \
       "$STAGE/node/lib/node_modules/npm" "$STAGE/node/lib/node_modules/corepack" \
       "$STAGE/node/bin/npm" "$STAGE/node/bin/npx" "$STAGE/node/bin/corepack" 2>/dev/null || true

# shellcheck disable=SC2086
"$TOOL" pack --root "$STAGE" --out "$OUT" $EXEC_ARGS \
    || { echo "could not pack the runtime" >&2; exit 1; }
echo "   runtime packed: $(du -h "$OUT" | cut -f1)"
