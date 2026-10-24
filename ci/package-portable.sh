#!/usr/bin/env bash
# Assemble a self-contained, portable Krita for Windows ARM64 from the install
# tree, pulling in the runtime DLLs / plugin dirs / data files it needs from the
# MSYS2 CLANGARM64 prefix, then zip it.
#
# Usage: ci/package-portable.sh <version> [workdir] [outdir]
set -euo pipefail

VERSION="${1:?usage: package-portable.sh <version> [workdir] [outdir]}"
WORK="${2:-$PWD/work}"
OUT="${3:-$PWD/dist}"
INSTALL="$WORK/install"
: "${MINGW_PREFIX:?run inside MSYS2 CLANGARM64}"

APPNAME="Krita-$VERSION-arm64"
APP="$OUT/$APPNAME"
ZIP="$OUT/krita-$VERSION-windows-arm64.zip"

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m[!]\033[0m %s\n' "$*"; }

[[ -f "$INSTALL/bin/krita.exe" ]] || { echo "no install tree at $INSTALL - run build-krita.sh first" >&2; exit 1; }

rm -rf "$APP"; mkdir -p "$APP" "$OUT"

step "Copying install tree"
cp -a "$INSTALL/." "$APP/"
ok "bin/krita.exe present"

step "Pruning build-only files"
for d in lib/cmake lib/pkgconfig include share/man; do
  rm -rf "${APP:?}/$d"
done

step "Deploying Qt runtime (windeployqt)"
if command -v windeployqt >/dev/null 2>&1; then
  if windeployqt --release --no-translations --no-compiler-runtime \
                 --no-system-d3d-compiler --no-opengl-sw \
                 "$APP/bin/krita.exe" >/dev/null 2>&1; then
    ok "windeployqt done"
  else
    warn "windeployqt returned non-zero (continuing; ldd sweep will fill the gaps)"
  fi
else
  warn "windeployqt not found"
fi

step "Adding Qt / KDE plugin categories"
for cat in platforms styles imageformats iconengines networkinformation tls generic; do
  src="$MINGW_PREFIX/share/qt6/plugins/$cat"
  [[ -d "$src" ]] || continue
  mkdir -p "$APP/bin/$cat"
  cp -f "$src"/*.dll "$APP/bin/$cat/" 2>/dev/null || true
done
ok "plugin categories copied"

step "Collecting transitive MSYS2 DLL dependencies"
# Read the PE import tables with objdump instead of ldd: ldd has to load every
# DLL, which takes seconds per file on arm64, whereas objdump just parses the
# import directory (milliseconds).
OBJDUMP="$(command -v objdump || command -v llvm-objdump || true)"
[[ -n "$OBJDUMP" ]] || { echo "no objdump/llvm-objdump available" >&2; exit 1; }

declare -A SEEN=()
QUEUE=()
while IFS= read -r f; do QUEUE+=("$f"); done \
  < <(find "$APP" -type f \( -iname '*.exe' -o -iname '*.dll' -o -iname '*.pyd' \) | sort)

copied=0
idx=0
while [[ $idx -lt ${#QUEUE[@]} ]]; do
  f="${QUEUE[$idx]}"; idx=$((idx + 1))
  while IFS= read -r want; do
    want="${want%$'\r'}"
    [[ -n "$want" ]] || continue
    key="${want,,}"
    [[ -n "${SEEN[$key]:-}" ]] && continue
    SEEN[$key]=1
    src="$MINGW_PREFIX/bin/$want"
    if [[ ! -f "$src" ]]; then
      src="$(find "$MINGW_PREFIX/bin" -maxdepth 1 -iname "$want" -print -quit 2>/dev/null || true)"
    fi
    [[ -n "$src" && -f "$src" ]] || continue
    base="$(basename "$src")"
    if [[ ! -f "$APP/bin/$base" ]]; then
      cp -f "$src" "$APP/bin/"
      copied=$((copied + 1))
    fi
    QUEUE+=("$APP/bin/$base")
  done < <("$OBJDUMP" -p "$f" 2>/dev/null | awk '/DLL Name:/ {print $3}')
done
ok "$copied runtime DLL(s) added from $MINGW_PREFIX"

step "Copying runtime data directories"
DATA_DIRS=(
  share/mypaint-data
  share/OpenColorIO
  share/poppler
  share/mlt-7
  lib/mlt-7
  share/qt6/translations
  share/locale
  share/icons/hicolor
  etc/fonts
)
for d in "${DATA_DIRS[@]}"; do
  if [[ -e "$MINGW_PREFIX/$d" && ! -e "$APP/$d" ]]; then
    mkdir -p "$APP/$(dirname "$d")"
    cp -a "$MINGW_PREFIX/$d" "$APP/$d" 2>/dev/null || warn "could not copy $d"
    ok "$d"
  fi
done

step "Adding Python runtime (scripting support)"
for pydir in "$MINGW_PREFIX"/lib/python3.*; do
  [[ -d "$pydir" ]] || continue
  base="$(basename "$pydir")"
  [[ -e "$APP/lib/$base" ]] && continue
  mkdir -p "$APP/lib"
  cp -a "$pydir" "$APP/lib/$base" 2>/dev/null || warn "could not copy $base"
  # drop caches + headers, keep the stdlib and site-packages
  rm -rf "$APP/lib/$base/__pycache__" "$APP/lib/$base/config-"* "$APP/include" 2>/dev/null || true
  ok "lib/$base"
done

step "Writing qt.conf, launcher and readme"
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
for /d %%D in ("%APPDIR%lib\python3.*") do set "PYTHONHOME=%APPDIR%"
start "" "%APPDIR%bin\krita.exe" %*
BAT

cat > "$APP/README-PORTABLE.txt" <<TXT
Krita $VERSION - portable native Windows ARM64 build
====================================================

Start it with krita-portable.bat (or bin\krita.exe directly).

Compiled natively for arm64 from the official KDE source release against the
MSYS2 CLANGARM64 toolchain (Qt 6 + KF6 + the imaging stack). No x64 emulation.

This is an unofficial community build. Krita is (C) the Krita Foundation and the
KDE community, GPL-3.0-or-later; see share/licenses/krita.
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
