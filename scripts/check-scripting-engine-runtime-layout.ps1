[CmdletBinding()]
param(
    [switch]$VerifyExports
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Assert-CanonicalPluginSet {
    param(
        [string]$PluginsRoot,
        [string]$CanonicalWindows,
        [string]$CanonicalLinux
    )

    $runtimeBinaries = Get-ChildItem -Path $PluginsRoot -Recurse -File | Where-Object {
        $_.Name -eq 'se_ffi.dll' -or $_.Name -eq 'libse_ffi.so'
    }

    if (-not $runtimeBinaries -or $runtimeBinaries.Count -eq 0) {
        throw "No scripting runtime binaries found under $PluginsRoot"
    }

    $canonicalWindowsFull = [System.IO.Path]::GetFullPath($CanonicalWindows)
    $canonicalLinuxFull = [System.IO.Path]::GetFullPath($CanonicalLinux)
    $allowed = @($canonicalWindowsFull, $canonicalLinuxFull)

    $fullPaths = $runtimeBinaries | ForEach-Object { [System.IO.Path]::GetFullPath($_.FullName) }

    $extras = $fullPaths | Where-Object { $allowed -notcontains $_ }
    if ($extras.Count -gt 0) {
        $extraList = ($extras | Sort-Object | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
        throw "Found legacy/non-canonical scripting runtime binaries:`n$extraList"
    }

    if (-not (Test-Path $canonicalWindowsFull)) {
        throw "Missing canonical Windows runtime binary: $canonicalWindowsFull"
    }

    if (-not (Test-Path $canonicalLinuxFull)) {
        throw "Missing canonical Linux runtime binary: $canonicalLinuxFull"
    }

    $windowsMatches = $fullPaths | Where-Object { $_ -eq $canonicalWindowsFull }
    if ($windowsMatches.Count -ne 1) {
        throw "Expected exactly one canonical Windows runtime binary, found $($windowsMatches.Count): $canonicalWindowsFull"
    }

    $linuxMatches = $fullPaths | Where-Object { $_ -eq $canonicalLinuxFull }
    if ($linuxMatches.Count -ne 1) {
        throw "Expected exactly one canonical Linux runtime binary, found $($linuxMatches.Count): $canonicalLinuxFull"
    }
}

function Assert-WindowsExports {
    param([string]$WindowsDll)

    if (-not (Test-Path $WindowsDll)) {
        throw "Missing Windows runtime binary: $WindowsDll"
    }

    if (-not ('SeNativeWindowsLoader' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class SeNativeWindowsLoader
{
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("kernel32", SetLastError = true)]
    public static extern bool FreeLibrary(IntPtr hModule);

    [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)]
    public static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);
}
"@
    }

    $requiredSymbols = @(
        'se_api_version',
        'se_get_capabilities',
        'se_runtime_family',
        'se_runtime_build_id'
    )

    $module = [SeNativeWindowsLoader]::LoadLibrary($WindowsDll)
    if ($module -eq [IntPtr]::Zero) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Failed to load $WindowsDll for export verification (Win32=$errorCode)"
    }

    try {
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($symbol in $requiredSymbols) {
            if ([SeNativeWindowsLoader]::GetProcAddress($module, $symbol) -eq [IntPtr]::Zero) {
                $missing.Add($symbol)
            }
        }

        if ($missing.Count -gt 0) {
            $missingList = ($missing | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
            throw "Missing required exports in ${WindowsDll}:`n$missingList"
        }
    }
    finally {
        [SeNativeWindowsLoader]::FreeLibrary($module) | Out-Null
    }
}

$root = Get-RepoRoot
$unityPkg = Join-Path $root 'repos/scripting-engine-unity'
$pluginsRoot = Join-Path $unityPkg 'Runtime/Plugins'
$canonicalWindows = Join-Path $pluginsRoot 'Windows/x86_64/se_ffi.dll'
$canonicalLinux = Join-Path $pluginsRoot 'Linux/x86_64/libse_ffi.so'

if (-not (Test-Path $pluginsRoot)) {
    throw "Missing plugins root: $pluginsRoot"
}

Assert-CanonicalPluginSet -PluginsRoot $pluginsRoot -CanonicalWindows $canonicalWindows -CanonicalLinux $canonicalLinux

if ($VerifyExports) {
    Assert-WindowsExports -WindowsDll ([System.IO.Path]::GetFullPath($canonicalWindows))
}

Write-Host "Scripting runtime layout OK"
Write-Host "  windows: $([System.IO.Path]::GetFullPath($canonicalWindows))"
Write-Host "  linux:   $([System.IO.Path]::GetFullPath($canonicalLinux))"
if ($VerifyExports) {
    Write-Host "  required exports: verified"
}
