#!/usr/bin/env bash
# Build Krita for Windows ARM64 inside an MSYS2 CLANGARM64 environment.
#
# Everything Krita links against (Qt 6, KF6, libraw-free imaging stack, poppler,
# mlt, ffmpeg, python/PyQt6) is installed as a prebuilt MSYS2 package, so this
# script only has to fetch Krita's own sources, apply the mingw/clang patches and
# run cmake + ninja.
#
# Usage: ci/build-krita.sh <version> [workdir]
set -euo pipefail

VERSION="${1:?usage: build-krita.sh <version> [workdir]}"
WORK="${2:-$PWD/work}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KDE_BASE="${KDE_BASE:-https://download.kde.org/stable/krita}"

PREFIX="${MINGW_PREFIX:?run inside MSYS2 CLANGARM64}"
SRC="$WORK/krita-$VERSION"
BUILD="$WORK/build-${MSYSTEM:-CLANGARM64}"
TARBALL="$WORK/krita-$VERSION.tar.xz"
JOBS="$(nproc)"

# SHA256 of the official release tarballs we have verified. Unknown versions are
# still allowed (with a warning) so the workflow can be pointed at a new release.
declare -A KNOWN_SHA256=(
  ["6.0.4.1"]="bd0568754417ffca0ef60448d1cc7fb153658af1fb9796f027fa7e69b69098df"
)

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m[!]\033[0m %s\n' "$*"; }

mkdir -p "$WORK"

step "Fetching Krita $VERSION sources"
if [[ -f "$TARBALL" && -d "$SRC" ]]; then
  ok "already unpacked"
else
  curl --fail --location --retry 3 --retry-delay 5 \
       --output "$TARBALL" "$KDE_BASE/$VERSION/krita-$VERSION.tar.xz"

  expected="${KNOWN_SHA256[$VERSION]:-}"
  actual="$(sha256sum "$TARBALL" | awk '{print $1}')"
  if [[ -n "$expected" ]]; then
    [[ "$actual" == "$expected" ]] || { echo "sha256 mismatch: $actual != $expected" >&2; exit 1; }
    ok "sha256 $actual"
  else
    warn "no pinned sha256 for $VERSION (got $actual)"
  fi

  tar -xf "$TARBALL" -C "$WORK"
  [[ -d "$SRC" ]] || { echo "expected $SRC after unpack" >&2; exit 1; }
fi

step "Applying mingw / clang patches"
cd "$SRC"
for p in "$REPO_ROOT"/ci/patches/*.patch; do
  name="$(basename "$p")"
  if patch -Nbp1 -i "$p" >/dev/null 2>&1; then
    ok "$name"
  else
    if patch -Nbp1 --dry-run -i "$p" >/dev/null 2>&1; then
      ok "$name (already applied)"
    else
      warn "$name did not apply cleanly"
      patch -Nbp1 -i "$p" || true   # show the conflict in the log
    fi
  fi
done

step "Configuring (Release, Qt6, no tests)"
cmake -GNinja \
  -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_CXX_STANDARD=17 \
  -DBUILD_TESTING=OFF \
  -DBUILD_WITH_QT6=ON \
  -DALLOW_UNSTABLE=QT6 \
  -DENABLE_UPDATERS=OFF \
  -DPython_EXECUTABLE="$PREFIX/bin/python" \
  -DCMAKE_INSTALL_DATAROOTDIR=share

step "Compiling Krita with $JOBS jobs"
cmake --build "$BUILD" --parallel "$JOBS"

ok "Krita $VERSION built into $BUILD"
