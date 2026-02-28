#!/usr/bin/env bash
# test_cc_start.sh — Layer 3 tests for cc-start.sh pre-flight checks.
#
# Tests the argument validation, environment checks, and hook installation
# failure detection in cc-start.sh. Does NOT require tmux or openclaw.
#
# Usage: ./tests/test_cc_start.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPT="$PROJECT_DIR/scripts/cc-start.sh"

PASS=0
FAIL=0

# ── Helpers ───────────────────────────────────────────────────────────────────

assert_exit_nonzero() {
  local label="$1" exit_code="$2"
  if [[ "$exit_code" -ne 0 ]]; then
    echo "  PASS: $label (exit=$exit_code)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — expected non-zero exit, got 0"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local label="$1" output="$2" pattern="$3"
  if echo "$output" | grep -q "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — expected '$pattern' in output"
    echo "    actual output:"
    echo "$output" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
}

# Run cc-start.sh with given args and env, capture output + exit code.
# Sets globals: RUN_OUTPUT, RUN_EXIT
run_cc_start() {
  local env_prefix="$1"; shift
  RUN_OUTPUT="$(env $env_prefix bash "$SCRIPT" "$@" 2>&1)" || RUN_EXIT=$?
  RUN_EXIT="${RUN_EXIT:-0}"
}

RUN_OUTPUT=""
RUN_EXIT=0

# ── S1: Argument validation ───────────────────────────────────────────────────
echo "=== Layer 3: cc-start Pre-flight Tests ==="
echo ""
echo "── S1: Argument validation ───────────────────────────────────────────────"

# S1-01: no args → exit 1 + Usage
RUN_EXIT=0
RUN_OUTPUT="$(bash "$SCRIPT" 2>&1)" || RUN_EXIT=$?
assert_exit_nonzero "S1-01: no args → non-zero exit" "$RUN_EXIT"
assert_output_contains "S1-01b: no args → Usage in output" "$RUN_OUTPUT" "Usage"

# S1-02: non-existent directory → exit 1 + "does not exist"
RUN_EXIT=0
RUN_OUTPUT="$(OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="123" \
  bash "$SCRIPT" "/tmp/nonexistent_cc_test_dir_$$" 2>&1)" || RUN_EXIT=$?
assert_exit_nonzero "S1-02: non-existent dir → non-zero exit" "$RUN_EXIT"
assert_output_contains "S1-02b: non-existent dir → 'does not exist'" "$RUN_OUTPUT" "does not exist"

# S1-03: invalid mode → exit 1 + "mode must be"
RUN_EXIT=0
RUN_OUTPUT="$(OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="123" \
  bash "$SCRIPT" "/tmp" "badmode" 2>&1)" || RUN_EXIT=$?
assert_exit_nonzero "S1-03: invalid mode → non-zero exit" "$RUN_EXIT"
assert_output_contains "S1-03b: invalid mode → 'mode must be'" "$RUN_OUTPUT" "mode must be"

echo ""

# ── S2: Environment variable validation ───────────────────────────────────────
echo "── S2: Environment variable validation ───────────────────────────────────"

# S2-01: no OPENCLAW_SESSION_ID → exit 1 + "not set"
RUN_EXIT=0
RUN_OUTPUT="$(OPENCLAW_SESSION_ID="" \
  OPENCLAW_TARGET="123" \
  bash "$SCRIPT" "/tmp" 2>&1)" || RUN_EXIT=$?
assert_exit_nonzero "S2-01: no SESSION_ID → non-zero exit" "$RUN_EXIT"
assert_output_contains "S2-01b: no SESSION_ID → 'not set'" "$RUN_OUTPUT" "not set"

# S2-02: invalid UUID format → exit 1 + "invalid format"
RUN_EXIT=0
RUN_OUTPUT="$(OPENCLAW_SESSION_ID="not-a-uuid" \
  OPENCLAW_TARGET="123" \
  bash "$SCRIPT" "/tmp" 2>&1)" || RUN_EXIT=$?
assert_exit_nonzero "S2-02: invalid UUID → non-zero exit" "$RUN_EXIT"
assert_output_contains "S2-02b: invalid UUID → 'invalid format'" "$RUN_OUTPUT" "invalid format"

# S2-03: no OPENCLAW_TARGET → exit 1 + "not set"
RUN_EXIT=0
RUN_OUTPUT="$(OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" \
  bash "$SCRIPT" "/tmp" 2>&1)" || RUN_EXIT=$?
assert_exit_nonzero "S2-03: no OPENCLAW_TARGET → non-zero exit" "$RUN_EXIT"
assert_output_contains "S2-03b: no OPENCLAW_TARGET → 'not set'" "$RUN_OUTPUT" "not set"

echo ""

# ── S3: Hook installation failure detection (BUG-001) ─────────────────────────
echo "── S3: Hook installation failure detection (BUG-001) ─────────────────────"

# Create a temp project dir with a mock install-hooks.sh that always fails
TEST_TMP="$(mktemp -d)"
MOCK_CC_HOME="$TEST_TMP/cc-supervisor"
mkdir -p "$MOCK_CC_HOME/scripts/lib"
mkdir -p "$MOCK_CC_HOME/logs"
mkdir -p "$MOCK_CC_HOME/config"

# Copy real lib/log.sh so the script can source it
cp "$PROJECT_DIR/scripts/lib/log.sh" "$MOCK_CC_HOME/scripts/lib/log.sh"

# Create a mock install-hooks.sh that always fails
cat > "$MOCK_CC_HOME/scripts/install-hooks.sh" << 'MOCK_INSTALL'
#!/usr/bin/env bash
echo "Simulated hook installation failure"
exit 1
MOCK_INSTALL
chmod +x "$MOCK_CC_HOME/scripts/install-hooks.sh"

# Create other required scripts (stubs that succeed)
for s in supervisor_run.sh cc_send.sh; do
  cat > "$MOCK_CC_HOME/scripts/$s" << 'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$MOCK_CC_HOME/scripts/$s"
done

# Create a minimal claude-hooks.json
echo '{"hooks":{}}' > "$MOCK_CC_HOME/config/claude-hooks.json"

# Create a real target project dir
TARGET_DIR="$TEST_TMP/target-project"
mkdir -p "$TARGET_DIR"

# S3-01: install-hooks.sh fails → cc-start exits with error (BUG-001)
RUN_EXIT=0
RUN_OUTPUT="$(CC_PROJECT_DIR="$MOCK_CC_HOME" \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="123456" \
  bash "$SCRIPT" "$TARGET_DIR" 2>&1)" || RUN_EXIT=$?
assert_exit_nonzero "S3-01: install-hooks failure → non-zero exit" "$RUN_EXIT"
assert_output_contains "S3-01b: install-hooks failure → 'Hook installation failed'" \
  "$RUN_OUTPUT" "Hook installation failed"

rm -rf "$TEST_TMP"

echo ""

# ── Results ───────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ $FAIL -eq 0 ]]
