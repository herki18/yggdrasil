param(
    [ValidateSet("Debug", "Release", "All")]
    [string]$Configuration = "All",
    [string]$RustRepoPath = $env:WEB_ENGINE_RUST_PATH
)

$ErrorActionPreference = "Stop"

function Resolve-RootPath {
    return (Resolve-Path (Join-Path $PSScriptRoot ".." "..")).Path
}

function Resolve-RustRepoPath([string]$root) {
    if (-not [string]::IsNullOrWhiteSpace($RustRepoPath)) {
        return (Resolve-Path $RustRepoPath).Path
    }

    $candidate = Join-Path $root "repos" "web-engine-rust"
    if (Test-Path $candidate) {
        return (Resolve-Path $candidate).Path
    }

    throw "Could not locate web-engine-rust. Set WEB_ENGINE_RUST_PATH to the repo location."
}

function Resolve-PackagePath([string]$root) {
    $candidate = Join-Path $root "repos" "web-engine-unity"
    if (Test-Path $candidate) {
        return (Resolve-Path $candidate).Path
    }

    throw "Could not locate web-engine-unity package."
}

function Build-One([string]$profile, [string]$rustRepo, [string]$packagePath) {
    $args = @("build", "-p", "webr-engine-ffi")
    $targetDir = "debug"
    if ($profile -eq "Release") {
        $args += "--release"
        $targetDir = "release"
    }

    Push-Location $rustRepo
    try {
        & cargo @args
    } finally {
        Pop-Location
    }

    $src = Join-Path $rustRepo "target" $targetDir "webr_engine.dll"
    if (-not (Test-Path $src)) {
        throw "Expected build output not found: $src"
    }

    $destBase = Join-Path $packagePath "Runtime" "Plugins" "Windows" "x86_64"
    $destDir = if ($profile -eq "Release") { $destBase } else { Join-Path $destBase "Debug" }
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    Copy-Item $src (Join-Path $destDir "webr_engine.dll") -Force
    Write-Host "Copied $profile build to $destDir"
}

$root = Resolve-RootPath
$rustRepo = Resolve-RustRepoPath $root
$packagePath = Resolve-PackagePath $root

switch ($Configuration) {
    "Debug" { Build-One "Debug" $rustRepo $packagePath }
    "Release" { Build-One "Release" $rustRepo $packagePath }
    "All" {
        Build-One "Debug" $rustRepo $packagePath
        Build-One "Release" $rustRepo $packagePath
    }
}
