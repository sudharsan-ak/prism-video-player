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
and does not yet crop or rotate output. Export Copy never modifies the
source; Replace Original requires confirmation and encodes before swapping
the file. Failed/canceled copy exports clean up their temporary file.
Only the final successfully encoded file gets its selected name.

**License note:** FFmpeg builds differ in LGPL/GPL licensing based on
configuration. Review the build's licenses and attribution before shipping
FFmpeg to others. The application repo does not redistribute it.


### Replacing the original MP4
In Edit mode, select **Replace original MP4...** (available only for MP4
sources) and confirm the warning. Prism first finishes the entire encoding
job into a temporary file. After libmpv releases the source file, Windows
\`ReplaceFileW\` replaces it with the edited MP4. A timestamped backup
named \`<title>-prism-backup-<timestamp>-<id>.mp4\` is kept only when
**Tools → Settings → Keep backup when replacing original** is enabled
(default OFF).

- **Export edited copy remains the default and safest choice.** Prism never
  silently overwrites media, and existing copy output names are rejected.
- The new MP4 keeps the first audio stream; **other audio streams and
  subtitles are not preserved**. When enabled, the backup preserves the
  complete original file.
- If the original changes while encoding or Windows refuses the file
  replacement, Prism attempts to save the completed video as a new
  \`-trimmed.mp4\` copy. Some Windows replace errors may partially
  affect the source or backup, so inspect both if replacement fails.
- If the fallback copy cannot be saved either, Prism reports where the
  encoded temporary file remains rather than deleting successful work.
- Test Replace Original on disposable MP4 files before using valuable
  videos. When backup is enabled, inspect the edited copy before deleting
  its backup. If backup is disabled, replacement may be irreversible.

## Trim playback, encoder presets and performance

- Edit mode has **Play range / Pause** and **0.25x–2x speed** controls.
  Editing speed adjusts mpv playback and export video/audio timestamps
  (FFmpeg `setpts` / `atempo`) together. Normal speed is restored
  on leaving Edit mode. New editing sessions default to 1x.
- Encoding presets in the editing sidebar: Ultrafast, Very Fast, Fast,
  Medium, Slow. Default is **Very Fast** and persists across restarts.
  These presets affect encoding speed and compression efficiency, not
  playback speed. CRF remains 18.
- Tools → Settings → **Keep backup when replacing original** is OFF by
  default and persists in settings.json. ON retains a timestamped backup.
  OFF requests a Windows replacement without backup; some file-system
  errors may be unrecoverable. Always validate using disposable files.
- Thumbnail extraction uses two bounded concurrent FFmpeg jobs and reuses
  frames when reopening an unchanged file within the same Prism session.
- Sub-10-second clips show fractional timestamps in the normal seek bar
  and fullscreen overlay, improving sub-second trim review.

**Acceptance testing:** Validate 0.25x, 0.5x, 1x, 2x exported durations
and audio sync; test each encoding preset, the backup toggle ON/OFF,
cancel and failed replacement, thumbnail reuse and all six themes.

## Trim audio toggle and animated GIF export

- In Edit → Trim timeline, **Sound on** retains the first source audio
  track in an exported MP4. Clicking it changes the control to **Muted**,
  mutes the preview and produces an MP4 with **no audio stream** when
  using either Export edited copy or Replace original MP4. Default is
  Sound on for each new editing session. Prism restores the original
  playback mute state when leaving Edit mode or replacing a video.
- The new **Export animated GIF...** action uses the selected IN/OUT
  range and editing playback speed. GIFs are inherently silent.
  Export creates a new .gif copy only; it never replaces the MP4.
- GIF export uses FFmpeg's palettegen/paletteuse filters for better color
  reproduction, 12 fps, up to 640 pixels wide without upscaling,
  and an infinite animation loop. It may still be larger than MP4;
  short clips generally work best. Encoding presets apply only to MP4.
- GIFs and muted MP4s use the same background export progress and
  cancellation as ordinary MP4 exports. No existing file is overwritten.
- Test sound toggle in preview and both MP4 export modes; verify the
  muted file has no audio stream. Also test GIF speed, loop behavior,
  output size, cancellation, and reopening normal audio playback.
