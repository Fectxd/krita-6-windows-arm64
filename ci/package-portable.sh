#!/usr/bin/env bash
# Assemble a self-contained, portable Krita for Windows ARM64 from the build
# tree, pulling in the runtime DLLs / plugin dirs / data files it needs from the
# MSYS2 CLANGARM64 prefix, then zip it.
#
# Usage: ci/package-portable.sh <version> [workdir] [outdir]
set -euo pipefail

VERSION="${1:?usage: package-portable.sh <version> [workdir] [outdir]}"
WORK="${2:-$PWD/work}"
OUT="${3:-$PWD/dist}"
BUILD="$WORK/build-${MSYSTEM:-CLANGARM64}"
PREFIX="${MINGW_PREFIX:?run inside MSYS2 CLANGARM64}"

APPNAME="Krita-$VERSION-arm64"
STAGE="$WORK/stage"
APP="$OUT/$APPNAME"
ZIP="$OUT/krita-$VERSION-windows-arm64.zip"

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m[!]\033[0m %s\n' "$*"; }

rm -rf "$STAGE" "$APP"
mkdir -p "$STAGE" "$APP" "$OUT"

step "Installing the build tree into $APP"
DESTDIR="$STAGE" cmake --install "$BUILD" >/dev/null
cp -a "$STAGE$PREFIX/." "$APP/"
[[ -f "$APP/bin/krita.exe" ]] || { echo "krita.exe missing from install tree" >&2; exit 1; }
ok "bin/krita.exe present"

step "Pruning build-only files"
for d in lib/cmake lib/pkgconfig include share/man share/doc/HTML; do
  rm -rf "${APP:?}/$d"
done

step "Deploying Qt runtime (windeployqt)"
if command -v windeployqt >/dev/null 2>&1; then
  windeployqt --release --no-translations --no-compiler-runtime \
              --no-system-d3d-compiler --no-opengl-sw \
              "$APP/bin/krita.exe" >/dev/null 2>&1 && ok "windeployqt done" || warn "windeployqt returned non-zero"
else
  warn "windeployqt not found"
fi

step "Adding KDE / MSYS2 Qt plugins"
for cat in platforms styles imageformats iconengines networkinformation tls generic; do
  src="$PREFIX/share/qt6/plugins/$cat"
  [[ -d "$src" ]] || continue
  mkdir -p "$APP/bin/$cat"
  for dll in "$src"/*.dll; do
    [[ -e "$dll" ]] && cp -f "$dll" "$APP/bin/$cat/"
  done
done
cp -f "$PREFIX/share/qt6/plugins/platforms/qwindows.dll" "$APP/bin/platforms/" 2>/dev/null || true
ok "plugins in place"

step "Collecting transitive MSYS2 DLL dependencies"
declare -A SEEN=()
QUEUE=()
while IFS= read -r f; do QUEUE+=("$f"); done < <(find "$APP" -type f \( -iname '*.exe' -o -iname '*.dll' \) | sort)

copied=0
idx=0
while [[ $idx -lt ${#QUEUE[@]} ]]; do
  f="${QUEUE[$idx]}"; idx=$((idx + 1))
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    case "$dep" in
      "$PREFIX"/*) ;;
      *) continue ;;   # system DLL (C:/Windows/...) or empty
    esac
    base="$(basename "$dep")"
    [[ -n "${SEEN[$base]:-}" ]] && continue
    SEEN[$base]=1
    if [[ ! -f "$APP/bin/$base" ]]; then
      cp -f "$dep" "$APP/bin/"
      copied=$((copied + 1))
    fi
    QUEUE+=("$APP/bin/$base")
  done < <(ldd "$f" 2>/dev/null | awk '{print $3}' | grep '^/' || true)
done
ok "$copied runtime DLL(s) added from $PREFIX"

step "Copying runtime data directories"
DATA_DIRS=(
  share/krita
  share/mypaint-data
  share/OpenColorIO
  share/poppler
  share/mlt-7
  lib/mlt-7
  share/qt6/translations
  share/locale
  share/icons/hicolor
  etc/fonts
  lib/gdk-pixbuf-2.0
  share/glib-2.0
)
for d in "${DATA_DIRS[@]}"; do
  if [[ -e "$PREFIX/$d" && ! -e "$APP/$d" ]]; then
    mkdir -p "$APP/$(dirname "$d")"
    cp -a "$PREFIX/$d" "$APP/$d" 2>/dev/null || warn "could not copy $d"
    ok "$d"
  fi
done
# Python standard library + PyQt6 (Krita's scripting support)
for pydir in "$PREFIX"/lib/python3.*; do
  [[ -d "$pydir" ]] || continue
  base="$(basename "$pydir")"
  [[ -e "$APP/lib/$base" ]] && continue
  mkdir -p "$APP/lib"
  cp -a "$pydir" "$APP/lib/$base" 2>/dev/null || warn "could not copy $base"
  ok "lib/$base"
done

step "Writing qt.conf + launcher"
cat > "$APP/bin/qt.conf" <<'QTCONF'
[Paths]
Prefix = ..
Plugins = bin
Translations = share/qt6/translations
QTCONF

cat > "$APP/krita-portable.bat" <<'BAT'
@echo off
setlocal
set "APPDIR=%~dp0"
set "PATH=%APPDIR%bin;%PATH%"
set "QT_PLUGIN_PATH=%APPDIR%bin"
if exist "%APPDIR%etc\fonts" set "FONTCONFIG_PATH=%APPDIR%etc\fonts"
if exist "%APPDIR%lib\python3.13" set "PYTHONHOME=%APPDIR%"
start "" "%APPDIR%bin\krita.exe" %*
BAT

cat > "$APP/README-PORTABLE.txt" <<TXT
Krita $VERSION — portable native Windows ARM64 build
=====================================================

Start it with krita-portable.bat (or bin\\krita.exe directly).

Built from the official KDE source release tarball, compiled natively for
arm64 against the MSYS2 CLANGARM64 toolchain (Qt 6 + KF6 + the imaging stack).
No x64 emulation is involved.

This is an unofficial community build. Krita is (C) the Krita Foundation and
the KDE community, GPL-3.0-or-later; see share/licenses/krita.
TXT

step "Zipping"
rm -f "$ZIP"
if command -v zip >/dev/null 2>&1; then
  ( cd "$OUT" && zip -r -q -1 "$(basename "$ZIP")" "$APPNAME" )
else
  warn "zip not found, leaving the unpacked tree at $APP"
fi

du -sh "$APP" || true
[[ -f "$ZIP" ]] && ls -lh "$ZIP"
ok "packaged $APPNAME"
