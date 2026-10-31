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
