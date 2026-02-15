param(
    [ValidateSet("Debug", "Release", "All")]
    [string]$Configuration = "All",
    [string]$Target = "x86_64-pc-windows-msvc"
)

$ErrorActionPreference = "Stop"

function Resolve-RootPath {
    return (Resolve-Path (Join-Path $PSScriptRoot ".." "..")).Path
}

$root = Resolve-RootPath
$explicitScript = Join-Path $root "scripts" "build-scripting-engine-ffi.ps1"
if (-not (Test-Path $explicitScript)) {
    throw "Missing script: $explicitScript"
}

switch ($Configuration) {
    "Debug" {
        & $explicitScript -Profile debug -Target $Target
    }
    "Release" {
        & $explicitScript -Profile release -Target $Target
    }
    "All" {
        & $explicitScript -Profile debug -Target $Target
        & $explicitScript -Profile release -Target $Target
    }
}
