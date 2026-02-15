[CmdletBinding()]
param(
    [switch]$VerifyExports
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-ManagedExternSymbols {
    param([string]$NativeBindingsPath)

    if (-not (Test-Path $NativeBindingsPath)) {
        throw "Missing Webr native bindings file: $NativeBindingsPath"
    }

    $content = Get-Content -Path $NativeBindingsPath -Raw
    $matches = [regex]::Matches($content, 'internal\s+static\s+extern\s+[^\(]+\s+(webr_[A-Za-z0-9_]+)\s*\(')
    $symbols = $matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

    if (-not $symbols -or $symbols.Count -eq 0) {
        throw "No managed extern symbols found in $NativeBindingsPath"
    }

    return $symbols
}

function Assert-CanonicalPluginSet {
    param(
        [string]$PluginsRoot,
        [string]$CanonicalWindows,
        [string]$CanonicalLinux,
        [string]$CanonicalMac
    )

    $runtimeBinaries = Get-ChildItem -Path $PluginsRoot -Recurse -File | Where-Object {
        $_.Name -eq 'webr_engine.dll' -or $_.Name -eq 'libwebr_engine.so' -or $_.Name -eq 'libwebr_engine.dylib'
    }

    if (-not $runtimeBinaries -or $runtimeBinaries.Count -eq 0) {
        throw "No web-engine runtime binaries found under $PluginsRoot"
    }

    $canonicalWindowsFull = [System.IO.Path]::GetFullPath($CanonicalWindows)
    $canonicalLinuxFull = [System.IO.Path]::GetFullPath($CanonicalLinux)
    $canonicalMacFull = [System.IO.Path]::GetFullPath($CanonicalMac)

    $allowed = @($canonicalWindowsFull, $canonicalLinuxFull)
    if (Test-Path $canonicalMacFull) {
        $allowed += $canonicalMacFull
    }

    $fullPaths = $runtimeBinaries | ForEach-Object { [System.IO.Path]::GetFullPath($_.FullName) }

    $extras = $fullPaths | Where-Object { $allowed -notcontains $_ }
    if ($extras.Count -gt 0) {
        $extraList = ($extras | Sort-Object | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
        throw "Found legacy/non-canonical web runtime binaries:`n$extraList"
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

    if (Test-Path $canonicalMacFull) {
        $macMatches = $fullPaths | Where-Object { $_ -eq $canonicalMacFull }
        if ($macMatches.Count -ne 1) {
            throw "Expected exactly one canonical macOS runtime binary when present, found $($macMatches.Count): $canonicalMacFull"
        }
    }
}

function Assert-WindowsExports {
    param(
        [string]$WindowsDll,
        [string[]]$RequiredSymbols
    )

    if (-not (Test-Path $WindowsDll)) {
        throw "Missing Windows runtime binary: $WindowsDll"
    }

    if (-not ('WebrNativeWindowsLoader' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class WebrNativeWindowsLoader
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

    $module = [WebrNativeWindowsLoader]::LoadLibrary($WindowsDll)
    if ($module -eq [IntPtr]::Zero) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Failed to load $WindowsDll for export verification (Win32=$errorCode)"
    }

    try {
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($symbol in $RequiredSymbols) {
            if ([WebrNativeWindowsLoader]::GetProcAddress($module, $symbol) -eq [IntPtr]::Zero) {
                $missing.Add($symbol)
            }
        }

        if ($missing.Count -gt 0) {
            $missingList = ($missing | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
            throw "Missing required exports in ${WindowsDll}:`n$missingList"
        }
    }
    finally {
        [WebrNativeWindowsLoader]::FreeLibrary($module) | Out-Null
    }
}

function Assert-LinuxExports {
    param(
        [string]$LinuxSo,
        [string[]]$RequiredSymbols
    )

    if (-not (Test-Path $LinuxSo)) {
        throw "Missing Linux runtime binary: $LinuxSo"
    }

    $nm = Get-Command nm -ErrorAction SilentlyContinue
    if (-not $nm) {
        Write-Warning "Skipping Linux export verification (nm not available on this host)."
        return
    }

    $dump = (& $nm.Source -D --defined-only $LinuxSo | Out-String)
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($symbol in $RequiredSymbols) {
        if ($dump -notmatch "(^|[^A-Za-z0-9_])$([regex]::Escape($symbol))([^A-Za-z0-9_]|$)") {
            $missing.Add($symbol)
        }
    }

    if ($missing.Count -gt 0) {
        $missingList = ($missing | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
        throw "Missing required exports in ${LinuxSo}:`n$missingList"
    }
}

$root = Get-RepoRoot
$unityPkg = Join-Path $root 'repos/web-engine-unity'
$pluginsRoot = Join-Path $unityPkg 'Runtime/Plugins'
$canonicalWindows = Join-Path $pluginsRoot 'Windows/x86_64/webr_engine.dll'
$canonicalLinux = Join-Path $pluginsRoot 'Linux/x86_64/libwebr_engine.so'
$canonicalMac = Join-Path $pluginsRoot 'macOS/libwebr_engine.dylib'
$nativeBindingsPath = Join-Path $unityPkg 'Runtime/WebrNative.cs'

if (-not (Test-Path $pluginsRoot)) {
    throw "Missing plugins root: $pluginsRoot"
}

Assert-CanonicalPluginSet -PluginsRoot $pluginsRoot -CanonicalWindows $canonicalWindows -CanonicalLinux $canonicalLinux -CanonicalMac $canonicalMac

if ($VerifyExports) {
    $requiredSymbols = Get-ManagedExternSymbols -NativeBindingsPath $nativeBindingsPath
    Assert-WindowsExports -WindowsDll ([System.IO.Path]::GetFullPath($canonicalWindows)) -RequiredSymbols $requiredSymbols
    Assert-LinuxExports -LinuxSo ([System.IO.Path]::GetFullPath($canonicalLinux)) -RequiredSymbols $requiredSymbols
}

Write-Host "Web runtime layout OK"
Write-Host "  windows: $([System.IO.Path]::GetFullPath($canonicalWindows))"
Write-Host "  linux:   $([System.IO.Path]::GetFullPath($canonicalLinux))"
if (Test-Path $canonicalMac) {
    Write-Host "  macOS:   $([System.IO.Path]::GetFullPath($canonicalMac))"
}
if ($VerifyExports) {
    Write-Host "  managed extern exports: verified"
}
