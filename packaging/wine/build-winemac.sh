#!/bin/bash
# Builds Wine's Mac driver (winemac.so) with Dormer's patch so that DXMT can draw into windows.
#
#   packaging/wine/build-winemac.sh [work-folder]
#
# Everything is downloaded into the work folder (default: build/winemac-dxmt) and checked against a pinned
# checksum; nothing is installed on the system. Needs the Xcode command line tools. On Apple silicon it
# also needs Rosetta 2, because Wine's build runs the x86_64 tools it has just compiled.
#
# Output: <work-folder>/dist/winemac-dxmt-<wine version>-<build>.tar.gz and its .sha256
set -euo pipefail

WINE_VERSION=11.21
BUILD=1
NAME="winemac-dxmt-${WINE_VERSION}-${BUILD}"

WINE_URL="https://dl.winehq.org/wine/source/11.x/wine-${WINE_VERSION}.tar.xz"
# From https://dl.winehq.org/wine/source/11.x/sha512sums.asc
WINE_SHA512="7071442db60d768d96c4e7276891f2985b4f606546d4184b83bb24245a903e7ae8dfb6369426489474d98f1cb130905269c1fa34c5456641be27d22bd7ab32cf"

# macOS ships bison 2.3; Wine needs 3 or later.
BISON_URL="https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz"
BISON_SHA256="9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2"

# Wine 11 requires a Windows cross compiler on macOS. Digest as published on the GitHub release page.
MINGW_NAME="llvm-mingw-20261104-ucrt-macos-universal"
MINGW_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/20261104/${MINGW_NAME}.tar.xz"
MINGW_SHA256="66cbd5178c4a71b0d473e68ede172f8eb7d15d023e67f39201d0a69e21f6bf3c"

here="$(cd "$(dirname "$0")" && pwd)"
patch_file="$here/0001-winemac-add-macdrv_functions-for-metal-layers.patch"
mkdir -p "${1:-build/winemac-dxmt}"
work="$(cd "${1:-build/winemac-dxmt}" && pwd)"
jobs="$(sysctl -n hw.ncpu)"

fetch() { # url, file, algorithm, expected digest
    if [ ! -f "$2" ]; then
        echo "Downloading $1"
        curl -fL --retry 3 -sS -o "$2.part" "$1"
        mv "$2.part" "$2"
    fi
    local actual
    actual="$(shasum -a "$3" "$2" | cut -d' ' -f1)"
    if [ "$actual" != "$4" ]; then
        echo "error: checksum mismatch for $2" >&2
        echo "  expected $4" >&2
        echo "  actual   $actual" >&2
        exit 1
    fi
}

mkdir -p "$work/downloads" "$work/dist"
fetch "$WINE_URL" "$work/downloads/wine.tar.xz" 512 "$WINE_SHA512"
fetch "$BISON_URL" "$work/downloads/bison.tar.xz" 256 "$BISON_SHA256"
fetch "$MINGW_URL" "$work/downloads/llvm-mingw.tar.xz" 256 "$MINGW_SHA256"

if [ ! -x "$work/tools/bin/bison" ]; then
    echo "Building bison"
    rm -rf "$work/bison-src" && mkdir -p "$work/bison-src"
    tar -xJf "$work/downloads/bison.tar.xz" -C "$work/bison-src" --strip-components=1
    (cd "$work/bison-src" && PATH=/usr/bin:/bin:/usr/sbin:/sbin ./configure --prefix="$work/tools" >"$work/bison-configure.log" 2>&1 \
        && PATH=/usr/bin:/bin:/usr/sbin:/sbin make -j"$jobs" install >"$work/bison-make.log" 2>&1) \
        || { echo "error: bison failed to build; see $work/bison-*.log" >&2; exit 1; }
fi

if [ ! -x "$work/$MINGW_NAME/bin/x86_64-w64-mingw32-clang" ]; then
    echo "Unpacking llvm-mingw"
    tar -xJf "$work/downloads/llvm-mingw.tar.xz" -C "$work"
fi

echo "Unpacking Wine $WINE_VERSION and applying the patch"
rm -rf "$work/wine-src" "$work/wine-build"
mkdir -p "$work/wine-src" "$work/wine-build"
tar -xJf "$work/downloads/wine.tar.xz" -C "$work/wine-src" --strip-components=1
(cd "$work/wine-src" && patch -p1 <"$patch_file")

# llvm-mingw goes last so that its clang does not shadow Apple's.
export PATH="$work/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin:$work/$MINGW_NAME/bin"
export MACOSX_DEPLOYMENT_TARGET=14.0

echo "Configuring Wine"
(cd "$work/wine-build" && CC="/usr/bin/clang -arch x86_64" CXX="/usr/bin/clang++ -arch x86_64" \
    ../wine-src/configure --host=x86_64-apple-darwin --enable-win64 --disable-tests \
    --without-x --without-freetype --without-gnutls --without-gstreamer --without-vulkan --without-sdl \
    --without-cups --without-pcap --without-usb --without-v4l2 --without-krb5 --without-unwind \
    --without-pulse --without-alsa --without-oss --without-capi --without-inotify --without-dbus \
    --without-sane --without-gphoto --without-ffmpeg >"$work/wine-configure.log" 2>&1) \
    || { echo "error: configure failed; last lines:" >&2; tail -30 "$work/wine-configure.log" >&2; exit 1; }

echo "Building winemac.so"
(cd "$work/wine-build" && make -j"$jobs" dlls/winemac.drv/winemac.so >"$work/wine-make.log" 2>&1) \
    || { echo "error: make failed; last lines:" >&2; tail -40 "$work/wine-make.log" >&2; exit 1; }

built="$work/wine-build/dlls/winemac.drv/winemac.so"
nm -gU "$built" | grep -q " _macdrv_functions$" \
    || { echo "error: winemac.so does not export macdrv_functions" >&2; exit 1; }
lipo -archs "$built" | grep -qx "x86_64" || { echo "error: winemac.so is not x86_64 only" >&2; exit 1; }

echo "Packaging"
stage="$work/stage/$NAME"
rm -rf "$work/stage" && mkdir -p "$stage"
cp "$built" "$stage/winemac.so"
cp "$patch_file" "$stage/"
cp "$work/wine-src/COPYING.LIB" "$work/wine-src/LICENSE" "$stage/"
cat >"$stage/README.txt" <<EOF
winemac.so from Wine $WINE_VERSION (x86_64, macOS $MACOSX_DEPLOYMENT_TARGET or later), built with one patch
so that Direct3D-on-Metal layers such as DXMT can draw into windows.

Wine is free software under the GNU LGPL 2.1 or later (see COPYING.LIB and LICENSE).
Source:  $WINE_URL
Patch:   $(basename "$patch_file") (included)
Recipe:  packaging/wine/build-winemac.sh in the Dormer repository

It replaces lib/wine/x86_64-unix/winemac.so of a Wine $WINE_VERSION installation. Dormer does this in a
copy of the Wine engine, never in the original.
EOF
# Fixed owner, order and timestamps so that the archive only changes when its contents do.
find "$stage" -exec touch -t 202601010000 {} +
(cd "$work/stage" && tar --uid 0 --gid 0 --uname root --gname wheel -cf - "$NAME"/COPYING.LIB "$NAME"/LICENSE \
    "$NAME"/README.txt "$NAME"/*.patch "$NAME"/winemac.so | gzip -n >"$work/dist/$NAME.tar.gz")
(cd "$work/dist" && shasum -a 256 "$NAME.tar.gz" >"$NAME.tar.gz.sha256")

echo "Done: $work/dist/$NAME.tar.gz"
cat "$work/dist/$NAME.tar.gz.sha256"
echo "winemac.so sha256: $(shasum -a 256 "$built" | cut -d' ' -f1), $(stat -f %z "$work/dist/$NAME.tar.gz") bytes packed"
