#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${1:-$SCRIPT_DIR/../repos/sunderia}"
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

UNITY_EXE="${UNITY_EDITOR:-}"
LOG_FILE="${LOG_FILE:-/tmp/sunderia-world-script-validation.log}"
TEST_RESULTS="${TEST_RESULTS:-/tmp/sunderia-world-script-validation-results.xml}"
WARMUP_LOG_FILE="${WARMUP_LOG_FILE:-${LOG_FILE%.*}.warmup.log}"
SKIP_WARMUP="${SKIP_WARMUP:-0}"

if [[ -z "$UNITY_EXE" ]] && command -v unity >/dev/null 2>&1; then
  UNITY_EXE="$(command -v unity)"
fi

if [[ -z "$UNITY_EXE" ]]; then
  for candidate in \
    "/opt/unity/Editor/Unity" \
    "/Applications/Unity/Hub/Editor/Unity.app/Contents/MacOS/Unity"; do
    if [[ -x "$candidate" ]]; then
      UNITY_EXE="$candidate"
      break
    fi
  done
fi

if [[ -z "$UNITY_EXE" ]]; then
  echo "Unable to locate Unity editor. Set UNITY_EDITOR to your Unity executable path." >&2
  exit 1
fi

echo "Unity editor: $UNITY_EXE"
echo "Project path: $PROJECT_PATH"
echo "Log file: $LOG_FILE"
echo "Warmup log file: $WARMUP_LOG_FILE"
echo "Test results: $TEST_RESULTS"

BUILD_INFO_PATH="$SCRIPT_DIR/../repos/scripting-engine-unity/Runtime/NativeRuntimeBuildInfo.g.cs"
if [[ ! -f "$BUILD_INFO_PATH" ]]; then
  echo "Missing runtime build info file: $BUILD_INFO_PATH" >&2
  exit 1
fi
if grep -Eq 'ExpectedBuildId\s*=\s*"UNSET"' "$BUILD_INFO_PATH"; then
  echo "Native runtime build ID is UNSET. Run ./scripts/build-scripting-engine-ffi.sh before validation." >&2
  exit 1
fi

"$SCRIPT_DIR/check-scripting-engine-runtime-layout.sh" --verify-exports

if [[ "$SKIP_WARMUP" != "1" ]]; then
  echo "Warmup pass: importing/compiling project before test run..."
  "$UNITY_EXE" \
    -batchmode \
    -nographics \
    -quit \
    -projectPath "$PROJECT_PATH" \
    -logFile "$WARMUP_LOG_FILE"
fi

rm -f "$TEST_RESULTS"

"$UNITY_EXE" \
  -batchmode \
  -nographics \
  -projectPath "$PROJECT_PATH" \
  -runTests \
  -testPlatform EditMode \
  -assemblyNames "Sunderia.World.Tests.EditMode" \
  -testResults "$TEST_RESULTS" \
  -logFile "$LOG_FILE"

if [[ ! -f "$TEST_RESULTS" ]]; then
  if [[ -f "$LOG_FILE" ]] && grep -Eq "No tests to run|No tests were found|Test run cancelled|Compilation failed" "$LOG_FILE"; then
    echo "Unity did not produce test results because tests did not execute. See $LOG_FILE." >&2
    exit 1
  fi
  echo "Missing test results file: $TEST_RESULTS (see $LOG_FILE and $WARMUP_LOG_FILE)" >&2
  exit 1
fi

if grep -q 'result="Failed"' "$TEST_RESULTS"; then
  echo "Script dialect validation failed. See $TEST_RESULTS and $LOG_FILE." >&2
  exit 1
fi

echo "Sunderia world script validation passed."
