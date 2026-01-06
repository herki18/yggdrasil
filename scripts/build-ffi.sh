#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SE_DIR="$ROOT_DIR/repos/scripting-engine-rust"
WE_DIR="$ROOT_DIR/repos/web-engine-rust"
SE_PKG="$ROOT_DIR/repos/scripting-engine-unity"
WE_PKG="$ROOT_DIR/repos/web-engine-unity"

PROFILE="debug"
TARGETS=()

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--profile debug|release] [--target <triple> | --targets <t1,t2,...>]

Builds Rust FFI libs and copies them into the Unity packages under Runtime/Plugins/<Platform>/<Arch>/.

Examples:
  $(basename "$0") --profile release
  $(basename "$0") --targets x86_64-pc-windows-msvc,x86_64-unknown-linux-gnu
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"; shift 2 ;;
    --target)
      TARGETS+=("$2"); shift 2 ;;
    --targets)
      IFS=',' read -r -a TARGETS <<< "$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  HOST_TRIPLE="$(rustc -vV | sed -n 's/^host: //p')"
  if [[ -z "$HOST_TRIPLE" ]]; then
    echo "Failed to detect host triple from rustc" >&2
    exit 1
  fi
  TARGETS=("$HOST_TRIPLE")
fi

if [[ "$PROFILE" != "debug" && "$PROFILE" != "release" ]]; then
  echo "Invalid profile: $PROFILE (use debug or release)" >&2
  exit 1
fi

PROFILE_DIR="$PROFILE"
CARGO_PROFILE_ARGS=()
if [[ "$PROFILE" == "release" ]]; then
  CARGO_PROFILE_ARGS+=("--release")
fi

platform_for_target() {
  local t="$1"
  case "$t" in
    *windows*) echo "Windows" ;;
    *linux*) echo "Linux" ;;
    *apple-darwin*) echo "macOS" ;;
    *) echo "" ;;
  esac
}

arch_for_target() {
  local t="$1"
  local arch="${t%%-*}"
  case "$arch" in
    x86_64) echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "$arch" ;;
  esac
}

ext_for_target() {
  local t="$1"
  case "$t" in
    *windows*) echo "dll" ;;
    *linux*) echo "so" ;;
    *apple-darwin*) echo "dylib" ;;
    *) echo "" ;;
  esac
}

prefix_for_target() {
  local t="$1"
  case "$t" in
    *windows*) echo "" ;;
    *linux*|*apple-darwin*) echo "lib" ;;
    *) echo "" ;;
  esac
}

for TARGET in "${TARGETS[@]}"; do
  PLATFORM="$(platform_for_target "$TARGET")"
  ARCH="$(arch_for_target "$TARGET")"
  EXT="$(ext_for_target "$TARGET")"
  PREFIX="$(prefix_for_target "$TARGET")"

  if [[ -z "$PLATFORM" || -z "$EXT" ]]; then
    echo "Unsupported target: $TARGET" >&2
    exit 1
  fi

  echo "== Building for $TARGET ($PLATFORM/$ARCH) [$PROFILE] =="

  (cd "$SE_DIR" && cargo build -p se-ffi --target "$TARGET" "${CARGO_PROFILE_ARGS[@]}")
  (cd "$WE_DIR" && cargo build -p webr-engine-ffi --target "$TARGET" "${CARGO_PROFILE_ARGS[@]}")

  SE_OUT="$SE_DIR/target/$TARGET/$PROFILE_DIR/${PREFIX}se_ffi.$EXT"
  WE_OUT="$WE_DIR/target/$TARGET/$PROFILE_DIR/${PREFIX}webr_engine.$EXT"

  if [[ ! -f "$SE_OUT" ]]; then
    echo "Missing output: $SE_OUT" >&2
    exit 1
  fi
  if [[ ! -f "$WE_OUT" ]]; then
    echo "Missing output: $WE_OUT" >&2
    exit 1
  fi

  SE_DEST="$SE_PKG/Runtime/Plugins/$PLATFORM/$ARCH"
  WE_DEST="$WE_PKG/Runtime/Plugins/$PLATFORM/$ARCH"

  mkdir -p "$SE_DEST" "$WE_DEST"
  cp "$SE_OUT" "$SE_DEST/"
  cp "$WE_OUT" "$WE_DEST/"

  echo "  -> $SE_DEST/$(basename "$SE_OUT")"
  echo "  -> $WE_DEST/$(basename "$WE_OUT")"
  echo
 done

echo "Done."
