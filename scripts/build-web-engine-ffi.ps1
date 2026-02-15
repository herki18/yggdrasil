param(
  [ValidateSet('debug','release')]
  [string]$Profile = 'release',
  [string]$Target,
  [switch]$StopLockingProcesses
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-CargoTargetDirectory([string]$repoPath) {
  Push-Location $repoPath
  try {
    $metadataJson = & cargo metadata --format-version 1 --no-deps
    if ($LASTEXITCODE -ne 0) { throw "cargo metadata failed for $repoPath" }
  } finally {
    Pop-Location
  }

  if ([string]::IsNullOrWhiteSpace($metadataJson)) {
    throw "cargo metadata returned no output for $repoPath"
  }

  $metadata = $metadataJson | ConvertFrom-Json
  if ([string]::IsNullOrWhiteSpace($metadata.target_directory)) {
    throw "cargo metadata did not provide target_directory for $repoPath"
  }

  try { return [System.IO.Path]::GetFullPath($metadata.target_directory) }
  catch { return $metadata.target_directory }
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
  throw "Unsupported target: $triple"
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
  throw "Unsupported target: $triple"
}

function Get-Prefix($triple) {
  if ($triple -match 'windows') { return '' }
  return 'lib'
}

function Get-LockingProcesses([string]$path) {
  $normalizedPath = [System.IO.Path]::GetFullPath($path)
  $results = New-Object System.Collections.Generic.List[System.Diagnostics.Process]

  foreach ($proc in Get-Process -ErrorAction SilentlyContinue) {
    try {
      foreach ($module in $proc.Modules) {
        if ([string]::Equals(
            [System.IO.Path]::GetFullPath($module.FileName),
            $normalizedPath,
            [System.StringComparison]::OrdinalIgnoreCase)) {
          $results.Add($proc)
          break
        }
      }
    }
    catch {
      # ignore access denied
    }
  }

  return $results | Sort-Object -Property Id -Unique
}

function Format-ProcessList($processes) {
  if (-not $processes -or $processes.Count -eq 0) {
    return "<unknown>"
  }

  return ($processes | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ", "
}

function Copy-WithRetry(
  [string]$source,
  [string]$destination,
  [int]$attempts = 20,
  [int]$delayMs = 500,
  [switch]$StopLockers
) {
  for ($i = 1; $i -le $attempts; $i++) {
    try {
      Copy-Item $source -Destination $destination -Force
      return
    }
    catch {
      $lockers = Get-LockingProcesses $destination
      if ($StopLockers -and $lockers -and $lockers.Count -gt 0) {
        Write-Warning ("Destination locked by: {0}. Stopping locker processes." -f (Format-ProcessList $lockers))
        foreach ($locker in $lockers) {
          try {
            Stop-Process -Id $locker.Id -Force -ErrorAction Stop
          }
          catch {
            Write-Warning ("Failed to stop process {0}({1}): {2}" -f $locker.ProcessName, $locker.Id, $_.Exception.Message)
          }
        }
        Start-Sleep -Milliseconds $delayMs
        continue
      }

      if ($i -eq $attempts) {
        $lockerText = Format-ProcessList $lockers
        $actionHint = if ($StopLockers) {
          "Could not terminate all locking processes automatically."
        } else {
          "Rerun with -StopLockingProcesses to auto-terminate lockers, or close them manually."
        }
        throw "Failed to copy '$source' to '$destination' after $attempts attempts. Lockers: $lockerText. $actionHint $($_.Exception.Message)"
      }

      Start-Sleep -Milliseconds $delayMs
    }
  }
}

function Remove-LegacyRuntimeArtifacts([string]$unityPackagePath) {
  $pluginsRoot = Join-Path $unityPackagePath 'Runtime/Plugins'
  if (-not (Test-Path $pluginsRoot)) {
    return
  }

  $canonicalWindows = [System.IO.Path]::GetFullPath((Join-Path $pluginsRoot 'Windows/x86_64/webr_engine.dll'))
  $canonicalLinux = [System.IO.Path]::GetFullPath((Join-Path $pluginsRoot 'Linux/x86_64/libwebr_engine.so'))
  $canonicalMac = [System.IO.Path]::GetFullPath((Join-Path $pluginsRoot 'macOS/libwebr_engine.dylib'))

  $legacyPaths = @(
    (Join-Path $pluginsRoot 'Windows/x86_64/Debug'),
    (Join-Path $pluginsRoot 'Windows/x86_64/Debug.meta'),
    (Join-Path $pluginsRoot 'Linux/x86_64/Debug'),
    (Join-Path $pluginsRoot 'Linux/x86_64/Debug.meta'),
    (Join-Path $pluginsRoot 'macOS/Debug'),
    (Join-Path $pluginsRoot 'macOS/Debug.meta')
  )

  foreach ($legacyPath in $legacyPaths) {
    if (Test-Path $legacyPath) {
      Write-Warning "Removing legacy path: $legacyPath"
      Remove-Item -Path $legacyPath -Recurse -Force
    }
  }

  $runtimeFiles = Get-ChildItem -Path $pluginsRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -eq 'webr_engine.dll' -or $_.Name -eq 'libwebr_engine.so' -or $_.Name -eq 'libwebr_engine.dylib'
  }

  foreach ($runtimeFile in $runtimeFiles) {
    $fullPath = [System.IO.Path]::GetFullPath($runtimeFile.FullName)
    if ($fullPath -ne $canonicalWindows -and $fullPath -ne $canonicalLinux -and $fullPath -ne $canonicalMac) {
      Write-Warning "Removing legacy runtime binary: $fullPath"
      Remove-Item -Path $runtimeFile.FullName -Force
      $sidecarMeta = "$($runtimeFile.FullName).meta"
      if (Test-Path $sidecarMeta) {
        Remove-Item -Path $sidecarMeta -Force
      }
    }
  }
}

$root = Get-RepoRoot
$rustRepo = Join-Path $root 'repos/web-engine-rust'
$unityPkg = Join-Path $root 'repos/web-engine-unity'

if (-not (Test-Path $rustRepo)) { throw "Missing repo: $rustRepo" }
if (-not (Test-Path $unityPkg)) { throw "Missing repo: $unityPkg" }

if ([string]::IsNullOrWhiteSpace($Target)) {
  $Target = Get-HostTriple
}

$targetDir = Get-CargoTargetDirectory $rustRepo
$platform = Get-Platform $Target
$arch = Get-Arch $Target
$ext = Get-Ext $Target
$prefix = Get-Prefix $Target
$profileDir = $Profile

$cargoArgs = @('build','-p','webr-engine-ffi','--target',$Target)
if ($Profile -eq 'release') { $cargoArgs += '--release' }

Push-Location $rustRepo
try {
  & cargo @cargoArgs
  if ($LASTEXITCODE -ne 0) { throw 'cargo build failed' }
}
finally {
  Pop-Location
}

$outPath = Join-Path $targetDir "$Target/$profileDir/${prefix}webr_engine.$ext"
if (-not (Test-Path $outPath)) {
  throw "Missing output: $outPath"
}

Remove-LegacyRuntimeArtifacts -unityPackagePath $unityPkg

$destDir = Join-Path $unityPkg "Runtime/Plugins/$platform/$arch"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$destPath = Join-Path $destDir (Split-Path $outPath -Leaf)
Copy-WithRetry $outPath $destPath -StopLockers:$StopLockingProcesses

$runtimeLayoutScript = Join-Path $root 'scripts/check-web-engine-runtime-layout.ps1'
if (-not (Test-Path $runtimeLayoutScript)) {
  throw "Missing runtime layout checker: $runtimeLayoutScript"
}

& $runtimeLayoutScript -VerifyExports

Write-Host "Built web engine FFI"
Write-Host "  target: $Target"
Write-Host "  profile: $Profile"
Write-Host "  source: $outPath"
Write-Host "  destination: $destPath"
Write-Host "  stop locking processes: $StopLockingProcesses"
