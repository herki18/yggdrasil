#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_REPO="$ROOT_DIR/repos/web-engine-rust"
UNITY_PKG="$ROOT_DIR/repos/web-engine-unity"

PROFILE="release"
TARGET=""

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--profile debug|release] [--target <triple>]

Builds web engine FFI and copies it to the canonical Unity plugin path.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"; shift 2 ;;
    --target)
      TARGET="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ "$PROFILE" != "debug" && "$PROFILE" != "release" ]]; then
  echo "Invalid profile: $PROFILE" >&2
  exit 1
fi

if [[ -z "$TARGET" ]]; then
  TARGET="$(rustc -vV | sed -n 's/^host: //p')"
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
    *) echo "lib" ;;
  esac
}

remove_legacy_runtime_artifacts() {
  local plugins_root="$UNITY_PKG/Runtime/Plugins"
  local canonical_windows="$plugins_root/Windows/x86_64/webr_engine.dll"
  local canonical_linux="$plugins_root/Linux/x86_64/libwebr_engine.so"
  local canonical_macos="$plugins_root/macOS/libwebr_engine.dylib"

  rm -rf \
    "$plugins_root/Windows/x86_64/Debug" "$plugins_root/Windows/x86_64/Debug.meta" \
    "$plugins_root/Linux/x86_64/Debug" "$plugins_root/Linux/x86_64/Debug.meta" \
    "$plugins_root/macOS/Debug" "$plugins_root/macOS/Debug.meta"

  while IFS= read -r runtime_file; do
    [[ -z "$runtime_file" ]] && continue
    if [[ "$runtime_file" != "$canonical_windows" && "$runtime_file" != "$canonical_linux" && "$runtime_file" != "$canonical_macos" ]]; then
      echo "Removing legacy runtime binary: $runtime_file"
      rm -f "$runtime_file" "$runtime_file.meta"
    fi
  done < <(find "$plugins_root" -type f \( -name "webr_engine.dll" -o -name "libwebr_engine.so" -o -name "libwebr_engine.dylib" \))
}

if [[ ! -d "$RUST_REPO" ]]; then
  echo "Missing repo: $RUST_REPO" >&2
  exit 1
fi
if [[ ! -d "$UNITY_PKG" ]]; then
  echo "Missing repo: $UNITY_PKG" >&2
  exit 1
fi

PLATFORM="$(platform_for_target "$TARGET")"
ARCH="$(arch_for_target "$TARGET")"
EXT="$(ext_for_target "$TARGET")"
PREFIX="$(prefix_for_target "$TARGET")"
if [[ -z "$PLATFORM" || -z "$EXT" ]]; then
  echo "Unsupported target: $TARGET" >&2
  exit 1
fi

TARGET_DIR="$(cd "$RUST_REPO" && cargo metadata --format-version 1 --no-deps | sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p' | head -n 1)"
if [[ -z "$TARGET_DIR" ]]; then
  echo "Failed to resolve cargo target_directory" >&2
  exit 1
fi

CARGO_ARGS=(build -p webr-engine-ffi --target "$TARGET")
if [[ "$PROFILE" == "release" ]]; then
  CARGO_ARGS+=(--release)
fi

(cd "$RUST_REPO" && cargo "${CARGO_ARGS[@]}")

OUT_PATH="$TARGET_DIR/$TARGET/$PROFILE/${PREFIX}webr_engine.$EXT"
if [[ ! -f "$OUT_PATH" ]]; then
  echo "Missing output: $OUT_PATH" >&2
  exit 1
fi

remove_legacy_runtime_artifacts

DEST_DIR="$UNITY_PKG/Runtime/Plugins/$PLATFORM/$ARCH"
mkdir -p "$DEST_DIR"
cp "$OUT_PATH" "$DEST_DIR/"

"$ROOT_DIR/scripts/check-web-engine-runtime-layout.sh" --verify-exports

echo "Built web engine FFI"
echo "  target: $TARGET"
echo "  profile: $PROFILE"
echo "  source: $OUT_PATH"
echo "  destination: $DEST_DIR/$(basename "$OUT_PATH")"
