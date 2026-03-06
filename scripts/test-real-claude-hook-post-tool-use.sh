#!/usr/bin/env bash
# test-real-claude-hook-post-tool-use.sh - Verify real Claude Code triggers PostToolUse hook on successful tool use.
# Usage: ./scripts/test-real-claude-hook-post-tool-use.sh

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
SESSION_ID="99999999-4444-4555-8666-aaaaaaaaaaaa"
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

wait_for_event() {
  local event_type="$1"
  local timeout="${2:-60}"
  local deadline=$(( $(date +%s) + timeout ))

  while (( $(date +%s) < deadline )); do
    if [[ -f "$EVENTS_FILE" ]] && jq -e --arg since "$START_TS" --arg event_type "$event_type" \
      'select(.ts >= $since and .event_type == $event_type)' \
      "$EVENTS_FILE" >/dev/null 2>&1; then
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
echo "Testing Real Claude Hook PostToolUse"
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
OPENCLAW_TARGET="channel:test-post-tool-use" \
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
OPENCLAW_TARGET="channel:test-post-tool-use" \
CC_MODE=auto \
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

CC_PROJECT_DIR="$CC_PROJECT_DIR" \
HOME="$HOME_DIR" \
PATH="$PATH_WITH_STUB" \
bash "${CC_PROJECT_DIR}/scripts/cc_send.sh" $'Use Bash to run this exact command and do not retry:\npwd' >/dev/null

if ! wait_for_event "PostToolUse" 60; then
  echo "✗ FAIL: PostToolUse event not found in logs/events.ndjson"
  echo ""
  echo "Recent pane:"
  tmux capture-pane -t "$SESSION_NAME" -p -S -40 2>/dev/null || true
  echo ""
  echo "Recent events:"
  tail -10 "$EVENTS_FILE" 2>/dev/null || true
  exit 1
fi

POST_TOOL_EVENT_FILE="${TEST_DIR}/post-tool-use-event.json"
jq -c --arg since "$START_TS" 'select(.ts >= $since and .event_type == "PostToolUse")' \
  "$EVENTS_FILE" | tail -1 > "$POST_TOOL_EVENT_FILE"

assert_json_value "PostToolUse event_type recorded" '.event_type' 'PostToolUse' "$POST_TOOL_EVENT_FILE"
assert_json_value "PostToolUse event_id present" 'if (.event_id | length) > 0 then "yes" else "no" end' 'yes' "$POST_TOOL_EVENT_FILE"
assert_json_value "PostToolUse tool_name recorded" '.tool_name' 'Bash' "$POST_TOOL_EVENT_FILE"
assert_json_value "PostToolUse summary records Bash tool" '.summary' 'Tool: Bash' "$POST_TOOL_EVENT_FILE"

if [[ -f "$OPENCLAW_STUB_LOG" ]] && jq -e '
  select(.subcommand == "agent")
  | select((.args | index("--message")) != null)
  | select(.args[(.args | index("--message")) + 1] | contains("PostToolUse"))
' "$OPENCLAW_STUB_LOG" >/dev/null 2>&1; then
  echo "✗ FAIL: PostToolUse unexpectedly triggered openclaw notification"
  cat "$OPENCLAW_STUB_LOG"
  exit 1
fi

echo "✓ PASS: PostToolUse remains log-only (no openclaw notification)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Real Claude PostToolUse hook test passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
