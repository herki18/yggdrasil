[CmdletBinding()]
param(
    [string]$ProjectPath = "",
    [string]$UnityExe = $env:UNITY_EDITOR,
    [string]$LogFile = "",
    [string]$TestResults = "",
    [switch]$SkipWarmup
)

$ErrorActionPreference = "Stop"

function Resolve-UnityEditorPath {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath) -and (Test-Path $RequestedPath)) {
        return (Resolve-Path $RequestedPath).Path
    }

    $unityCommand = Get-Command unity -ErrorAction SilentlyContinue
    if ($unityCommand) {
        return $unityCommand.Source
    }

    $roots = @(
        "C:\\Program Files\\Unity\\Hub\\Editor",
        "$env:ProgramFiles\\Unity\\Hub\\Editor",
        "$env:ProgramFiles\\Unity\\Editor"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) }

    foreach ($root in $roots) {
        $candidate = Get-ChildItem -Path $root -Recurse -Filter "Unity.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    return $null
}

function Write-LogTail {
    param(
        [string]$Path,
        [int]$Lines = 120
    )

    if (-not (Test-Path $Path)) {
        Write-Warning "Unity log file not found: $Path"
        return
    }

    Write-Host "----- Unity log tail ($Lines lines) -----"
    Get-Content -Path $Path -Tail $Lines | ForEach-Object { Write-Host $_ }
    Write-Host "----- End Unity log tail -----"
}

function Invoke-UnityBatch {
    param(
        [string]$UnityPath,
        [string[]]$Arguments,
        [string]$Purpose
    )

    $process = Start-Process `
        -FilePath $UnityPath `
        -ArgumentList $Arguments `
        -NoNewWindow `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Unity exited with code $($process.ExitCode) during $Purpose."
    }
}

function Assert-NativeRuntimeBuildPinned {
    param([string]$RootPath)

    $buildInfoPath = Join-Path $RootPath "repos\\scripting-engine-unity\\Runtime\\NativeRuntimeBuildInfo.g.cs"
    if (-not (Test-Path $buildInfoPath)) {
        throw "Missing runtime build info file: $buildInfoPath"
    }

    $buildInfo = Get-Content -Path $buildInfoPath -Raw
    if ($buildInfo -match 'ExpectedBuildId\s*=\s*"UNSET"') {
        throw "Native runtime build ID is UNSET. Run .\\scripts\\build-scripting-engine-ffi.ps1 before validation."
    }
}

function Assert-CanonicalRuntimeLayout {
    param([string]$RootPath)

    $layoutScriptPath = Join-Path $RootPath "scripts\\check-scripting-engine-runtime-layout.ps1"
    if (-not (Test-Path $layoutScriptPath)) {
        throw "Missing runtime layout checker: $layoutScriptPath"
    }

    & $layoutScriptPath -VerifyExports
}

$scriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
elseif (-not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
    Split-Path -Path $MyInvocation.MyCommand.Path -Parent
}
else {
    (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Join-Path $scriptRoot "..\\repos\\sunderia"
}

$rootPath = (Resolve-Path (Join-Path $scriptRoot "..")).Path
Assert-NativeRuntimeBuildPinned -RootPath $rootPath
Assert-CanonicalRuntimeLayout -RootPath $rootPath

$resolvedProjectPath = (Resolve-Path $ProjectPath).Path
$resolvedUnityExe = Resolve-UnityEditorPath -RequestedPath $UnityExe

if ([string]::IsNullOrWhiteSpace($resolvedUnityExe) -or -not (Test-Path $resolvedUnityExe)) {
    throw "Unable to locate Unity editor. Set UNITY_EDITOR or pass -UnityExe."
}

if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $LogFile = Join-Path $env:TEMP "sunderia-world-script-validation.log"
}
if ([string]::IsNullOrWhiteSpace($TestResults)) {
    $TestResults = Join-Path $env:TEMP "sunderia-world-script-validation-results.xml"
}

Write-Host "Unity editor: $resolvedUnityExe"
Write-Host "Project path: $resolvedProjectPath"
Write-Host "Log file: $LogFile"
Write-Host "Test results: $TestResults"

if (Test-Path $TestResults) {
    Remove-Item -Path $TestResults -Force
}

$warmupLogFile = [System.IO.Path]::ChangeExtension($LogFile, ".warmup.log")
if (-not $SkipWarmup) {
    Write-Host "Warmup pass: importing/compiling project before test run..."
    $warmupArgs = @(
        "-batchmode"
        "-nographics"
        "-quit"
        "-projectPath", $resolvedProjectPath
        "-logFile", $warmupLogFile
    )

    try {
        Invoke-UnityBatch -UnityPath $resolvedUnityExe -Arguments $warmupArgs -Purpose "warmup pass"
    }
    catch {
        Write-LogTail -Path $warmupLogFile
        throw
    }
}

$unityArgs = @(
    "-batchmode"
    "-nographics"
    "-projectPath", $resolvedProjectPath
    "-runTests"
    "-testPlatform", "EditMode"
    "-assemblyNames", "Sunderia.World.Tests.EditMode"
    "-testResults", $TestResults
    "-logFile", $LogFile
)

try {
    Invoke-UnityBatch -UnityPath $resolvedUnityExe -Arguments $unityArgs -Purpose "test run"
}
catch {
    Write-LogTail -Path $LogFile
    throw
}

if (-not (Test-Path $TestResults)) {
    Write-LogTail -Path $LogFile
    if (Test-Path $LogFile) {
        $logText = Get-Content -Path $LogFile -Raw
        if ($logText -match "No tests to run|No tests were found|Test run cancelled|Compilation failed") {
            throw "Unity did not produce test results because tests did not execute. See $LogFile."
        }
    }
    throw "Unity exited successfully but did not produce test results: $TestResults. See $LogFile and $warmupLogFile."
}

[xml]$resultsXml = Get-Content -Path $TestResults -Raw
$failures = $resultsXml.SelectNodes("//test-case[@result='Failed']")
if ($failures -and $failures.Count -gt 0) {
    Write-LogTail -Path $LogFile
    throw "Script dialect validation failed with $($failures.Count) failing test(s). See $TestResults and $LogFile."
}

Write-Host "Sunderia world script validation passed."
