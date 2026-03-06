#!/usr/bin/env bash
# test-real-claude-hook-session-end.sh - Verify real Claude Code triggers SessionEnd hook.
# Usage: ./scripts/test-real-claude-hook-session-end.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_DIR="${CC_PROJECT_DIR}/example-project"
OPENCLAW_STUB="${CC_PROJECT_DIR}/tests/fixtures/bin/openclaw"
SESSION_NAME="cc-supervise"
TEST_DIR="$(mktemp -d)"
HOME_DIR="${TEST_DIR}/home"
WORKDIR="${TEST_DIR}/example-project"
REAL_HOME="${HOME}"
LOG_DIR="${CC_PROJECT_DIR}/logs"
EVENTS_FILE="${LOG_DIR}/events.ndjson"
NOTIFY_QUEUE="${LOG_DIR}/notification.queue"
SUPERVISOR_LOG="${LOG_DIR}/supervisor.log"
OPENCLAW_STUB_LOG="${TEST_DIR}/openclaw.ndjson"
SESSION_ID="22222222-3333-4444-8555-666666666666"
START_TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

cleanup() {
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
  rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "SKIP: missing required command: $name"
    exit 0
  fi
}

seed_claude_state() {
  mkdir -p "$HOME_DIR/.claude"

  if [[ -f "$REAL_HOME/.claude.json" ]]; then
    cp "$REAL_HOME/.claude.json" "$HOME_DIR/.claude.json"
  fi

  for file in settings.json stats-cache.json history.jsonl; do
    if [[ -f "$REAL_HOME/.claude/$file" ]]; then
      cp "$REAL_HOME/.claude/$file" "$HOME_DIR/.claude/$file"
    fi
  done
}

prepare_claude_session() {
  local timeout="${1:-60}"
  local deadline=$(( $(date +%s) + timeout ))
  local trust_handled=false
  local theme_handled=false

  while (( $(date +%s) < deadline )); do
    local pane
    pane="$(tmux capture-pane -t "$SESSION_NAME" -p 2>/dev/null || true)"

    if [[ "$trust_handled" == "false" ]] && printf '%s' "$pane" | grep -qiE 'trust this folder|not trusted|Trust folder'; then
      echo "Info: trust prompt detected, confirming default option"
      bash "${CC_PROJECT_DIR}/scripts/cc_send.sh" --key Enter >/dev/null
      trust_handled=true
      sleep 2
      continue
    fi

    if [[ "$theme_handled" == "false" ]] && printf '%s' "$pane" | grep -q 'Choose the text style'; then
      echo "Info: theme prompt detected, confirming default option"
      bash "${CC_PROJECT_DIR}/scripts/cc_send.sh" --key Enter >/dev/null
      theme_handled=true
      sleep 2
      continue
    fi

    if printf '%s' "$pane" | grep -q 'Select login method'; then
      echo "SKIP: Claude login prompt detected in isolated HOME"
      return 2
    fi

    if printf '%s' "$pane" | grep -qE '^[[:space:]]*>|❯|claude>|Human:|Press Enter'; then
      return 0
    fi

    sleep 1
  done

  return 1
}

event_exists() {
  local event_type="$1"
  local since_ts="${2:-$START_TS}"
  if [[ -f "$EVENTS_FILE" ]] && jq -e --arg since "$since_ts" --arg event_type "$event_type" \
    'select(.ts >= $since and .event_type == $event_type)' \
    "$EVENTS_FILE" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

wait_for_event() {
  local event_type="$1"
  local timeout="${2:-90}"
  local since_ts="${3:-$START_TS}"
  local deadline=$(( $(date +%s) + timeout ))

  while (( $(date +%s) < deadline )); do
    if event_exists "$event_type" "$since_ts"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

wait_for_stub_message() {
  local pattern="$1"
  local timeout="${2:-30}"
  local deadline=$(( $(date +%s) + timeout ))

  while (( $(date +%s) < deadline )); do
    if [[ -f "$OPENCLAW_STUB_LOG" ]] && jq -e --arg pattern "$pattern" '
      select(.subcommand == "agent")
      | select((.args | index("--message")) != null)
      | select(.args[(.args | index("--message")) + 1] | contains($pattern))
    ' "$OPENCLAW_STUB_LOG" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

assert_json_value() {
  local description="$1"
  local filter="$2"
  local expected="$3"
  local file="$4"
  local actual

  actual="$(jq -r "$filter" "$file")"
  if [[ "$actual" == "$expected" ]]; then
    echo "✓ PASS: $description"
  else
    echo "✗ FAIL: $description"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    exit 1
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Real Claude Hook SessionEnd"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

require_cmd jq
require_cmd tmux
require_cmd claude
require_cmd rsync

if [[ ! -x "$OPENCLAW_STUB" ]]; then
  echo "✗ FAIL: openclaw stub missing or not executable: $OPENCLAW_STUB"
  exit 1
fi

mkdir -p "$HOME_DIR"
seed_claude_state
rsync -a "$FIXTURE_DIR/" "$WORKDIR/"

rm -f "$EVENTS_FILE" "$NOTIFY_QUEUE" "$SUPERVISOR_LOG"
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

PATH_WITH_STUB="$(dirname "$OPENCLAW_STUB"):$PATH"

CC_PROJECT_DIR="$CC_PROJECT_DIR" \
CLAUDE_WORKDIR="$WORKDIR" \
HOME="$HOME_DIR" \
PATH="$PATH_WITH_STUB" \
OPENCLAW_BIN="$OPENCLAW_STUB" \
OPENCLAW_STUB_LOG="$OPENCLAW_STUB_LOG" \
OPENCLAW_SESSION_ID="$SESSION_ID" \
OPENCLAW_AGENT_ID="ruyi" \
OPENCLAW_CHANNEL="discord" \
OPENCLAW_TARGET="channel:test-session-end" \
bash "${CC_PROJECT_DIR}/scripts/install-hooks.sh" >/dev/null

CC_PROJECT_DIR="$CC_PROJECT_DIR" \
CLAUDE_WORKDIR="$WORKDIR" \
HOME="$HOME_DIR" \
PATH="$PATH_WITH_STUB" \
OPENCLAW_BIN="$OPENCLAW_STUB" \
OPENCLAW_STUB_LOG="$OPENCLAW_STUB_LOG" \
OPENCLAW_SESSION_ID="$SESSION_ID" \
OPENCLAW_AGENT_ID="ruyi" \
OPENCLAW_CHANNEL="discord" \
OPENCLAW_TARGET="channel:test-session-end" \
CC_POLL_INTERVAL=0 \
CC_TIMEOUT=300 \
bash "${CC_PROJECT_DIR}/scripts/supervisor_run.sh" >/dev/null

prepare_result=0
set +e
prepare_claude_session 45
prepare_result=$?
set -e

if [[ "$prepare_result" -eq 2 ]]; then
  exit 0
fi

if [[ "$prepare_result" -ne 0 ]]; then
  echo "✗ FAIL: Claude Code did not become ready"
  tmux capture-pane -t "$SESSION_NAME" -p 2>/dev/null || true
  exit 1
fi

TEST_PROMPT=$'Read app.txt and respond with exactly one line:\nHOOK_FIXTURE_OK\nAfter replying, stay in the session and wait for more instructions.'

CC_PROJECT_DIR="$CC_PROJECT_DIR" \
HOME="$HOME_DIR" \
PATH="$PATH_WITH_STUB" \
bash "${CC_PROJECT_DIR}/scripts/cc_send.sh" "$TEST_PROMPT" >/dev/null

if ! wait_for_event "Stop" 120; then
  echo "✗ FAIL: Stop event not found before exit step"
  echo ""
  echo "Recent pane:"
  tmux capture-pane -t "$SESSION_NAME" -p -S -30 2>/dev/null || true
  echo ""
  echo "Recent events:"
  tail -5 "$EVENTS_FILE" 2>/dev/null || true
  exit 1
fi

STOP_TS="$(jq -r --arg since "$START_TS" 'select(.ts >= $since and .event_type == "Stop") | .ts' \
  "$EVENTS_FILE" | tail -1)"

set +e
CC_PROJECT_DIR="$CC_PROJECT_DIR" \
HOME="$HOME_DIR" \
PATH="$PATH_WITH_STUB" \
bash "${CC_PROJECT_DIR}/scripts/cc_send.sh" "/exit" >/dev/null
set -e

if ! wait_for_event "SessionEnd" 60 "$STOP_TS"; then
  echo "✗ FAIL: SessionEnd event not found in logs/events.ndjson"
  echo ""
  echo "Recent pane:"
  tmux capture-pane -t "$SESSION_NAME" -p -S -30 2>/dev/null || true
  echo ""
  echo "Recent events:"
  tail -5 "$EVENTS_FILE" 2>/dev/null || true
  exit 1
fi

SESSION_END_EVENT_FILE="${TEST_DIR}/session-end-event.json"
jq -c --arg since "$STOP_TS" 'select(.ts >= $since and .event_type == "SessionEnd")' \
  "$EVENTS_FILE" | tail -1 > "$SESSION_END_EVENT_FILE"

assert_json_value "SessionEnd event_type recorded" '.event_type' 'SessionEnd' "$SESSION_END_EVENT_FILE"
assert_json_value "SessionEnd event_id present" 'if (.event_id | length) > 0 then "yes" else "no" end' 'yes' "$SESSION_END_EVENT_FILE"
assert_json_value "SessionEnd summary present" 'if (.summary | length) > 0 then "yes" else "no" end' 'yes' "$SESSION_END_EVENT_FILE"

if [[ ! -f "$OPENCLAW_STUB_LOG" ]]; then
  echo "✗ FAIL: openclaw stub was not invoked"
  exit 1
fi

OPENCLAW_CALL_FILE="${TEST_DIR}/openclaw-session-end-call.json"
if ! wait_for_stub_message "SessionEnd" 45; then
  echo "✗ FAIL: SessionEnd notification did not reach openclaw stub"
  cat "$OPENCLAW_STUB_LOG"
  exit 1
fi

jq -c '
  select(.subcommand == "agent")
  | select((.args | index("--message")) != null)
  | select(.args[(.args | index("--message")) + 1] | contains("SessionEnd"))
' "$OPENCLAW_STUB_LOG" | tail -1 > "$OPENCLAW_CALL_FILE"

if [[ ! -s "$OPENCLAW_CALL_FILE" ]]; then
  echo "✗ FAIL: SessionEnd notification did not reach openclaw stub"
  cat "$OPENCLAW_STUB_LOG"
  exit 1
fi

assert_json_value "SessionEnd notification uses agent subcommand" '.subcommand' 'agent' "$OPENCLAW_CALL_FILE"
assert_json_value "SessionEnd notification includes --session-id" 'if (.args | index("--session-id")) != null then "yes" else "no" end' 'yes' "$OPENCLAW_CALL_FILE"
assert_json_value "SessionEnd notification includes --deliver" 'if (.args | index("--deliver")) != null then "yes" else "no" end' 'yes' "$OPENCLAW_CALL_FILE"
assert_json_value "SessionEnd notification routes to discord" 'if (.args | index("--reply-channel")) != null then .args[(.args | index("--reply-channel")) + 1] else "" end' 'discord' "$OPENCLAW_CALL_FILE"
assert_json_value "SessionEnd notification includes cc-supervisor marker" 'if (.args | index("--message")) != null and (.args[(.args | index("--message")) + 1] | contains("[cc-supervisor]")) then "yes" else "no" end' 'yes' "$OPENCLAW_CALL_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Real Claude SessionEnd hook test passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
