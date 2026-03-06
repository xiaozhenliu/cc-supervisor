#!/usr/bin/env bash
# test-multi-session-runtime.sh - Verify multi-session runtime helpers and registry isolation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
PROJECT_A="${TEST_ROOT}/project-a"
PROJECT_B="${TEST_ROOT}/project-b"
ID_A="multi-a-$$"
ID_B="multi-b-$$"
ID_C="multi-c-$$"
SESSION_A="cc-supervise-${ID_A}"
SESSION_B="cc-supervise-${ID_B}"

cleanup() {
  tmux kill-session -t "$SESSION_A" 2>/dev/null || true
  tmux kill-session -t "$SESSION_B" 2>/dev/null || true
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$PROJECT_A" "$PROJECT_B"

export CC_PROJECT_DIR="$TEST_ROOT"
source "${SOURCE_REPO}/scripts/lib/runtime_context.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [[ "$expected" == "$actual" ]]; then
    echo "✓ PASS: $description"
  else
    echo "✗ FAIL: $description"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    exit 1
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Multi-Session Runtime Helpers"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

runtime_context_init "default"
assert_eq "${TEST_ROOT}/logs" "$CC_RUNTIME_DIR" "default runtime dir stays top-level"
assert_eq "cc-supervise" "$CC_TMUX_SESSION" "default tmux session keeps backward-compatible name"

runtime_context_init "$ID_A"
assert_eq "${TEST_ROOT}/logs/instances/${ID_A}" "$CC_RUNTIME_DIR" "named instance uses isolated runtime dir"
assert_eq "$SESSION_A" "$CC_TMUX_SESSION" "named instance uses isolated tmux session"

tmux new-session -d -s "$SESSION_A" -c "$PROJECT_A" "sleep 60"
tmux new-session -d -s "$SESSION_B" -c "$PROJECT_B" "sleep 60"

register_supervision "$ID_A" "$PROJECT_A" "relay" "running"
register_supervision "$ID_B" "$PROJECT_B" "auto" "running"

assert_eq "$ID_A" "$(resolve_project_supervision "$PROJECT_A")" "project A resolves to instance A"
assert_eq "$ID_B" "$(resolve_project_supervision "$PROJECT_B")" "project B resolves to instance B"

if assert_supervision_start_allowed "$ID_C" "$PROJECT_A" >/dev/null 2>&1; then
  echo "✗ FAIL: same project should reject a second active supervision id"
  exit 1
else
  echo "✓ PASS: same project duplicate start is rejected"
fi

if assert_supervision_start_allowed "$ID_A" "$PROJECT_B" >/dev/null 2>&1; then
  echo "✗ FAIL: same supervision id should reject a different active project"
  exit 1
else
  echo "✓ PASS: same id cannot be rebound to another active project"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Multi-session runtime test passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
