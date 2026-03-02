#!/usr/bin/env bash
# cc-start.sh — One-command startup for cc-supervisor.
#
# Replaces Phase 0–3.5 of SKILL.md. Handles:
#   1. Validate OPENCLAW_SESSION_ID (UUID format)
#   2. Check OPENCLAW_TARGET is set
#   3. Verify shell commands exist (cc-supervise, cc-send, cc-install-hooks)
#   4. Install hooks into target project
#   5. Start tmux session with all required env vars
#   6. Send hook verification test message
#   7. Wait up to 30s for [cc-supervisor] callback to confirm routing works
#
# Usage:
#   cc-start <project-dir> [relay|auto]
#
# Exit codes:
#   0  — session started and hook routing verified
#   1  — fatal error (printed to stdout for agent to read)
#   2  — hook verification timed out (session started but routing unconfirmed)

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR

source "${CC_PROJECT_DIR}/scripts/lib/log.sh"

# ── Args ──────────────────────────────────────────────────────────────────────

PROJECT_DIR="${1:-}"
CC_MODE="${2:-relay}"

# Backward compatibility: map old 'autonomous' to new 'auto'
if [[ "$CC_MODE" == "autonomous" ]]; then
  CC_MODE="auto"
fi

if [[ -z "$PROJECT_DIR" ]]; then
  echo "ERROR: project-dir required"
  echo "Usage: cc-start <project-dir> [relay|auto]"
  exit 1
fi

if [[ "$CC_MODE" != "relay" && "$CC_MODE" != "auto" ]]; then
  echo "ERROR: mode must be 'relay' or 'auto', got: $CC_MODE"
  exit 1
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: project-dir does not exist: $PROJECT_DIR"
  exit 1
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# ── Auto mode safety confirmation ────────────────────────────────────────────
# Auto mode skips ALL permission prompts (--dangerously-skip-permissions).
# Require explicit human confirmation before proceeding.
if [[ "$CC_MODE" == "auto" ]]; then
  echo ""
  echo "⚠⚠⚠  危险！你现在将进入全自动运行模式 ⚠⚠⚠"
  echo ""
  echo "  - 所有权限都会被自动批准（--dangerously-skip-permissions）"
  echo "  - Claude Code 将自主执行所有操作，包括文件修改、命令执行等"
  echo "  - 开始后无法随时停止！"
  echo ""
  if [[ -t 0 ]]; then
    read -r -p "要继续吗？(yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
      echo "已取消。"
      exit 0
    fi
    echo ""
  else
    echo "WARN: Non-interactive mode — auto mode confirmation skipped."
  fi
fi

# ── Step 1: Validate SESSION_ID ───────────────────────────────────────────────

echo "=== cc-start: Phase 0-3.5 automated startup ==="
echo ""
echo "[1/7] Validating OPENCLAW_SESSION_ID..."

# Use ensure-session-id.sh for robust validation and retrieval
ENSURE_SCRIPT="${CC_PROJECT_DIR}/scripts/ensure-session-id.sh"
if [ -f "$ENSURE_SCRIPT" ]; then
  if SESSION_ID_EXPORT=$(bash "$ENSURE_SCRIPT" 2>&1); then
    eval "$SESSION_ID_EXPORT"
    echo "  OK: $OPENCLAW_SESSION_ID"
  else
    echo "ERROR: Failed to ensure OPENCLAW_SESSION_ID:"
    echo "$SESSION_ID_EXPORT"
    echo ""
    echo "  If testing manually: export OPENCLAW_SESSION_ID=\$(uuidgen | tr '[:upper:]' '[:lower:]')"
    exit 1
  fi
else
  # Fallback to inline validation if ensure-session-id.sh not found
  SESSION_ID="${OPENCLAW_SESSION_ID:-}"

  if [[ -z "$SESSION_ID" ]]; then
    echo "ERROR: OPENCLAW_SESSION_ID is not set."
    echo "  This must be set automatically by the OpenClaw agent environment."
    echo "  If testing manually: export OPENCLAW_SESSION_ID=\$(uuidgen | tr '[:upper:]' '[:lower:]')"
    exit 1
  fi

  UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  if ! echo "$SESSION_ID" | grep -qE "$UUID_RE"; then
    echo "ERROR: OPENCLAW_SESSION_ID has invalid format: $SESSION_ID"
    echo "  Expected UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    echo "  Got routing-format string? That is a session KEY, not a session ID."
    exit 1
  fi

  echo "  OK: $SESSION_ID"
fi

# ── Step 2: Check OPENCLAW_TARGET ─────────────────────────────────────────────

echo ""
echo "[2/7] Checking notification routing vars..."

if [[ -z "${OPENCLAW_TARGET:-}" ]]; then
  echo "ERROR: OPENCLAW_TARGET is not set."
  echo "  Without it, all notifications route to webchat instead of Discord."
  echo "  Set it in ~/.zshrc: export OPENCLAW_TARGET=<your-discord-channel-id>"
  exit 1
fi

echo "  OPENCLAW_CHANNEL=${OPENCLAW_CHANNEL:-<unset>}"
echo "  OPENCLAW_TARGET=${OPENCLAW_TARGET}"

# ── Step 3: Verify scripts exist ──────────────────────────────────────────────

echo ""
echo "[3/7] Verifying scripts..."

MISSING=()
for script in scripts/supervisor_run.sh scripts/cc_send.sh scripts/install-hooks.sh; do
  if [[ ! -f "${CC_PROJECT_DIR}/${script}" ]]; then
    MISSING+=("$script")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "ERROR: Missing scripts in CC_PROJECT_DIR ($CC_PROJECT_DIR): ${MISSING[*]}"
  echo "  Is CC_SUPERVISOR_HOME set correctly?"
  exit 1
fi

echo "  OK: supervisor_run.sh, cc_send.sh, install-hooks.sh"

# ── Step 4: Install hooks ─────────────────────────────────────────────────────

echo ""
echo "[4/7] Installing hooks into $PROJECT_DIR..."

INSTALL_EXIT_FILE="$(mktemp)"
{ CC_PROJECT_DIR="$CC_PROJECT_DIR" CLAUDE_WORKDIR="$PROJECT_DIR" \
    bash "${CC_PROJECT_DIR}/scripts/install-hooks.sh" || echo $? > "$INSTALL_EXIT_FILE"; } \
  2>&1 | sed 's/^/  /'
INSTALL_EXIT="$(cat "$INSTALL_EXIT_FILE" 2>/dev/null || echo 0)"
rm -f "$INSTALL_EXIT_FILE"
if [[ "$INSTALL_EXIT" -ne 0 ]]; then
  echo "ERROR: Hook installation failed (exit $INSTALL_EXIT). Aborting."
  exit 1
fi

# Verify all 4 hook events are registered
HOOK_KEYS="$(jq -r '.hooks | keys | join(",")' \
  "$PROJECT_DIR/.claude/settings.local.json" 2>/dev/null || true)"

for event in Notification PostToolUse SessionEnd Stop; do
  if ! echo "$HOOK_KEYS" | grep -q "$event"; then
    echo "ERROR: Hook '$event' not found after install."
    echo "  Check: cat $PROJECT_DIR/.claude/settings.local.json | jq .hooks"
    exit 1
  fi
done

echo "  OK: Notification, PostToolUse, SessionEnd, Stop"

# ── Step 5: Start tmux session ────────────────────────────────────────────────

echo ""
echo "[5/7] Starting tmux session (mode=$CC_MODE)..."

# Kill stale session if it exists but Claude Code is not running
if tmux has-session -t cc-supervise 2>/dev/null; then
  log_info "Session cc-supervise already exists — reusing"
else
  OPENCLAW_SESSION_ID="$SESSION_ID" \
    OPENCLAW_CHANNEL="${OPENCLAW_CHANNEL:-}" \
    OPENCLAW_TARGET="${OPENCLAW_TARGET}" \
    CC_MODE="$CC_MODE" \
    CC_PROJECT_DIR="$CC_PROJECT_DIR" CLAUDE_WORKDIR="$PROJECT_DIR" \
    bash "${CC_PROJECT_DIR}/scripts/supervisor_run.sh"
fi

echo "  OK: tmux session cc-supervise running"
echo "  Observe: tmux attach -t cc-supervise"

# ── Step 6: Send hook verification message ────────────────────────────────────

echo ""
echo "[6/7] Waiting for Claude Code to initialize (up to 15s)..."
READY=false
for _i in $(seq 1 30); do
  sleep 0.5
  PANE="$(tmux capture-pane -t cc-supervise -p 2>/dev/null || true)"
  if echo "$PANE" | grep -qE "^\s*>|✓|claude>|Human:|Press Enter"; then
    READY=true; break
  fi
done
if [[ "$READY" == "false" ]]; then
  echo "  WARN: Claude Code may not be ready yet, proceeding anyway"
fi

echo "  Sending hook verification message..."
bash "${CC_PROJECT_DIR}/scripts/cc_send.sh" "Please respond with exactly: Hook test successful"

# ── Step 7: Wait for [cc-supervisor] callback ─────────────────────────────────

echo ""
echo "[7/7] Waiting for Hook callback (timeout: 30s)..."
echo "  Session ID to watch: $SESSION_ID"
echo ""

EVENTS_FILE="${CC_PROJECT_DIR}/logs/events.ndjson"
DEADLINE=$(( $(date +%s) + 30 ))
# Record timestamp before sending test message — only look for Stop events after this point
WAIT_START="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

while true; do
  NOW=$(date +%s)
  if (( NOW >= DEADLINE )); then
    echo "TIMEOUT: No Hook callback received within 30 seconds."
    echo ""
    echo "Diagnostics:"
    echo "  events.ndjson tail:"
    tail -3 "$EVENTS_FILE" 2>/dev/null | sed 's/^/    /' || echo "    (file missing)"
    echo "  notification.queue:"
    tail -3 "${CC_PROJECT_DIR}/logs/notification.queue" 2>/dev/null | sed 's/^/    /' || echo "    (empty)"
    echo ""
    echo "Next steps:"
    echo "  1. Run: echo \$OPENCLAW_SESSION_ID  — confirm UUID matches current session"
    echo "  2. Run: cc-flush-queue              — retry queued notifications"
    echo "  3. Check: cat $PROJECT_DIR/.claude/settings.local.json | jq .hooks"
    exit 2
  fi

  # Look for a Stop event logged after we sent the test message
  if [[ -f "$EVENTS_FILE" ]]; then
    NEW_STOP="$(jq -r --arg since "$WAIT_START" \
      'select(.event_type=="Stop" and .ts >= $since) | .ts' \
      "$EVENTS_FILE" 2>/dev/null | head -1 || true)"
    if [[ -n "$NEW_STOP" ]]; then
      echo "  Hook fired — Stop event logged at $NEW_STOP"
      break
    fi
  fi

  sleep 1
done

echo ""
echo "=== cc-start complete ==="
echo "  Project:    $PROJECT_DIR"
echo "  Mode:       $CC_MODE"
echo "  Session ID: $SESSION_ID"
echo ""
echo "Hook routing verified. Proceed to send the real task with:"
echo "  cc-send \"<your task>\""
