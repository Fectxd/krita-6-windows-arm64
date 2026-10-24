## Krita 6 for Windows ARM64 — native build

Compiled on GitHub Actions' `windows-11-arm` runner with the MSYS2 **CLANGARM64**
toolchain. `bin\krita.exe` is a native arm64 PE — no x64 emulation.

**Use it:** unzip, then run `krita-portable.bat` (or `bin\krita.exe`).
Needs Windows 10/11 on an ARM64 device (Snapdragon X, etc.).

**Included:** Qt 6 base/svg/declarative/5compat + KF6 modules, Krita's full
plugin set, image format support (PNG/JPEG/TIFF/WebP/JPEG-XL/HEIF/OpenEXR/PSD
via kimageformats), OpenColorIO, MyPaint brushes, mlt + ffmpeg (animation
export), Python 3 + PyQt6 scripting.

**Not included:** the NSIS one-click installer (use the portable zip), debug
symbols, and third-party ICC/brush bundles that the official installer offers.

Notes:

- Built from the official `krita-<version>.tar.xz` release tarball from
  `download.kde.org`, with the mingw/clang patch set in `ci/patches/`.
- This is an unofficial community build. Krita is © the Krita Foundation and the
  KDE community, GPL-3.0-or-later; see `share/licenses/krita` inside the zip.
  Please back up artwork you care about, as with any new build.
- Report problems on the issue tracker of this repository, not to the Krita
  Foundation.
