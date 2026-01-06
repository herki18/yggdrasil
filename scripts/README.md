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
