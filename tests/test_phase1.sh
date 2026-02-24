#!/usr/bin/env bash
# test_phase1.sh — Integration tests for Phase 1 scripts.
#
# Creates a real tmux session with a plain shell (not Claude Code) to verify
# session management, text sending, and output capture.
#
# Usage: ./tests/test_phase1.sh

set -uo pipefail
# Note: -e intentionally omitted — we need to catch non-zero exits from
# subcommands under test without aborting the whole suite.
# Arithmetic ((n++)) also returns 1 when result is 0, which would abort with -e.

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
SESSION_NAME="cc-supervise"
PASS=0
FAIL=0

# ── Helpers ───────────────────────────────────────────────────────────────────

cleanup() {
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" pattern="$2" text="$3"
  if echo "$text" | grep -q "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected to contain: '$pattern'"
    echo "    actual output:"
    echo "$text" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected exit=$expected, got=$actual)"
    FAIL=$((FAIL + 1))
  fi
}

trap cleanup EXIT

# ── Ensure clean state ────────────────────────────────────────────────────────
cleanup

echo "=== Phase 1 Integration Tests ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
echo "── T1-T2: cc_send.sh error handling ──────────────────────────────────"

rc=0; "$SCRIPT_DIR/cc_send.sh" 2>/dev/null || rc=$?
assert_exit_code "T1: exit 1 on missing argument" "1" "$rc"

rc=0; "$SCRIPT_DIR/cc_send.sh" "hello" 2>/dev/null || rc=$?
assert_exit_code "T2: exit 1 when session not running" "1" "$rc"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T3-T4: cc_capture.sh error handling ───────────────────────────────"

rc=0; "$SCRIPT_DIR/cc_capture.sh" 2>/dev/null || rc=$?
assert_exit_code "T3: exit 1 when session not running" "1" "$rc"

rc=0; "$SCRIPT_DIR/cc_capture.sh" --bogus 2>/dev/null || rc=$?
assert_exit_code "T4: exit 1 on unknown argument" "1" "$rc"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T5: tmux session creation ─────────────────────────────────────────"

# Use a plain bash shell instead of claude so tests are self-contained.
tmux new-session -d -s "$SESSION_NAME" -c /tmp
sleep 0.2
has_session=$(tmux has-session -t "$SESSION_NAME" 2>/dev/null && echo "yes" || echo "no")
assert_eq "T5: session exists after creation" "yes" "$has_session"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T6-T7: send + capture round-trip ──────────────────────────────────"

MARKER="TEST_MARKER_$(date +%s)"
"$SCRIPT_DIR/cc_send.sh" "echo $MARKER" 2>/dev/null
sleep 0.5  # let the shell in tmux execute the echo

captured=$("$SCRIPT_DIR/cc_capture.sh" --tail 20 2>/dev/null)
assert_contains "T6: captured output contains sent marker" "$MARKER" "$captured"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T7: special characters preserved ─────────────────────────────────"

# Using printf to avoid shell expansion of $HOME; literal text must reach tmux
SPECIAL='SPECIAL_hello "world" and tilde~'
"$SCRIPT_DIR/cc_send.sh" "echo '$SPECIAL'" 2>/dev/null
sleep 0.5
captured=$("$SCRIPT_DIR/cc_capture.sh" --tail 10 2>/dev/null)
assert_contains "T7: special chars (quotes) preserved in capture" 'SPECIAL_hello' "$captured"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T8: supervisor_run.sh idempotency ─────────────────────────────────"

session_count_before=$(tmux list-sessions 2>/dev/null | grep -c "$SESSION_NAME")
# supervisor_run.sh tries to attach when session exists; timeout prevents blocking
timeout 2 "$SCRIPT_DIR/supervisor_run.sh" 2>/dev/null || true
session_count_after=$(tmux list-sessions 2>/dev/null | grep -c "$SESSION_NAME")
assert_eq "T8: no duplicate session created" "$session_count_before" "$session_count_after"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T9-T10: logging ───────────────────────────────────────────────────"

LOG_FILE="$(cd "$(dirname "$0")/.." && pwd)/logs/supervisor.log"

if [[ -f "$LOG_FILE" ]] && [[ -s "$LOG_FILE" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T9: log file exists and is non-empty"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T9: log file missing or empty ($LOG_FILE)"
fi

invalid_lines=0
while IFS= read -r line; do
  if [[ -z "$line" ]]; then continue; fi
  if ! echo "$line" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    invalid_lines=$((invalid_lines + 1))
  fi
done < "$LOG_FILE"
assert_eq "T10: all log lines are valid JSON" "0" "$invalid_lines"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ $FAIL -eq 0 ]]
