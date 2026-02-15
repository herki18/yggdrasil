# Yggdrasil Scripts

## FFI Build Scripts (Clean Break)

The old `build-ffi.*` entrypoints are removed because they mixed engines and copied to ambiguous paths.

Use explicit scripts:

### `build-scripting-engine-ffi.ps1` / `build-scripting-engine-ffi.sh`
Builds `se-ffi` from `repos/scripting-engine-rust` and copies to canonical plugin paths:
- `repos/scripting-engine-unity/Runtime/Plugins/Windows/x86_64/se_ffi.dll`
- `repos/scripting-engine-unity/Runtime/Plugins/Linux/x86_64/libse_ffi.so`

Before copy, the script removes legacy runtime artifacts (for example `Runtime/Plugins/Windows/x86_64/Debug/se_ffi.dll`).

After copy, it regenerates:
- `repos/scripting-engine-unity/Runtime/NativeRuntimeBuildInfo.g.cs`

Then it enforces the single-runtime invariant via `check-scripting-engine-runtime-layout`.

Examples:
```powershell
.\scripts\build-scripting-engine-ffi.ps1 -Profile release
.\scripts\build-scripting-engine-ffi.ps1 -Profile debug -Target x86_64-pc-windows-msvc
.\scripts\build-scripting-engine-ffi.ps1 -Profile release -Target x86_64-pc-windows-msvc -StopLockingProcesses
```

```bash
./scripts/build-scripting-engine-ffi.sh --profile release
./scripts/build-scripting-engine-ffi.sh --profile debug --target x86_64-unknown-linux-gnu
```

### `build-web-engine-ffi.ps1` / `build-web-engine-ffi.sh`
Builds `webr-engine-ffi` from `repos/web-engine-rust` and copies to canonical plugin paths:
- `repos/web-engine-unity/Runtime/Plugins/Windows/x86_64/webr_engine.dll`
- `repos/web-engine-unity/Runtime/Plugins/Linux/x86_64/libwebr_engine.so`

Before copy, the script removes legacy runtime artifacts (for example `Runtime/Plugins/Windows/x86_64/Debug/webr_engine.dll`).

After copy, it enforces the single-runtime invariant via `check-web-engine-runtime-layout`.

Examples:
```powershell
.\scripts\build-web-engine-ffi.ps1 -Profile release
```

```bash
./scripts/build-web-engine-ffi.sh --profile release
```

## Runtime Layout Guard

### `check-scripting-engine-runtime-layout.ps1` / `check-scripting-engine-runtime-layout.sh`
Validates runtime plugin layout and fails if any non-canonical `se_ffi` binaries exist.

Single-runtime invariant:
- Exactly one canonical Windows runtime binary.
- Exactly one canonical Linux runtime binary.
- No duplicate or legacy runtime binaries anywhere under `Runtime/Plugins`.

With export verification enabled, required runtime identity exports are checked:
- `se_api_version`
- `se_get_capabilities`
- `se_runtime_family`
- `se_runtime_build_id`

Examples:
```powershell
.\scripts\check-scripting-engine-runtime-layout.ps1
.\scripts\check-scripting-engine-runtime-layout.ps1 -VerifyExports
```

```bash
./scripts/check-scripting-engine-runtime-layout.sh
./scripts/check-scripting-engine-runtime-layout.sh --verify-exports
```

### `check-web-engine-runtime-layout.ps1` / `check-web-engine-runtime-layout.sh`
Validates runtime plugin layout and fails if any non-canonical `webr_engine` binaries exist.

Single-runtime invariant:
- Exactly one canonical Windows runtime binary.
- Exactly one canonical Linux runtime binary.
- Optional canonical macOS runtime binary when present.
- No duplicate or legacy runtime binaries anywhere under `Runtime/Plugins`.

With export verification enabled, all managed extern `webr_*` symbols from `Runtime/WebrNative.cs` are checked against native exports.

Examples:
```powershell
.\scripts\check-web-engine-runtime-layout.ps1
.\scripts\check-web-engine-runtime-layout.ps1 -VerifyExports
```

```bash
./scripts/check-web-engine-runtime-layout.sh
./scripts/check-web-engine-runtime-layout.sh --verify-exports
```

## `validate-sunderia-world-script.ps1` / `.sh`
Runs Unity EditMode tests in `Sunderia.World.Tests.EditMode.ScriptDialectValidationTests` for world script/runtime startup validation.

Validation now hard-fails before Unity launch when:
- `NativeRuntimeBuildInfo.g.cs` has `ExpectedBuildId = "UNSET"`.
- Runtime layout/export preflight fails.

Validation flow is deterministic:
1. Warmup Unity batch pass to import/compile scripts.
2. Test pass using `-assemblyNames Sunderia.World.Tests.EditMode` (without `-quit`, so Unity exits after test runner completes).

Examples:
```powershell
.\scripts\validate-sunderia-world-script.ps1
```

```bash
./scripts/validate-sunderia-world-script.sh
```

## Canonical Sunderia Startup Flow

1. Build/copy scripting runtime:
```powershell
.\scripts\build-scripting-engine-ffi.ps1 -Profile release -Target x86_64-pc-windows-msvc
```
2. Run validation:
```powershell
.\scripts\validate-sunderia-world-script.ps1
```
3. Start Unity and run scene.

## Legacy Wrappers

- `scripts/build-ffi.ps1`, `scripts/build-ffi.sh`, and `scripts/build-ffi.cmd` are intentionally removed wrappers and should not be used for real builds.
- `scripts/scripting-engine/build-native.ps1` is a thin forwarder to `scripts/build-scripting-engine-ffi.ps1`.
- `scripts/web-engine/build-native.ps1` and `scripts/web-engine/build-native.sh` are thin forwarders to `scripts/build-web-engine-ffi.*`.

## Troubleshooting

- `Native ABI mismatch ... required runtime identity exports are missing`:
  Runtime binary mismatch. Run `build-scripting-engine-ffi` and confirm `check-scripting-engine-runtime-layout` passes.
- `web engine fails to load or entry points missing`:
  Runtime binary mismatch. Run `build-web-engine-ffi` and confirm `check-web-engine-runtime-layout --verify-exports` passes.
- `Copy-Item ... se_ffi.dll ... being used by another process`:
  Close Unity/editor process, rerun build script, or use `-StopLockingProcesses`.
- `Missing test results file ...` during validation:
  Check Unity log passed by the script. Validation now surfaces common root causes (no tests found / compilation failed).
