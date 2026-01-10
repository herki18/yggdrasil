#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-all}"
RUST_REPO_PATH="${WEB_ENGINE_RUST_PATH:-}"

resolve_root() {
  cd "$(dirname "$0")/../.." && pwd
}

resolve_rust_repo() {
  if [[ -n "$RUST_REPO_PATH" ]]; then
    echo "$RUST_REPO_PATH"
    return
  fi

  local candidate
  candidate="$(resolve_root)/repos/web-engine-rust"
  if [[ -d "$candidate" ]]; then
    echo "$candidate"
    return
  fi

  echo "ERROR: Could not locate web-engine-rust. Set WEB_ENGINE_RUST_PATH." >&2
  exit 1
}

resolve_package() {
  local candidate
  candidate="$(resolve_root)/repos/web-engine-unity"
  if [[ -d "$candidate" ]]; then
    echo "$candidate"
    return
  fi

  echo "ERROR: Could not locate web-engine-unity package." >&2
  exit 1
}

build_one() {
  local profile="$1"
  local rust_repo="$2"
  local package_path="$3"
  local target_dir="debug"
  local lib_name=""
  local os

  if [[ "$profile" == "release" ]]; then
    target_dir="release"
  fi

  os="$(uname -s)"
  case "$os" in
    Linux*)
      lib_name="libwebr_engine.so"
      ;;
    Darwin*)
      lib_name="libwebr_engine.dylib"
      ;;
    *)
      echo "ERROR: Unsupported OS $os. Use build-native.ps1 on Windows." >&2
      exit 1
      ;;
  esac

  (cd "$rust_repo" && cargo build -p webr-engine-ffi ${profile:+--$profile})

  local src="$rust_repo/target/$target_dir/$lib_name"
  if [[ ! -f "$src" ]]; then
    echo "ERROR: Expected build output not found: $src" >&2
    exit 1
  fi

  local dest_base
  if [[ "$os" == "Darwin"* ]]; then
    dest_base="$package_path/Runtime/Plugins/macOS"
  else
    dest_base="$package_path/Runtime/Plugins/Linux/x86_64"
  fi

  local dest_dir
  if [[ "$profile" == "release" ]]; then
    dest_dir="$dest_base"
  else
    dest_dir="$dest_base/Debug"
  fi

  mkdir -p "$dest_dir"
  cp "$src" "$dest_dir/$lib_name"
  echo "Copied $profile build to $dest_dir"
}

rust_repo="$(resolve_rust_repo)"
package_path="$(resolve_package)"

case "$CONFIGURATION" in
  debug)
    build_one "debug" "$rust_repo" "$package_path"
    ;;
  release)
    build_one "release" "$rust_repo" "$package_path"
    ;;
  all)
    build_one "debug" "$rust_repo" "$package_path"
    build_one "release" "$rust_repo" "$package_path"
    ;;
  *)
    echo "Usage: $(basename "$0") [debug|release|all]" >&2
    exit 1
    ;;
esac
