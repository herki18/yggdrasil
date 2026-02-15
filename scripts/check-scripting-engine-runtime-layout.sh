#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGINS_ROOT="$ROOT_DIR/repos/scripting-engine-unity/Runtime/Plugins"
CANONICAL_WINDOWS="$PLUGINS_ROOT/Windows/x86_64/se_ffi.dll"
CANONICAL_LINUX="$PLUGINS_ROOT/Linux/x86_64/libse_ffi.so"
VERIFY_EXPORTS=false

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--verify-exports]

Validates that exactly one canonical scripting runtime binary exists per platform
and that no legacy duplicate se_ffi binaries are present.
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

mapfile -t RUNTIME_BINARIES < <(find "$PLUGINS_ROOT" -type f \( -name "se_ffi.dll" -o -name "libse_ffi.so" \) | sort)
if [[ ${#RUNTIME_BINARIES[@]} -eq 0 ]]; then
  echo "No scripting runtime binaries found under $PLUGINS_ROOT" >&2
  exit 1
fi

EXTRAS=()
for binary in "${RUNTIME_BINARIES[@]}"; do
  if [[ "$binary" != "$CANONICAL_WINDOWS" && "$binary" != "$CANONICAL_LINUX" ]]; then
    EXTRAS+=("$binary")
  fi
done

if [[ ${#EXTRAS[@]} -gt 0 ]]; then
  echo "Found legacy/non-canonical scripting runtime binaries:" >&2
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

if $VERIFY_EXPORTS; then
  REQUIRED_SYMBOLS=(
    se_api_version
    se_get_capabilities
    se_runtime_family
    se_runtime_build_id
  )

  if ! command -v objdump >/dev/null 2>&1; then
    echo "objdump is required for Windows export verification." >&2
    exit 2
  fi
  if ! command -v nm >/dev/null 2>&1; then
    echo "nm is required for Linux export verification." >&2
    exit 2
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

echo "Scripting runtime layout OK"
echo "  windows: $CANONICAL_WINDOWS"
echo "  linux:   $CANONICAL_LINUX"
if $VERIFY_EXPORTS; then
  echo "  required exports: verified"
fi
