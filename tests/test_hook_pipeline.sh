#!/usr/bin/env bash
# test_hook_pipeline.sh — Layer 2 tests for on-cc-event.sh Hook pipeline.
#
# Uses a mock openclaw binary to intercept calls and verify arguments.
# No real OpenClaw or Claude Code process needed.
#
# Usage: ./tests/test_hook_pipeline.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPT="$PROJECT_DIR/scripts/on-cc-event.sh"
FIXTURES="$TESTS_DIR/fixtures"
MOCK_DIR="$TESTS_DIR/mock"  # absolute path — must precede /opt/homebrew/bin in PATH

PASS=0
FAIL=0

# ── Test state ────────────────────────────────────────────────────────────────

MOCK_CALL_LOG=""
TEST_EVENTS_FILE=""
TEST_QUEUE_FILE=""
TEST_LOG_DIR=""

# ── Helpers ───────────────────────────────────────────────────────────────────

# setup: initializes global test state into a fresh temp dir.
# Call directly (not via command substitution) so globals are set in current shell.
setup() {
  TEST_TMP="$(mktemp -d)"
  MOCK_CALL_LOG="$TEST_TMP/mock_calls.log"
  TEST_LOG_DIR="$TEST_TMP/logs"
  TEST_EVENTS_FILE="$TEST_LOG_DIR/events.ndjson"
  TEST_QUEUE_FILE="$TEST_LOG_DIR/notification.queue"
  mkdir -p "$TEST_LOG_DIR"
  touch "$MOCK_CALL_LOG"
}

cleanup() {
  rm -rf "${TEST_TMP:-}"
  TEST_TMP=""
}

# Run on-cc-event.sh with a fixture file as stdin.
# CC_PROJECT_DIR is set to the temp dir so logs go there, not the real project.
# MOCK_DIR is prepended to PATH so mock/openclaw intercepts all openclaw calls.
# Args: fixture_path [extra env vars as KEY=VALUE ...]
run_hook() {
  local fixture="$1"; shift

  # Prepend MOCK_DIR with an explicit clean PATH so mock/openclaw always wins
  # over any real openclaw binary (e.g. /opt/homebrew/bin/openclaw).
  env \
    PATH="$MOCK_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    CC_PROJECT_DIR="$TEST_TMP" \
    MOCK_CALL_LOG="$MOCK_CALL_LOG" \
    "$@" \
    bash "$SCRIPT" < "$fixture" 2>/dev/null || true
}

assert_called() {
  local label="$1"
  if [[ -s "$MOCK_CALL_LOG" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — openclaw was not called"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_called() {
  local label="$1"
  if [[ ! -s "$MOCK_CALL_LOG" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — openclaw was called unexpectedly:"
    cat "$MOCK_CALL_LOG" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

assert_arg_contains() {
  local label="$1" pattern="$2"
  # Collapse newlines so multi-line messages (e.g. relay Stop) are searchable.
  # Use grep -F -e to handle patterns starting with '--' on macOS grep.
  local flat
  flat="$(tr '\n' ' ' < "$MOCK_CALL_LOG" 2>/dev/null)"
  if echo "$flat" | grep -qF -e "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — expected pattern: '$pattern'"
    echo "    actual call log:"
    cat "$MOCK_CALL_LOG" 2>/dev/null | sed 's/^/      /' || echo "      (empty)"
    FAIL=$((FAIL + 1))
  fi
}

assert_arg_not_contains() {
  local label="$1" pattern="$2"
  local flat
  flat="$(tr '\n' ' ' < "$MOCK_CALL_LOG" 2>/dev/null)"
  if ! echo "$flat" | grep -qF -e "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — unexpected pattern found: '$pattern'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local label="$1" file="$2" pattern="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — '$pattern' not found in $file"
    cat "$file" 2>/dev/null | sed 's/^/    /' || echo "    (file missing)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists_or_empty() {
  local label="$1" file="$2"
  if [[ ! -s "$file" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — file exists and is non-empty: $file"
    FAIL=$((FAIL + 1))
  fi
}

reset_log() {
  > "$MOCK_CALL_LOG"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

echo "=== Layer 2: Hook Pipeline Tests ==="
echo ""

# ── H1: Stop event ────────────────────────────────────────────────────────────
echo "── H1: Stop event ────────────────────────────────────────────────────────"

setup

run_hook "$FIXTURES/stop_event.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" || true

assert_called        "H1-01: relay Stop triggers openclaw"
assert_arg_contains  "H1-02: relay Stop message format" "[cc-supervisor][relay] Stop"
assert_arg_contains  "H1-03: --session-id passed correctly" "--session-id 11b7b38b-a9d6-460d-aa43-f704eda80dfb"
assert_arg_not_contains "H1-04: no --deliver when OPENCLAW_TARGET empty" "--deliver"

cleanup

# ── H1-05: auto mode message format ───────────────────────────────────────────
setup

run_hook "$FIXTURES/stop_event.json" \
  CC_MODE=auto \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" || true

assert_arg_contains "H1-05: auto Stop message format" "[cc-supervisor][auto] Stop"

cleanup

# ── H1-06: OPENCLAW_TARGET set → --deliver --reply-to appended ────────────────
setup

run_hook "$FIXTURES/stop_event.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="1466784529527214122" || true

assert_arg_contains "H1-06: --deliver present when OPENCLAW_TARGET set" "--deliver"
assert_arg_contains "H1-07: --reply-to contains target ID" "--reply-to 1466784529527214122"

cleanup

# ── H1-08: no OPENCLAW_SESSION_ID → enqueue, not call openclaw ───────────────
setup

run_hook "$FIXTURES/stop_event.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="" \
  OPENCLAW_TARGET="" || true

assert_not_called   "H1-08: no SESSION_ID → openclaw not called"
assert_file_contains "H1-09: no SESSION_ID → enqueued to notification.queue" \
  "$TEST_QUEUE_FILE" "cc-supervisor"

cleanup

echo ""

# ── H2: PostToolUse errors ────────────────────────────────────────────────────
echo "── H2: PostToolUse errors ────────────────────────────────────────────────"

setup

run_hook "$FIXTURES/posttooluse_error_403.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" || true

assert_called       "H2-01: tool error triggers openclaw"
assert_arg_contains "H2-02: HTTP 403 extracted in message" "API error 403"
assert_arg_contains "H2-03: tool name included in message" "WebFetch"

cleanup

setup

run_hook "$FIXTURES/posttooluse_error_no_http.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" || true

assert_called       "H2-04: non-HTTP tool error triggers openclaw"
assert_arg_contains "H2-05: non-HTTP error uses 'Tool error' prefix" "Tool error"

cleanup

setup

run_hook "$FIXTURES/posttooluse_success.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" || true

assert_not_called   "H2-06: tool success does not trigger openclaw"

cleanup

echo ""

# ── H3: Notification event ────────────────────────────────────────────────────
echo "── H3: Notification event ────────────────────────────────────────────────"

setup

run_hook "$FIXTURES/notification_event.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" || true

assert_called       "H3-01: Notification triggers openclaw"
assert_arg_contains "H3-02: Notification message content passed through" "Claude needs your attention"

cleanup

echo ""

# ── H4: SessionEnd event ──────────────────────────────────────────────────────
echo "── H4: SessionEnd event ──────────────────────────────────────────────────"

setup

run_hook "$FIXTURES/session_end_event.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" || true

assert_called       "H4-01: SessionEnd triggers openclaw"
assert_arg_contains "H4-02: SessionEnd message contains session_id" "11b7b38b-a9d6-460d-aa43-f704eda80dfb"

cleanup

echo ""

# ── H5: Deduplication ─────────────────────────────────────────────────────────
echo "── H5: Deduplication ─────────────────────────────────────────────────────"

setup

# First call — openclaw should be called
run_hook "$FIXTURES/stop_event.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET=""

FIRST_NONEMPTY=$([[ -s "$MOCK_CALL_LOG" ]] && echo "yes" || echo "no")

# Second call with same event_id — dedup should skip openclaw
run_hook "$FIXTURES/stop_event.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET=""

# After dedup, events.ndjson should have exactly 1 record (second call skipped)
EVENTS_COUNT="$(wc -l < "$TEST_EVENTS_FILE" | tr -d ' ')"

if [[ "$FIRST_NONEMPTY" == "yes" && "$EVENTS_COUNT" == "1" ]]; then
  echo "  PASS: H5-01: first call triggers openclaw; duplicate event_id skipped"
  PASS=$((PASS + 1))
else
  echo "  FAIL: H5-01: first_called=$FIRST_NONEMPTY events_after_dedup=$EVENTS_COUNT (expected yes/1)"
  FAIL=$((FAIL + 1))
fi

cleanup

echo ""

# ── H6: events.ndjson logging ─────────────────────────────────────────────────
echo "── H6: events.ndjson logging ─────────────────────────────────────────────"

setup

run_hook "$FIXTURES/stop_event.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" || true

if [[ -s "$TEST_EVENTS_FILE" ]]; then
  echo "  PASS: H6-01: event written to events.ndjson"
  PASS=$((PASS + 1))
else
  echo "  FAIL: H6-01: events.ndjson missing or empty"
  FAIL=$((FAIL + 1))
fi

LAST_LINE="$(tail -1 "$TEST_EVENTS_FILE" 2>/dev/null || true)"
if echo "$LAST_LINE" | jq . >/dev/null 2>&1; then
  echo "  PASS: H6-02: log line is valid JSON"
  PASS=$((PASS + 1))
else
  echo "  FAIL: H6-02: log line is not valid JSON: $LAST_LINE"
  FAIL=$((FAIL + 1))
fi

for field in ts event_type session_id event_id summary; do
  if echo "$LAST_LINE" | jq -e ".$field" >/dev/null 2>&1; then
    echo "  PASS: H6-03.$field: field present in log"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: H6-03.$field: field missing from log"
    FAIL=$((FAIL + 1))
  fi
done

cleanup

echo ""

# ── H7: openclaw failure → enqueue ────────────────────────────────────────────
echo "── H7: openclaw failure → enqueue ───────────────────────────────────────"

setup

MOCK_OPENCLAW_FAIL=1 run_hook "$FIXTURES/stop_event.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" || true

assert_file_contains "H7-01: openclaw failure enqueues to notification.queue" \
  "$TEST_QUEUE_FILE" "cc-supervisor"

# Verify queue format: timestamp|channel|account|target|event_type|message
# The message field may contain newlines, so count pipes in the whole file
PIPE_COUNT="$(tr -cd '|' < "$TEST_QUEUE_FILE" 2>/dev/null | wc -c | tr -d ' ')"
if [[ "$PIPE_COUNT" -ge 5 ]]; then
  echo "  PASS: H7-02: queue record has correct pipe-delimited format (pipes=$PIPE_COUNT)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: H7-02: queue record has wrong format (pipes=$PIPE_COUNT)"
  cat "$TEST_QUEUE_FILE" 2>/dev/null | sed 's/^/    /' || echo "    (missing)"
  FAIL=$((FAIL + 1))
fi

cleanup

# ── H8: events.ndjson write failure → CRITICAL alert (BUG-004) ───────────────
echo "── H8: events.ndjson write failure (BUG-004) ────────────────────────────"

setup

# Make the logs dir read-only so jq cannot write to events.ndjson
chmod 555 "$TEST_LOG_DIR"

MOCK_OPENCLAW_FAIL=0 run_hook "$FIXTURES/stop_event.json" \
  CC_MODE=relay \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" || true

# Restore permissions so cleanup() can delete the temp dir
chmod 755 "$TEST_LOG_DIR"

# The CRITICAL alert should be queued (events.ndjson dir was unwritable,
# but notification.queue is in the same dir — so we check the queue file
# was created in the parent tmp dir instead)
# Actually: CC_PROJECT_DIR=$TEST_TMP, queue goes to $TEST_TMP/logs/notification.queue
# Since $TEST_TMP/logs is chmod 555, the queue write also fails silently.
# What we CAN verify: the hook exits non-zero (no openclaw call for the event itself)
assert_not_called "H8-01: write failure → event not logged, openclaw not called for event" || true

cleanup

# H8-02: verify hook exits non-zero when write fails
setup
chmod 555 "$TEST_LOG_DIR"

EXIT_CODE=0
env \
  PATH="$MOCK_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  CC_PROJECT_DIR="$TEST_TMP" \
  MOCK_CALL_LOG="$MOCK_CALL_LOG" \
  OPENCLAW_SESSION_ID="11b7b38b-a9d6-460d-aa43-f704eda80dfb" \
  OPENCLAW_TARGET="" \
  CC_MODE=relay \
  bash "$SCRIPT" < "$FIXTURES/stop_event.json" 2>/dev/null || EXIT_CODE=$?

chmod 755 "$TEST_LOG_DIR"

if [[ "$EXIT_CODE" -ne 0 ]]; then
  echo "  PASS: H8-02: write failure → hook exits non-zero (exit=$EXIT_CODE)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: H8-02: write failure → expected non-zero exit, got 0"
  FAIL=$((FAIL + 1))
fi

cleanup

echo ""

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ $FAIL -eq 0 ]]
