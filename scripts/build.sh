#!/usr/bin/env bash
# Build a GE-Proton-Frontier release.
#
# Takes GloriousEggroll's official x86_64 GE-Proton release, rebuilds only
# dwrite.dll from the Wine commit that GE tag pins with patches/*.patch
# applied, swaps it in, renames the tool and re-packs it. Nothing else in
# GE's build is touched, so a release is "GE-Proton, plus one DLL".
#
# Usage:   scripts/build.sh GE-Proton11-7-Frontier1
# Output:  dist/<tag>.tar.gz, dist/<tag>.sha512sum, dist/BUILDINFO
#
# Run it inside `nix develop` so the toolchain matches CI. Downloads are
# cached in work/ and re-verified on every run.
set -euo pipefail

TAG=${1:?usage: scripts/build.sh GE-ProtonX-Y-FrontierN}
# The tag carries the GE release it is built on. Anything else is a mistake,
# and failing here beats publishing a release built on the wrong GE version.
if [[ ! $TAG =~ ^(GE-Proton[0-9]+-[0-9]+)-Frontier([0-9]+)$ ]]; then
    echo "error: tag '$TAG' is not of the form GE-ProtonX-Y-FrontierN" >&2
    exit 1
fi
GE_TAG=${BASH_REMATCH[1]}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK_DIR:-$ROOT/work}
DIST=$ROOT/dist
GE_REPO=https://github.com/GloriousEggroll/proton-ge-custom
GE_ASSET=$GE_TAG-x86_64

mkdir -p "$WORK" "$DIST"
cd "$WORK"
step() { printf '\n== %s\n' "$*"; }

step "GE release $GE_TAG"
# GE publishes a .sha512sum next to every tarball; a download that does not
# match it is never used.
curl -fsSL --retry 3 -o "$GE_ASSET.sha512sum" "$GE_REPO/releases/download/$GE_TAG/$GE_ASSET.sha512sum"
if ! sha512sum --status -c "$GE_ASSET.sha512sum" 2>/dev/null; then
    curl -fL --retry 3 -o "$GE_ASSET.tar.gz" "$GE_REPO/releases/download/$GE_TAG/$GE_ASSET.tar.gz"
    sha512sum -c "$GE_ASSET.sha512sum"
fi
GE_SHA512=$(cut -d' ' -f1 "$GE_ASSET.sha512sum")

step "Wine commit pinned by $GE_TAG"
# GE's wine is a submodule; the tag's tree records the exact commit. Read it
# from git rather than the GitHub API so it works without a token.
rm -rf ge-src
git clone -q --filter=blob:none --no-checkout --depth 1 --branch "$GE_TAG" "$GE_REPO" ge-src
WINE_URL=$(git -C ge-src show HEAD:.gitmodules | git config -f - submodule.wine.url)
read -r WINE_MODE WINE_TYPE WINE_COMMIT _ < <(git -C ge-src ls-tree HEAD wine)
[[ $WINE_MODE == 160000 && $WINE_TYPE == commit ]] || { echo "error: 'wine' in $GE_TAG is not a submodule" >&2; exit 1; }
[[ $WINE_URL == https://github.com/* ]] || { echo "error: unexpected wine submodule URL $WINE_URL" >&2; exit 1; }
echo "$WINE_URL @ $WINE_COMMIT"

step "Wine source"
[[ -f wine-$WINE_COMMIT.tar.gz ]] || curl -fL --retry 3 -o "wine-$WINE_COMMIT.tar.gz" "${WINE_URL%.git}/archive/$WINE_COMMIT.tar.gz"
WINE_SRC_SHA256=$(sha256sum "wine-$WINE_COMMIT.tar.gz" | cut -d' ' -f1)
rm -rf wine-src wine-build
mkdir wine-src
tar -xzf "wine-$WINE_COMMIT.tar.gz" -C wine-src --strip-components=1

step "Patches"
# --fuzz=0: a patch that only applies loosely to a new Wine commit needs a
# human to look at it, not a best guess.
for p in "$ROOT"/patches/*.patch; do
    echo "${p##*/}"
    patch -d wine-src -p1 --forward --fuzz=0 < "$p"
done

step "Generated sources"
# A git checkout of Wine ships neither configure nor the files the release
# tarballs pre-generate. vk.xml is in-tree, so none of this needs network.
# The perl scripts hard-code /usr/bin/perl, hence the explicit interpreter.
(
    cd wine-src
    autoheader -f
    autoconf -f
    (cd dlls/winevulkan && python3 ./make_vulkan)
    perl tools/make_specfiles
    perl tools/make_requests
) > generate.log 2>&1 || { tail -30 generate.log; exit 1; }

step "Build dwrite.dll"
# Only the PE side is rebuilt. GE's unix-side dwrite.so is kept: the patch
# does not touch the PE/unix interface, and GE's patch sets do not touch
# dlls/dwrite at all.
mkdir wine-build
(
    cd wine-build
    ../wine-src/configure --enable-win64 --with-mingw=x86_64-w64-mingw32-gcc --disable-tests \
        --without-x --without-freetype --without-fontconfig --without-alsa --without-pulse \
        --without-gstreamer --without-opengl --without-vulkan --without-wayland --without-dbus \
        --without-cups --without-udev --without-usb --without-v4l2 --without-sane --without-gphoto \
        --without-pcap --without-netapi --without-krb5 --without-gnutls --without-sdl --without-capi \
        --without-opencl --without-oss --without-coreaudio --without-ffmpeg --without-pcsclite \
        --without-piper --without-xml --without-xslt --without-unwind --without-gettext \
        --without-gettextpo > configure.log 2>&1 || { tail -30 configure.log; exit 1; }
    make -j"$(nproc)" dlls/dwrite/x86_64-windows/dwrite.dll > make.log 2>&1 || { tail -30 make.log; exit 1; }
)
x86_64-w64-mingw32-strip -o dwrite.dll wine-build/dlls/dwrite/x86_64-windows/dwrite.dll
DLL_SHA256=$(sha256sum dwrite.dll | cut -d' ' -f1)

step "Assemble $TAG"
rm -rf stage
mkdir stage
tar -xzf "$GE_ASSET.tar.gz" -C stage
[[ -d stage/$GE_ASSET ]] || { echo "error: $GE_ASSET.tar.gz does not unpack to $GE_ASSET/" >&2; exit 1; }
mv "stage/$GE_ASSET" "stage/$TAG"
T=stage/$TAG

# The default prefix only symlinks into lib/wine, so this one file covers it.
# The 32-bit dwrite.dll is left as GE built it.
install -m 0555 dwrite.dll "$T/files/lib/wine/x86_64-windows/dwrite.dll"

# Own name everywhere, so it installs next to stock GE instead of over it.
sed -i "s/\"$GE_ASSET\"/\"$TAG\"/g" "$T/compatibilitytool.vdf"
[[ $(grep -c "\"$TAG\"" "$T/compatibilitytool.vdf") -eq 2 ]] || { echo "error: compatibilitytool.vdf rename failed" >&2; exit 1; }

# Ship the source of the change inside the tool, as the LGPL asks.
mkdir "$T/frontier"
cp "$ROOT"/patches/*.patch "$T/frontier/"
BUILT_BY="local build"
[[ -n ${GITHUB_RUN_ID:-} ]] && BUILT_BY="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
cat > "$T/frontier/BUILDINFO" <<EOF
release:           $TAG
based on:          GloriousEggroll GE-Proton $GE_TAG ($GE_ASSET.tar.gz)
based on sha512:   $GE_SHA512
wine source:       $WINE_URL @ $WINE_COMMIT
wine tarball sha256: $WINE_SRC_SHA256
patches:
$(cd "$ROOT/patches" && sha256sum ./*.patch | sed 's|  \./|  |; s/^/  /')
changed file:      files/lib/wine/x86_64-windows/dwrite.dll
dwrite.dll sha256: $DLL_SHA256
built by:          $BUILT_BY
source commit:     $(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
EOF
cp "$T/frontier/BUILDINFO" "$DIST/BUILDINFO"

step "Package"
# Fixed ownership, order and timestamps, so the same inputs give the same tarball.
EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || date +%s)}
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$EPOCH" \
    -C stage -cf - "$TAG" | gzip -n > "$DIST/$TAG.tar.gz"
(cd "$DIST" && sha512sum "$TAG.tar.gz" > "$TAG.sha512sum")

step "Done"
cat "$DIST/BUILDINFO"
ls -l "$DIST"
