#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-all}"
TARGET="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXPLICIT_SCRIPT="$ROOT_DIR/scripts/build-web-engine-ffi.sh"

if [[ ! -f "$EXPLICIT_SCRIPT" ]]; then
  echo "Missing script: $EXPLICIT_SCRIPT" >&2
  exit 1
fi

run_profile() {
  local profile="$1"
  if [[ -n "$TARGET" ]]; then
    "$EXPLICIT_SCRIPT" --profile "$profile" --target "$TARGET"
  else
    "$EXPLICIT_SCRIPT" --profile "$profile"
  fi
}

case "$CONFIGURATION" in
  debug)
    run_profile debug
    ;;
  release)
    run_profile release
    ;;
  all)
    run_profile debug
    run_profile release
    ;;
  *)
    echo "Usage: $(basename "$0") [debug|release|all] [target]" >&2
    exit 1
    ;;
esac
