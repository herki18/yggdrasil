# Yggdrasil

Superproject for coordinating multiple repositories (scripting engine, browser, game, and shared modules).

## Structure
- `repos/` (planned): submodules for each codebase
- `scripts/`: shared build and setup scripts

## Getting started
```bash
git clone --recurse-submodules git@github.com:herki18/yggdrasil.git
```

## Native plugin builds (Unity)

Build scripts live in the repo root under `scripts/`.

### Combined (both engines)
**Windows (PowerShell):**
```powershell
.\scripts\build-ffi.ps1 -Profile all
```

**Linux/macOS (bash):**
```bash
./scripts/build-ffi.sh --profile all
```

### Per-engine
**Scripting engine (Windows):**
```powershell
.\scripts\scripting-engine\build-native.ps1 -Configuration All
```

**Scripting engine (Linux/macOS):**
```bash
./scripts/scripting-engine/build-native.sh all
```

**Web engine (Windows):**
```powershell
.\scripts\web-engine\build-native.ps1 -Configuration All
```

**Web engine (Linux/macOS):**
```bash
./scripts/web-engine/build-native.sh all
```

Outputs:
- Release builds → `repos/<package>/Runtime/Plugins/<platform>/...`
- Debug builds → `repos/<package>/Runtime/Plugins/<platform>/Debug/...`

If you run scripts outside this superproject, set:
- `SCRIPTING_ENGINE_RUST_PATH` for the scripting engine Rust repo
- `WEB_ENGINE_RUST_PATH` for the web engine Rust repo
