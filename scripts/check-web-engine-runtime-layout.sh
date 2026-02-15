#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGINS_ROOT="$ROOT_DIR/repos/web-engine-unity/Runtime/Plugins"
NATIVE_BINDINGS="$ROOT_DIR/repos/web-engine-unity/Runtime/WebrNative.cs"

CANONICAL_WINDOWS="$PLUGINS_ROOT/Windows/x86_64/webr_engine.dll"
CANONICAL_LINUX="$PLUGINS_ROOT/Linux/x86_64/libwebr_engine.so"
CANONICAL_MACOS="$PLUGINS_ROOT/macOS/libwebr_engine.dylib"
VERIFY_EXPORTS=false

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--verify-exports]

Validates canonical web-engine runtime layout and detects legacy/duplicate binaries.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-exports)
      VERIFY_EXPORTS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -d "$PLUGINS_ROOT" ]]; then
  echo "Missing plugins root: $PLUGINS_ROOT" >&2
  exit 1
fi

if [[ ! -f "$NATIVE_BINDINGS" ]]; then
  echo "Missing native bindings file: $NATIVE_BINDINGS" >&2
  exit 1
fi

mapfile -t RUNTIME_BINARIES < <(find "$PLUGINS_ROOT" -type f \( -name "webr_engine.dll" -o -name "libwebr_engine.so" -o -name "libwebr_engine.dylib" \) | sort)
if [[ ${#RUNTIME_BINARIES[@]} -eq 0 ]]; then
  echo "No web-engine runtime binaries found under $PLUGINS_ROOT" >&2
  exit 1
fi

ALLOWED=("$CANONICAL_WINDOWS" "$CANONICAL_LINUX")
if [[ -f "$CANONICAL_MACOS" ]]; then
  ALLOWED+=("$CANONICAL_MACOS")
fi

EXTRAS=()
for binary in "${RUNTIME_BINARIES[@]}"; do
  allowed=false
  for canonical in "${ALLOWED[@]}"; do
    if [[ "$binary" == "$canonical" ]]; then
      allowed=true
      break
    fi
  done
  if ! $allowed; then
    EXTRAS+=("$binary")
  fi
done

if [[ ${#EXTRAS[@]} -gt 0 ]]; then
  echo "Found legacy/non-canonical web runtime binaries:" >&2
  printf '  - %s\n' "${EXTRAS[@]}" >&2
  exit 1
fi

if [[ ! -f "$CANONICAL_WINDOWS" ]]; then
  echo "Missing canonical Windows runtime binary: $CANONICAL_WINDOWS" >&2
  exit 1
fi
if [[ ! -f "$CANONICAL_LINUX" ]]; then
  echo "Missing canonical Linux runtime binary: $CANONICAL_LINUX" >&2
  exit 1
fi

WINDOWS_COUNT=$(printf '%s\n' "${RUNTIME_BINARIES[@]}" | grep -cFx "$CANONICAL_WINDOWS" || true)
LINUX_COUNT=$(printf '%s\n' "${RUNTIME_BINARIES[@]}" | grep -cFx "$CANONICAL_LINUX" || true)

if [[ "$WINDOWS_COUNT" -ne 1 ]]; then
  echo "Expected exactly one canonical Windows runtime binary, found $WINDOWS_COUNT" >&2
  exit 1
fi
if [[ "$LINUX_COUNT" -ne 1 ]]; then
  echo "Expected exactly one canonical Linux runtime binary, found $LINUX_COUNT" >&2
  exit 1
fi

if [[ -f "$CANONICAL_MACOS" ]]; then
  MAC_COUNT=$(printf '%s\n' "${RUNTIME_BINARIES[@]}" | grep -cFx "$CANONICAL_MACOS" || true)
  if [[ "$MAC_COUNT" -ne 1 ]]; then
    echo "Expected exactly one canonical macOS runtime binary when present, found $MAC_COUNT" >&2
    exit 1
  fi
fi

if $VERIFY_EXPORTS; then
  if ! command -v objdump >/dev/null 2>&1; then
    echo "objdump is required for Windows export verification." >&2
    exit 2
  fi
  if ! command -v nm >/dev/null 2>&1; then
    echo "nm is required for Linux export verification." >&2
    exit 2
  fi

  mapfile -t REQUIRED_SYMBOLS < <(awk '
    /internal static .*extern .* webr_[A-Za-z0-9_]+\(/ {
      if (match($0, /(webr_[A-Za-z0-9_]+)\(/, m)) {
        print m[1]
      }
    }
  ' "$NATIVE_BINDINGS" | sort -u)

  if [[ ${#REQUIRED_SYMBOLS[@]} -eq 0 ]]; then
    echo "Failed to extract managed extern symbols from $NATIVE_BINDINGS" >&2
    exit 1
  fi

  WINDOWS_EXPORT_DUMP="$(objdump -p "$CANONICAL_WINDOWS")"
  LINUX_EXPORT_DUMP="$(nm -D --defined-only "$CANONICAL_LINUX")"

  MISSING_WINDOWS=()
  for symbol in "${REQUIRED_SYMBOLS[@]}"; do
    if ! grep -Eq "(^|[^A-Za-z0-9_])${symbol}([^A-Za-z0-9_]|$)" <<<"$WINDOWS_EXPORT_DUMP"; then
      MISSING_WINDOWS+=("$symbol")
    fi
  done
  if [[ ${#MISSING_WINDOWS[@]} -gt 0 ]]; then
    echo "Missing required exports in $CANONICAL_WINDOWS:" >&2
    printf '  - %s\n' "${MISSING_WINDOWS[@]}" >&2
    exit 1
  fi

  MISSING_LINUX=()
  for symbol in "${REQUIRED_SYMBOLS[@]}"; do
    if ! grep -Eq "(^|[^A-Za-z0-9_])${symbol}([^A-Za-z0-9_]|$)" <<<"$LINUX_EXPORT_DUMP"; then
      MISSING_LINUX+=("$symbol")
    fi
  done
  if [[ ${#MISSING_LINUX[@]} -gt 0 ]]; then
    echo "Missing required exports in $CANONICAL_LINUX:" >&2
    printf '  - %s\n' "${MISSING_LINUX[@]}" >&2
    exit 1
  fi
fi

echo "Web runtime layout OK"
echo "  windows: $CANONICAL_WINDOWS"
echo "  linux:   $CANONICAL_LINUX"
if [[ -f "$CANONICAL_MACOS" ]]; then
  echo "  macOS:   $CANONICAL_MACOS"
fi
if $VERIFY_EXPORTS; then
  echo "  managed extern exports: verified"
fi
