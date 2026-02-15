#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="debug"
DO_LINUX=true
DO_WINDOWS=true

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--profile debug|release] [--linux] [--windows] [--linux-target <triple>] [--windows-target <triple>]

Builds Linux and/or Windows FFI libs and copies them into the Unity packages.
- Linux build uses explicit per-engine scripts.
- Windows build invokes explicit per-engine PowerShell scripts (WSL-friendly).

Examples:
  $(basename "$0") --profile release
  $(basename "$0") --linux --windows
  $(basename "$0") --windows --windows-target x86_64-pc-windows-msvc
USAGE
}

LINUX_TARGET=""
WINDOWS_TARGET="x86_64-pc-windows-msvc"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"; shift 2 ;;
    --linux)
      DO_LINUX=true; DO_WINDOWS=false; shift ;;
    --windows)
      DO_WINDOWS=true; DO_LINUX=false; shift ;;
    --linux-target)
      LINUX_TARGET="$2"; shift 2 ;;
    --windows-target)
      WINDOWS_TARGET="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [[ "$PROFILE" != "debug" && "$PROFILE" != "release" ]]; then
  echo "Invalid profile: $PROFILE (use debug or release)" >&2
  exit 1
fi

if $DO_LINUX; then
  echo "== Linux build =="
  if [[ -n "$LINUX_TARGET" ]]; then
    "$ROOT_DIR/scripts/build-scripting-engine-ffi.sh" --profile "$PROFILE" --target "$LINUX_TARGET"
    "$ROOT_DIR/scripts/build-web-engine-ffi.sh" --profile "$PROFILE" --target "$LINUX_TARGET"
  else
    "$ROOT_DIR/scripts/build-scripting-engine-ffi.sh" --profile "$PROFILE"
    "$ROOT_DIR/scripts/build-web-engine-ffi.sh" --profile "$PROFILE"
  fi
fi

if $DO_WINDOWS; then
  echo "== Windows build (via powershell.exe) =="
  if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "powershell.exe not found. Run this step on Windows or install WSL interop." >&2
    exit 1
  fi
  WIN_ROOT="$(wslpath -w "$ROOT_DIR")"
  WIN_SE_SCRIPT="${WIN_ROOT}\\scripts\\build-scripting-engine-ffi.ps1"
  WIN_WE_SCRIPT="${WIN_ROOT}\\scripts\\build-web-engine-ffi.ps1"
  powershell.exe -ExecutionPolicy Bypass -File "$WIN_SE_SCRIPT" -Profile "$PROFILE" -Target "$WINDOWS_TARGET"
  powershell.exe -ExecutionPolicy Bypass -File "$WIN_WE_SCRIPT" -Profile "$PROFILE" -Target "$WINDOWS_TARGET"
fi

echo "All requested builds completed."
