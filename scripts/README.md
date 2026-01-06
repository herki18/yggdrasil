# Yggdrasil scripts

## build-ffi.sh
Builds the Rust FFI libraries and copies the outputs into the Unity packages.

Usage:
```bash
./scripts/build-ffi.sh --profile release
./scripts/build-ffi.sh --targets x86_64-pc-windows-msvc,x86_64-unknown-linux-gnu
```

Notes:
- Uses the `se-ffi` crate from `repos/scripting-engine-rust`.
- Uses the `webr-engine-ffi` crate from `repos/web-engine-rust`.
- Outputs are copied to:
  - `repos/scripting-engine-unity/Runtime/Plugins/<Platform>/<Arch>/`
  - `repos/web-engine-unity/Runtime/Plugins/<Platform>/<Arch>/`
- For cross-compilation, you must install the appropriate Rust target and toolchain.

Output layout (platform-specific):
- Windows x86_64:
  - `Runtime/Plugins/Windows/x86_64/se_ffi.dll`
  - `Runtime/Plugins/Windows/x86_64/webr_engine.dll`
- Linux x86_64:
  - `Runtime/Plugins/Linux/x86_64/libse_ffi.so`
  - `Runtime/Plugins/Linux/x86_64/libwebr_engine.so`
- macOS arm64:
  - `Runtime/Plugins/macOS/arm64/libse_ffi.dylib`
  - `Runtime/Plugins/macOS/arm64/libwebr_engine.dylib`

## build-ffi.ps1 (Windows)
PowerShell wrapper for Windows builds.

Usage:
```powershell
.\scripts\build-ffi.ps1 -Profile release
.\scripts\build-ffi.ps1 -Targets x86_64-pc-windows-msvc,x86_64-unknown-linux-gnu
```

Shortcut:
```cmd
scripts\build-ffi.cmd --profile release
```

## build-ffi-all.sh (WSL-friendly)
Runs Linux and/or Windows builds from WSL.

Usage:
```bash
./scripts/build-ffi-all.sh --profile release
./scripts/build-ffi-all.sh --linux
./scripts/build-ffi-all.sh --windows
```

Notes:
- Windows build uses `powershell.exe` and requires WSL interop.
- If `powershell.exe` is not available, run `scripts/build-ffi.ps1` directly on Windows.
