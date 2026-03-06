#!/usr/bin/env bash
# test-install-hooks-failure.sh - Verify install-hooks.sh reports readable failures.
# Usage: ./scripts/test-install-hooks-failure.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$(mktemp -d)"
TEMP_REPO="${TEST_DIR}/repo"
TARGET_PROJECT="${TEST_DIR}/target-project"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

assert_failure_message() {
  local description="$1"
  local command="$2"
  local expected_message="$3"
  local output_file="${TEST_DIR}/failure.out"

  set +e
  bash -lc "$command" >"$output_file" 2>&1
  local exit_code=$?
  set -e

  if [[ "$exit_code" -eq 0 ]]; then
    echo "✗ FAIL: $description"
    echo "  expected non-zero exit"
    cat "$output_file"
    exit 1
  fi

  if grep -Fq -- "$expected_message" "$output_file"; then
    echo "✓ PASS: $description"
  else
    echo "✗ FAIL: $description"
    echo "  missing: $expected_message"
    cat "$output_file"
    exit 1
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing install-hooks Failure Messages"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

mkdir -p "$TARGET_PROJECT"
rsync -a --exclude='.git' --exclude='logs' "$CC_PROJECT_DIR/" "$TEMP_REPO/"

rm -f "${TEMP_REPO}/config/claude-hooks.json"
assert_failure_message \
  "missing template reports clear error" \
  "CC_PROJECT_DIR='${TEMP_REPO}' CLAUDE_WORKDIR='${TARGET_PROJECT}' bash '${TEMP_REPO}/scripts/install-hooks.sh'" \
  "Hook template not found:"

rsync -a --exclude='.git' --exclude='logs' "$CC_PROJECT_DIR/" "$TEMP_REPO/"
printf '%s\n' '{invalid json' > "${TEMP_REPO}/config/claude-hooks.json"
assert_failure_message \
  "invalid template reports clear error" \
  "CC_PROJECT_DIR='${TEMP_REPO}' CLAUDE_WORKDIR='${TARGET_PROJECT}' bash '${TEMP_REPO}/scripts/install-hooks.sh'" \
  "Substituted hook JSON is invalid"

rsync -a --exclude='.git' --exclude='logs' "$CC_PROJECT_DIR/" "$TEMP_REPO/"
rm -f "${TEMP_REPO}/scripts/on-cc-event.sh"
assert_failure_message \
  "missing hook script reports clear error" \
  "CC_PROJECT_DIR='${TEMP_REPO}' CLAUDE_WORKDIR='${TARGET_PROJECT}' bash '${TEMP_REPO}/scripts/install-hooks.sh'" \
  "Hook script not found:"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "install-hooks failure tests passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
