# Krita for Windows on ARM — GitHub Actions build

Native **arm64** Krita for Windows-on-ARM laptops (Snapdragon X and friends),
compiled by GitHub Actions on an ARM64 Windows runner. No emulation, no x64
translation layer.

## Download

Grab the newest zip from the **[Releases page](../../releases)**:
`krita-<version>-windows-arm64.zip`. Unzip anywhere and start it with
`krita-portable.bat` (or `bin\krita.exe`). Requires Windows 10/11 on ARM64.

## How the build works

The pipeline lives in [`.github/workflows/build-krita-arm64.yml`](.github/workflows/build-krita-arm64.yml)
and runs on `windows-11-arm`:

1. Sets up **MSYS2 CLANGARM64** — a native arm64 clang/LLVM toolchain for
   Windows. Qt 6, KF6, poppler, mlt, ffmpeg, libheif, OpenColorIO, PyQt6 and the
   rest of Krita's dependency stack are installed as *prebuilt* MSYS2 packages,
   so no 8-hour Qt compile is needed.
2. Downloads the official Krita release tarball from `download.kde.org`, checks
   its SHA-256, and applies the mingw/clang patches in [`ci/patches/`](ci/patches)
   (same set MSYS2 uses for its own `mingw-w64-krita` package).
3. Configures with CMake (`BUILD_WITH_QT6=ON`, Release) and compiles with ninja.
4. Assembles a self-contained portable tree — `windeployqt`, a recursive `ldd`
   sweep over the MSYS2 prefix for every runtime DLL, Qt/KDE plugins, brush and
   colour-management data, Python stdlib — and zips it.
5. Uploads the zip as a workflow artifact and, when asked, creates a GitHub
   Release.

Trigger it from **Actions → Build Krita (Windows ARM64) → Run workflow**, where
you can override the Krita version and whether a release is published. Pushing a
`v<version>` tag also starts a release build.

Local reproduction (on a Windows ARM64 machine with MSYS2 CLANGARM64 installed):

```bash
./ci/build-krita.sh 6.0.4.1
./ci/package-portable.sh 6.0.4.1
```

## Repository layout

| Path | What |
|------|------|
| `.github/workflows/build-krita-arm64.yml` | The GitHub Actions pipeline |
| `ci/build-krita.sh` | Fetch → patch → cmake → ninja |
| `ci/package-portable.sh` | Stage runtime, deploy Qt, collect DLLs, zip |
| `ci/patches/` | mingw/clang patches applied to the Krita sources |
| `arm64-patches/`, `scripts/`, `packaging/` | Reference material from the original hand-built **MSVC** route (cl.exe + KDE dep recipes). Not used by the CI pipeline; kept for provenance. |
| `BUILD-STATE.md`, `BUILD-PROGRESS.md` | Notes from that hand-build effort |
| `README-msvc-route.md` | The original README of that hand-built route |

## Credits / license

This repository is derived from
**[Queuereel/krita-for-windows-on-arm](https://github.com/Queuereel/krita-for-windows-on-arm)**
(the original hand-built native arm64 port, whose MSVC tooling, patch notes and
packaging scripts are preserved here), and its CI recipe follows the
**[MSYS2 `mingw-w64-krita` PKGBUILD](https://github.com/msys2/MINGW-packages/tree/master/mingw-w64-krita)**
dependency set and patch series.

Krita is © the Krita Foundation / KDE community, GPL-3.0-or-later. This project's
own build tooling is GPL-3.0-or-later as well; every patched file keeps its
upstream license header. See [LICENSE.md](LICENSE.md).

This is an **unofficial, independent community build** — not affiliated with or
endorsed by the Krita Foundation or KDE. "Krita" and the Krita logo are
trademarks of the Krita Foundation, used only to identify a faithful native build.
