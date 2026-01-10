param(
  [ValidateSet('debug','release','all')]
  [string]$Profile = 'debug',
  [string]$Target,
  [string]$Targets
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-HostTriple {
  $hostLine = (& rustc -vV | Select-String '^host:').Line
  if (-not $hostLine) { throw 'Failed to detect host triple from rustc' }
  return $hostLine -replace '^host:\s*',''
}

function Get-Platform($triple) {
  if ($triple -match 'windows') { return 'Windows' }
  if ($triple -match 'linux') { return 'Linux' }
  if ($triple -match 'apple-darwin') { return 'macOS' }
  return $null
}

function Get-Arch($triple) {
  $arch = $triple.Split('-')[0]
  switch ($arch) {
    'x86_64' { return 'x86_64' }
    'aarch64' { return 'arm64' }
    'arm64' { return 'arm64' }
    default { return $arch }
  }
}

function Get-Ext($triple) {
  if ($triple -match 'windows') { return 'dll' }
  if ($triple -match 'linux') { return 'so' }
  if ($triple -match 'apple-darwin') { return 'dylib' }
  return $null
}

function Get-Prefix($triple) {
  if ($triple -match 'windows') { return '' }
  if ($triple -match 'linux|apple-darwin') { return 'lib' }
  return ''
}

$root = Get-RepoRoot
$seDir = Join-Path $root 'repos/scripting-engine-rust'
$weDir = Join-Path $root 'repos/web-engine-rust'
$sePkg = Join-Path $root 'repos/scripting-engine-unity'
$wePkg = Join-Path $root 'repos/web-engine-unity'

$targetList = @()
if ($Target) { $targetList += $Target }
if ($Targets) { $targetList += $Targets.Split(',') }
if ($targetList.Count -eq 0) { $targetList = @(Get-HostTriple) }

$profiles = @()
if ($Profile -eq 'all') {
  $profiles = @('debug','release')
} else {
  $profiles = @($Profile)
}

foreach ($p in $profiles) {
  $cargoProfileArgs = @()
  $profileDir = $p
  if ($p -eq 'release') { $cargoProfileArgs += '--release' }

  foreach ($t in $targetList) {
    $platform = Get-Platform $t
    $arch = Get-Arch $t
    $ext = Get-Ext $t
    $prefix = Get-Prefix $t

    if (-not $platform -or -not $ext) { throw "Unsupported target: $t" }

    Write-Host "== Building for $t ($platform/$arch) [$p] =="

    Push-Location $seDir
    & cargo build -p se-ffi --target $t @cargoProfileArgs
    Pop-Location

    Push-Location $weDir
    & cargo build -p webr-engine-ffi --target $t @cargoProfileArgs
    Pop-Location

    $seOut = Join-Path $seDir "target/$t/$profileDir/${prefix}se_ffi.$ext"
    $weOut = Join-Path $weDir "target/$t/$profileDir/${prefix}webr_engine.$ext"

    if (-not (Test-Path $seOut)) { throw "Missing output: $seOut" }
    if (-not (Test-Path $weOut)) { throw "Missing output: $weOut" }

    $seBase = Join-Path $sePkg "Runtime/Plugins/$platform/$arch"
    $weBase = Join-Path $wePkg "Runtime/Plugins/$platform/$arch"
    $seDest = if ($p -eq 'release') { $seBase } else { Join-Path $seBase 'Debug' }
    $weDest = if ($p -eq 'release') { $weBase } else { Join-Path $weBase 'Debug' }

    New-Item -ItemType Directory -Force -Path $seDest | Out-Null
    New-Item -ItemType Directory -Force -Path $weDest | Out-Null

    Copy-Item $seOut -Destination $seDest -Force
    Copy-Item $weOut -Destination $weDest -Force

    Write-Host "  -> $seDest\$(Split-Path $seOut -Leaf)"
    Write-Host "  -> $weDest\$(Split-Path $weOut -Leaf)"
    Write-Host ""
  }
}

Write-Host "Done."
