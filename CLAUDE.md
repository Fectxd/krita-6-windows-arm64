# Krita for Windows on ARM — Build System Context

## What this repo is
Tooling to build a native ARM64 Windows installer for Krita 5.3.2.1.
The repo does NOT contain Krita source or deps — those live outside in fixed locations.

## Key paths (hardcoded throughout scripts)
| Path | Contents |
|------|----------|
| `C:\KritaARM\` | Clone of THIS repo (scripts run from here) |
| `C:\KritaARM\krita-src\` | Krita 5.3.2.1 source (fetched separately, gitignored) |
| `C:\kritadeps\i\` | Pre-built ARM64 dependency prefix (Qt5, KDE Frameworks, etc.) |
| `C:\kritadeps\b\krita\` | CMake build directory |
| `C:\kritadeps\krita-install\` | CMake install prefix |
| `C:\kritadeps\pkg\` | Packaging output directory |
| `C:\kritadeps\python313-dev\` | Junction → `C:\kritadeps\i\python` (required by scripts) |
| `C:\KritaARM\packaging\arm64-installer\` | NSIS installer script + output exe |

The repo is ALSO cloned to `C:\Users\Queuereel\Documents\GitHub\krita-for-windows-on-arm` — that's the git remote used for pushing/releasing. Keep both in sync or push from either.

## ARM64 deps
Downloaded from GitHub release `deps-arm64-v1` on this repo. The zip extracts to `C:\kritadeps\i\`.
Python is at `C:\kritadeps\i\python\` — the junction at `C:\kritadeps\python313-dev` points there.

## How to build (full sequence)
```
C:\KritaARM\build-krita-arm64.bat -SkipDeps
```
Or manually:
```cmd
call C:\KritaARM\scripts\dep-env.cmd
cmake -S C:\KritaARM\krita-src -B C:\kritadeps\b\krita -G Ninja ^
  -DCMAKE_BUILD_TYPE=RelWithDebInfo ^
  -DCMAKE_PREFIX_PATH=C:\kritadeps\i ^
  -DCMAKE_INSTALL_PREFIX=C:\kritadeps\krita-install
cmake --build C:\kritadeps\b\krita --parallel
cmake --install C:\kritadeps\b\krita
```

## How to package
```powershell
# From an environment where dep-env.cmd has been called:
powershell -ExecutionPolicy Bypass -File C:\KritaARM\scripts\package-krita-arm64.ps1
```
This runs `package-complete-msvc.py` then `build-installer.ps1` (NSIS).
Output: `C:\KritaARM\packaging\arm64-installer\krita-5.3.2.1-windows-arm64-setup.exe`

**IMPORTANT**: After packaging, manually run windeployqt or the Qt DLLs won't be in the package:
```powershell
$env:PATH = "C:\kritadeps\i\bin;$env:PATH"
$pkg = "C:\kritadeps\pkg\krita-5.3.2.1-windows-arm64"
windeployqt.exe --release -gui -core -concurrent -network -printsupport -svg -xml -sql -qml -quick -quickwidgets "$pkg\bin\krita.exe" "$pkg\bin\krita.dll"
```
Then rebuild the zip and installer manually (see scripts).

## ARM64 patches (in `arm64-patches/krita-source/`)
Patches applied on top of upstream Krita source. Apply by copying files over krita-src:

| Patch file | What it fixes |
|-----------|---------------|
| `libs/ui/CMakeLists.txt` | Adds `KisRootSurfaceInfoProxy.h` as explicit target_source so AUTOMOC generates its MOC even when `KRITA_USE_SURFACE_COLOR_MANAGEMENT_API=OFF` (Windows/no Wayland). Without this, LNK2001 unresolved `staticMetaObject`. |
| `libs/ui/KisRootSurfaceInfoProxy.cpp` | Removes inline `#include "moc_..."` that was suppressing AUTOMOC global moc generation. |
| `libs/ui/KisMultiSurfaceStateManager.cpp` | ARM64 compat fix. |
| `libs/ui/KisViewManager.cpp` | ARM64 compat fix. |
| `libs/ui/widgets/KisGrabKeyboard*.cpp` | ARM64 compat fix. |
| `libs/widgets/KoZoomActionState*.cpp` | ARM64 compat fix. |
| `packaging/windows/package-complete-msvc.py` | Makes `kritarunner.exe` optional (pykrita not built); replaces bare `exit()` with `sys.exit()` for embedded Python compat. |

## Known issues / gotchas

### AUTOMOC LNK2001 (SOLVED)
`KisRootSurfaceInfoProxy::staticMetaObject` unresolved. Root cause: `KRITA_USE_SURFACE_COLOR_MANAGEMENT_API=OFF` on Windows skips compiling `KisRootSurfaceInfoProxy.cpp`, so AUTOMOC never generates its MOC. But `kis_dlg_preferences.cc` includes the header unconditionally, creating the linker reference.
**Fix**: `CMakeLists.txt` patch adds `target_sources(kritaui PRIVATE KisRootSurfaceInfoProxy.h)` in a `if (NOT KRITA_USE_SURFACE_COLOR_MANAGEMENT_API)` block. DO NOT re-add `#include "moc_KisRootSurfaceInfoProxy.cpp"` inline — that puts AUTOMOC in inline mode and breaks it.

### AUTOMOC parse cache staleness
If you hit MOC-related linker errors, delete these before rebuilding:
```
C:\kritadeps\b\krita\libs\ui\CMakeFiles\kritaui_autogen.dir\ParseCache.txt
C:\kritadeps\b\krita\libs\ui\kritaui_autogen\   (whole directory)
```

### krita.ico missing during cmake --install
`ecm_add_app_icon` doesn't generate the ICO on this setup. Fix:
```powershell
Copy-Item "C:\KritaARM\krita-src\krita\pics\branding\default\krita.ico" "C:\kritadeps\b\krita\krita\krita.ico"
Copy-Item "C:\KritaARM\krita-src\krita\pics\branding\default\krita.ico" "C:\kritadeps\b\krita\krita\kritafile.ico"
```
Then re-run `cmake --install`.

### Python / pykrita not built
PyQt5 and SIP are in `C:\kritadeps\i\python\Lib\site-packages\` but CMake doesn't auto-detect them. `kritarunner.exe` and the Python scripting plugin are absent. Packaging scripts handle this gracefully.

### Package script crashes before windeployqt
`package-complete-msvc.py` sometimes exits after file copying without running windeployqt, leaving the package without Qt DLLs. Always verify `Qt5Core.dll` etc. are in the package bin before releasing.

## GitHub release process
```powershell
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
Set-Location "C:\Users\Queuereel\Documents\GitHub\krita-for-windows-on-arm"
gh release create v5.x.x.x `
  "path\to\setup.exe#filename.exe" `
  "path\to\package.zip#filename.zip" `
  --title "Krita 5.x.x.x (ARM64)" --notes "..."
```
The installer goes to GitHub Releases, NOT into the git repo.

## Build environment
- VS Build Tools 2022 ARM64 at `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`
- `dep-env.cmd` calls `vcvarsall.bat arm64` and sets all required env vars
- NSIS at `C:\Program Files (x86)\NSIS\makensis.exe`
- 7-Zip at `C:\Program Files\7-Zip\7z.exe`
- GitHub CLI: `gh` (must run `gh auth login` once per machine)
