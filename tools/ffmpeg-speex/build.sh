#!/bin/sh
# shellcheck shell=dash
set -eu

LC_ALL=C; LANG=C; TZ=UTC
export LC_ALL LANG TZ

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-$HERE/build}"
WORK="${WORK:-$HERE/build/work}"
NAME="ffmpeg-speex-linux-armv7"
TARGET="arm-linux-musleabihf"

FFMPEG_VERSION="7.0.2"
FFMPEG_SHA256="5eb46d18d664a0ccadf7b0adee03bd3b7fa72893d667f36c69e202a807e6d533"
SPEEX_VERSION="1.2.1"
ZIG_VERSION="0.16.0"

USE_DOCKER=0
[ "${1:-}" = "--docker" ] && USE_DOCKER=1

die() { echo "STOP: $*" >&2; exit 1; }

sha_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
    else die "no sha256sum or shasum on this machine"
    fi
}

verify() {  # verify <file> <want> <what>
    got=$(sha_of "$1")
    [ "$got" = "$2" ] || die "$3 is not the file this project expects.
      expected $2
      got      $got"
}

fetch() {   # fetch <urls> <dest> <sha> <what>   -- urls tried in order
    [ -f "$2" ] && { verify "$2" "$3" "$4"; return 0; }
    echo "   fetching $4"
    for u in $1; do
        curl -fsSL --retry 3 --retry-delay 3 --retry-connrefused --connect-timeout 20 \
            -o "$2.part" "$u" && { mv "$2.part" "$2"; verify "$2" "$3" "$4"; return 0; }
        rm -f "$2.part"
    done
    die "could not download $4"
}

mkdir -p "$OUT"

if [ "$USE_DOCKER" = 1 ]; then
    command -v docker >/dev/null 2>&1 || die "--docker was asked for, and docker is not here."
    exec "$HERE/build-in-docker.sh" "$(cd "$HERE/../.." && pwd)" "$OUT"
fi

case "$(uname -s)" in
    Linux)                  zos=linux ;;
    Darwin)                 zos=macos ;;
    MINGW*|MSYS*|CYGWIN*)   zos=windows ;;
    *) die "unknown system: $(uname -s). Use --docker, or build on Linux, macOS or Windows." ;;
esac
case "$(uname -m)" in
    x86_64|amd64)   zarch=x86_64 ;;
    arm64|aarch64)  zarch=aarch64 ;;
    *) die "unknown processor: $(uname -m). Use --docker." ;;
esac

[ "$zos" = macos ] || command -v xz >/dev/null 2>&1 \
    || die "xz is not on this machine. Install it (xz-utils), or use --docker."
[ "$zos" != windows ] || command -v unzip >/dev/null 2>&1 \
    || die "unzip is not on this machine. In MSYS2: pacman -S unzip"

case "$zos-$zarch" in
    linux-x86_64)   zsha=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00; zext=tar.xz ;;
    linux-aarch64)  zsha=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17; zext=tar.xz ;;
    macos-x86_64)   zsha=0387557ed1877bc6a2e1802c8391953baddba76081876301c522f52977b52ba7; zext=tar.xz ;;
    macos-aarch64)  zsha=b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489; zext=tar.xz ;;
    windows-x86_64) zsha=68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e; zext=zip ;;
    windows-aarch64)zsha=aee38316ee4111717900f45dd3130145c39289e105541d737eb8c5ed653c78ef; zext=zip ;;
esac

mkdir -p "$WORK"
cd "$WORK"
# ffmpeg versions itself with git describe, which would otherwise find this repository
GIT_CEILING_DIRECTORIES="$WORK"; export GIT_CEILING_DIRECTORIES

ZNAME="zig-${zarch}-${zos}-${ZIG_VERSION}"
fetch "https://ziglang.org/download/${ZIG_VERSION}/${ZNAME}.${zext}" "${ZNAME}.${zext}" "$zsha" "the compiler"
if [ ! -d "$ZNAME" ]; then
    case "$zext" in
        tar.xz) tar xf "${ZNAME}.${zext}" ;;
        zip)    unzip -q "${ZNAME}.${zext}" ;;
    esac
fi
ZIG="$WORK/$ZNAME/zig"
[ -x "$ZIG" ] || ZIG="$WORK/$ZNAME/zig.exe"
[ -x "$ZIG" ] || die "the compiler did not unpack as expected"

mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexec "%s" cc -target %s "$@"\n'  "$ZIG" "$TARGET" > "$WORK/bin/cc"
printf '#!/bin/sh\nexec "%s" cc "$@"\n'               "$ZIG"           > "$WORK/bin/hostcc"
printf '#!/bin/sh\nexec "%s" ar "$@"\n'             "$ZIG"           > "$WORK/bin/ar"
printf '#!/bin/sh\nexec "%s" ranlib "$@"\n'         "$ZIG"           > "$WORK/bin/ranlib"
printf '#!/bin/sh\nexec "%s" ld.lld "$@"\n'        "$ZIG"           > "$WORK/bin/ld"
cp "$WORK/bin/ld" "$WORK/bin/arm-linux-ld"
cat > "$WORK/bin/strip" <<'STRIPEOF'
#!/bin/sh
[ "$1" = "-o" ] && exec cp -f "$3" "$2"
exit 0
STRIPEOF
chmod +x "$WORK/bin/cc" "$WORK/bin/hostcc" "$WORK/bin/ar" "$WORK/bin/ranlib" "$WORK/bin/strip" "$WORK/bin/ld" "$WORK/bin/arm-linux-ld"

cat > "$WORK/bin/pkg-config" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    --cflags)     echo "-I$WORK/prefix/include" ;;
    --libs)       echo "-L$WORK/prefix/lib -lspeex -lm" ;;
    --modversion) echo "$SPEEX_VERSION" ;;
  esac
done
exit 0
EOF
chmod +x "$WORK/bin/pkg-config"
PATH="$WORK/bin:$PATH"; export PATH

# An MSYS make: native w32 make trims long ar lines via cmd (8191)
command -v make >/dev/null 2>&1 || \
    die "make is not on this machine. On Windows install MSYS2 and run
      pacman -S make
    from its shell; elsewhere use your package manager. Or use --docker."

echo "== speex $SPEEX_VERSION (vendored)"
SPEEXSRC="$HERE/vendor/speex"
if [ ! -f "$WORK/prefix/lib/libspeex.a" ]; then
    (
        mkdir -p "$WORK/speexbuild/speex"
        cd "$WORK/speexbuild"
        cat > config.h <<'CONFEOF'
#define EXPORT __attribute__((visibility("default")))
#define FLOATING_POINT /**/
#define HAVE_ALLOCA_H 1
#define HAVE_DLFCN_H 1
#define HAVE_GETOPT_H 1
#define HAVE_GETOPT_LONG 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_SOUNDCARD_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
#define LT_OBJDIR ".libs/"
#define PACKAGE_BUGREPORT "speex-dev@xiph.org"
#define PACKAGE_NAME "speex"
#define PACKAGE_STRING "speex 1.2.1"
#define PACKAGE_TARNAME "speex"
#define PACKAGE_URL ""
#define PACKAGE_VERSION "1.2.1"
#define SIZEOF_INT 4
#define SIZEOF_INT16_T 2
#define SIZEOF_INT32_T 4
#define SIZEOF_LONG 4
#define SIZEOF_SHORT 2
#define SIZEOF_UINT16_T 2
#define SIZEOF_UINT32_T 4
#define SIZEOF_U_INT16_T 2
#define SIZEOF_U_INT32_T 4
#define SPEEX_EXTRA_VERSION ""
#define SPEEX_MAJOR_VERSION 1
#define SPEEX_MICRO_VERSION 1
#define SPEEX_MINOR_VERSION 2
#define SPEEX_VERSION "1.2.1"
#define STDC_HEADERS 1
#define USE_SMALLFT /**/
#define VAR_ARRAYS /**/
#define restrict __restrict__
CONFEOF
        cat > speex/speex_config_types.h <<'TYPESEOF'
#ifndef __SPEEX_TYPES_H__
#define __SPEEX_TYPES_H__

#include <stdint.h>

typedef int16_t spx_int16_t;
typedef uint16_t spx_uint16_t;
typedef int32_t spx_int32_t;
typedef uint32_t spx_uint32_t;

#endif
TYPESEOF
        OBJS="cb_search exc_10_32_table exc_8_128_table filters gain_table hexc_table \
              high_lsp_tables lsp ltp speex stereo vbr vq bits exc_10_16_table \
              exc_20_32_table exc_5_256_table exc_5_64_table gain_table_lbr \
              hexc_10_32_table lpc lsp_tables_nb modes modes_wb nb_celp quant_lsp \
              sb_celp speex_callbacks speex_header window"
        # no -g: debug paths would differ per machine
        # Compiled from a copy, by relative name: an absolute path would be
        # recorded in the object and the binary would differ per machine.
        cp "$SPEEXSRC"/libspeex/*.c "$SPEEXSRC"/libspeex/*.h .
        for f in $OBJS; do
            "$WORK/bin/cc" -DHAVE_CONFIG_H -I. -Ispeex -I"$SPEEXSRC/include" \
                -O2 -fvisibility=hidden -Wall -c "$f.c" -o "$f.o"
        done
        set --
        for f in $OBJS; do set -- "$@" "$f.o"; done
        "$WORK/bin/ar" cru libspeex.a "$@" 2>/dev/null
        "$WORK/bin/ranlib" libspeex.a
        mkdir -p "$WORK/prefix/lib" "$WORK/prefix/include/speex"
        cp libspeex.a "$WORK/prefix/lib/"
        cp "$SPEEXSRC"/include/speex/*.h "$WORK/prefix/include/speex/"
        cp speex/speex_config_types.h "$WORK/prefix/include/speex/"
    )
fi
echo "   built"

echo "== ffmpeg $FFMPEG_VERSION"
fetch "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${FFMPEG_VERSION}.tar.gz" \
      "ffmpeg-${FFMPEG_VERSION}.tar.gz" "$FFMPEG_SHA256" "the ffmpeg source"
if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
    mkdir -p "ffmpeg-${FFMPEG_VERSION}"
    tar xzf "ffmpeg-${FFMPEG_VERSION}.tar.gz" --strip-components 1 -C "ffmpeg-${FFMPEG_VERSION}"
    printf '%s\n' "$FFMPEG_VERSION" > "ffmpeg-${FFMPEG_VERSION}/VERSION"
fi
cd "ffmpeg-${FFMPEG_VERSION}"
if [ ! -f ffmpeg ]; then
    # ffmpeg embeds this command line in the binary
    ./configure \
        --arch=arm --target-os=linux --enable-cross-compile \
        --cc=cc --host-cc=hostcc --ar=ar --ranlib=ranlib --strip=strip \
        --pkg-config=pkg-config --pkg-config-flags=--static \
        --enable-libspeex \
        --extra-cflags="-I../prefix/include" --extra-ldflags="-L../prefix/lib -s" --extra-libs="-lm" \
        --enable-static --disable-shared \
        --disable-doc --disable-htmlpages --disable-manpages --disable-podpages --disable-txtpages \
        --disable-ffplay --disable-ffprobe \
        --disable-sdl2 --disable-xlib --disable-libxcb --disable-alsa \
            --disable-indevs --disable-outdevs \
        --disable-debug --enable-small >/dev/null
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" >/dev/null
fi
cp ffmpeg "$OUT/$NAME"

echo
echo "== built"
ls -l "$OUT/$NAME"
echo "   sha256 $(sha_of "$OUT/$NAME")"
