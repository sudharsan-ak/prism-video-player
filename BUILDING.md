# Building Prism

## Requirements

- Windows 10/11
- Visual Studio 2022 (Build Tools or full IDE) with the "Desktop development with C++" workload
- Qt 6.5+ (MSVC 64-bit kit), with CMake and Ninja support
- CMake 3.21+
- [libmpv](https://sourceforge.net/projects/mpv-player-windows/files/libmpv/) development package (DLL + `.lib` + headers), placed under `vendor/libmpv/` as:
  ```
  vendor/libmpv/bin/libmpv-2.dll
  vendor/libmpv/lib/libmpv.lib
  vendor/libmpv/include/...
  ```

## Build steps

Open **"Developer PowerShell for VS 2022"** (Start menu) — a plain terminal won't have the MSVC compiler environment set up, and the build will fail with missing standard-library headers.

If it defaults to x86 instead of x64, force it:

```powershell
Enter-VsDevShell -Arch amd64 -SkipAutomaticLocation
```

Then, from the project root:

```powershell
cmake -S . -B build -G Ninja
cmake --build build
```

This produces `build\Prism.exe` along with `libmpv-2.dll` copied next to it.

## Running a standalone copy

To run Prism outside the build folder, deploy the Qt runtime files alongside the exe:

```powershell
windeployqt build\Prism.exe
```

This copies the required Qt DLLs and QML modules into the same folder as the exe, making it runnable on its own.

## Video editing: trim export (first editing PR)

Prism uses **FFmpeg only for exporting** edited video. Playback still uses
libmpv, and FFmpeg never runs for normal playback.

Supply a trusted **Windows x64 static FFmpeg build** (with `libx264` and
`aac` encoders) from a distributor linked by [FFmpeg's download page](https://ffmpeg.org/download.html).
The FFmpeg executable is not checked into this repository.

Choose either setup:

1. Put `ffmpeg.exe` on your Windows `PATH`, so `Get-Command ffmpeg` works.
2. Put it in `vendor/ffmpeg/bin/ffmpeg.exe`, reconfigure CMake
   (`cmake -S . -B build -G Ninja`), and build. It will be copied next
   to `build/Prism.exe`.

**If you launch `dist/Prism/Prism.exe`**, copy FFmpeg alongside it as well:

```powershell
# When using the vendored FFmpeg path:
Copy-Item "vendor\ffmpeg\bin\ffmpeg.exe" "dist\Prism\ffmpeg.exe" -Force
```

Prism first looks for `ffmpeg.exe` beside the running `Prism.exe`, then on
`PATH`. No installer, download, or network access is performed by Prism.

**Phase 1 export limitations:** creates a new H.264/AAC MP4, re-encodes
for accurate trim points, keeps the first audio track (if present),
does not preserve embedded/external subtitles or additional audio tracks,
and does not yet crop or rotate output. The original source is never
overwritten; failed/canceled exports clean up their temporary file.
Only the final successfully encoded file gets its selected name.

**License note:** FFmpeg builds differ in LGPL/GPL licensing based on
configuration. Review the build's licenses and attribution before shipping
FFmpeg to others. The application repo does not redistribute it.
