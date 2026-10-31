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

## Trim editor UI and GIF startup improvements

- Play range / Pause now uses a fixed-size QML pause symbol (two aligned
  rectangles), avoiding the inconsistent spacing of the old Unicode glyph.
- GIF export no longer needs to analyze the entire selection before the
  first output frames can be processed. Prism builds a stable GIF palette
  from up to the first **2 seconds of the speed-adjusted output** instead.
  It keeps the existing 12 fps / 640 px / looping GIF options.
  This improves startup on longer selections, but if later scenes have
  substantially different colors the GIF's color fidelity may be lower
  than a full-clip palette.
- Verify pause-button alignment in different themes, and compare GIF
  startup time, color, speed-adjusted duration, and file size against
  previous builds with short and long clips.

## Sequential background export queue

- MP4 **Export edited copy** and **Export animated GIF** add a job to a
  session-only queue. One FFmpeg process runs at a time; subsequent jobs
  start automatically in creation order. The Edit timeline remains
  interactive during those exports. Changes made after queuing a job do
  not affect it: trim range, speed, audio mute, MP4 encoding preset and
  GIF quality preset are captured when the job is submitted.
- The editing sidebar displays the queue. **Exports** in the top bar
  opens a queue popup even outside Edit mode. Cancel individual waiting
  or running jobs, and clear completed/canceled/failed entries.
- Each queued output name is reserved; a second job cannot overwrite
  an existing or reserved file. If the source changes or disappears
  before a job begins, that job fails safely and the queue continues.
- **Replace original MP4** remains exclusive. It is disabled until all
  copy/GIF exports complete or are canceled and never enters the
  background queue.
- Closing Prism with active/waiting jobs displays a warning. The queue
  is *in-memory only*, not resumed after an app restart. FFmpeg processes
  will stop when Prism exits.

## GIF quality presets

- High Quality: up to 640px wide, 12 fps, 256-color palette.
- Balanced (default): up to 480px wide, 10 fps, 128 colors.
- Compact: up to 360px wide, 8 fps, 96 colors.

GIF presets are independent of MP4 encoding presets. The choice persists
in settings.json. All GIFs are silent, loop indefinitely, and use the
selected trim range and playback speed. Quality/size tradeoffs depend on
content; fine detail and motion may be reduced on Balanced/Compact.

### Acceptance tests

1. Queue an MP4 and then two GIFs while the first runs. Continue
   scrubbing/changing ranges and confirm every output matches the
   settings captured when that job was queued; only one runs at a time.
2. Cancel a waiting job and the active job, then verify the next runs.
   Try duplicate output names and missing/deleted source files.
3. Reopen Edit or switch to normal playback while exports continue,
   and use the top-bar Exports popup to monitor jobs.
4. Verify Replace original is blocked whenever copy/GIF jobs remain.
   Test replacement on disposable clips after the queue clears.
5. Compare High/Balanced/Compact output file sizes, colors and
   animation smoothness on the same clip; restart to confirm
   preset persistence.
6. Try closing Prism during an active export and verify the warning.

## One-click export queue workflow

- **Add MP4 to export queue** and **Add GIF to export queue** immediately
  submit the selected trim without opening a Windows Save As dialog.
  The trim timeline's quick export button now queues an MP4 the same way.
- Prism automatically chooses the source video's folder and a unique
  `<source>-trimmed.mp4` or `<source>-trimmed.gif` filename; if the name
  already exists or is reserved by the queue, it adds `-2`, `-3`, etc.
- For a custom filename or directory, use **Choose output location...**
  and select **Save MP4 as...** or **Save GIF as...**. These are optional
  and still enqueue after confirming the destination.
- Replace Original continues to use its exclusive confirmation dialog.
- Verify direct queue on repeated clicks, auto-incremented filenames,
  no Save As window on primary actions, optional Save As operations,
  job snapshots, and normal queued progress.
