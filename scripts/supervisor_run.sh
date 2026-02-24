#!/usr/bin/env bash
# supervisor_run.sh — Create or reuse tmux session for Claude Code interactive mode.
#
# Usage: ./scripts/supervisor_run.sh
#
# Environment variables:
#   CC_PROJECT_DIR   Path to this cc-supervisor repo (scripts, logs, config).
#                    Defaults to the repo root resolved from this script's path.
#   CLAUDE_WORKDIR   Directory where Claude Code starts working.
#                    Defaults to CC_PROJECT_DIR (single-project mode).
#                    Set this to supervise a different project:
#                      CLAUDE_WORKDIR=~/Projects/my-app ./scripts/supervisor_run.sh
#   CC_MODE          Supervision mode: relay (default) or autonomous.
#                    relay: notify on every key event, await human instruction
#                    autonomous: Stop carries ACTION_REQUIRED marker for OpenClaw self-driving

set -euo pipefail

SESSION_NAME="cc-supervise"
CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR

# CLAUDE_WORKDIR is where Claude Code actually runs. Defaults to CC_PROJECT_DIR
# so existing single-project setups require no changes.
CLAUDE_WORKDIR="${CLAUDE_WORKDIR:-$CC_PROJECT_DIR}"
export CLAUDE_WORKDIR

source "$(dirname "$0")/lib/log.sh"

# ── Ensure tmux is available ──────────────────────────────────────────────────
if ! command -v tmux &>/dev/null; then
  log_error "tmux is not installed"
  exit 1
fi

# ── Create or reuse session ───────────────────────────────────────────────────
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  log_info "Session '$SESSION_NAME' already exists. Attaching..."
  exec tmux attach-session -t "$SESSION_NAME"
fi

# Start a new detached session. Claude Code runs in CLAUDE_WORKDIR; the
# CC_PROJECT_DIR env var is also exported so Hook callbacks can find logs/.
tmux new-session -d -s "$SESSION_NAME" -c "$CLAUDE_WORKDIR" \
  -e "CC_PROJECT_DIR=$CC_PROJECT_DIR" \
  -e "CLAUDE_WORKDIR=$CLAUDE_WORKDIR" \
  -e "CC_MODE=${CC_MODE:-relay}"

# Give the shell a moment to initialize, then start Claude Code interactive mode.
sleep 0.3
tmux send-keys -t "$SESSION_NAME" "claude" Enter

# Detect the directory trust prompt that Claude Code shows for new/untrusted directories.
# Poll pane content for up to 8 seconds; if the prompt appears, ask the operator explicitly.
TRUST_DETECTED=false
for _i in $(seq 1 16); do
  sleep 0.5
  PANE_CONTENT=$(tmux capture-pane -t "$SESSION_NAME" -p 2>/dev/null || true)
  if echo "$PANE_CONTENT" | grep -qiE "trust this folder|not trusted|Trust folder"; then
    TRUST_DETECTED=true
    break
  fi
  # Stop polling once Claude Code's REPL prompt is visible (already trusted)
  if echo "$PANE_CONTENT" | grep -qE "^\s*>|✓|claude>"; then
    break
  fi
done

if [[ "$TRUST_DETECTED" == true ]]; then
  log_warn "Claude Code is requesting trust for directory: $CLAUDE_WORKDIR"
  if [[ -t 0 ]]; then
    # Interactive terminal: ask the operator before forwarding any answer
    read -r -p "[supervisor] Trust this directory? (y/N): " USER_TRUST
    if [[ "$USER_TRUST" =~ ^[Yy]$ ]]; then
      tmux send-keys -t "$SESSION_NAME" "y" Enter
      log_info "Directory trust confirmed by operator."
    else
      log_warn "Directory not trusted by operator. Attach to handle manually: tmux attach -t $SESSION_NAME"
    fi
  else
    # Non-interactive (piped/CI): refuse silently and let the operator handle it
    log_warn "Non-interactive mode: cannot confirm trust. Attach to handle manually: tmux attach -t $SESSION_NAME"
  fi
fi

log_info "Session '$SESSION_NAME' created. Claude Code working in $CLAUDE_WORKDIR"
log_info "Supervisor home (logs/config): $CC_PROJECT_DIR"
log_info "Supervision mode: CC_MODE=${CC_MODE:-relay}"
echo "Attach with: tmux attach -t $SESSION_NAME"

# ── Start watchdog in background ──────────────────────────────────────────────
WATCHDOG="${CC_PROJECT_DIR}/scripts/cc-watchdog.sh"
PID_FILE="${CC_PROJECT_DIR}/logs/watchdog.pid"

if [[ -f "$WATCHDOG" ]]; then
  # Kill any previously running watchdog
  if [[ -f "$PID_FILE" ]]; then
    OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
      kill "$OLD_PID" 2>/dev/null || true
      log_info "Stopped previous watchdog (PID=$OLD_PID)"
    fi
    rm -f "$PID_FILE"
  fi
  CC_PROJECT_DIR="$CC_PROJECT_DIR" CC_TIMEOUT="${CC_TIMEOUT:-1800}" \
    bash "$WATCHDOG" &
  log_info "Watchdog started in background (timeout=${CC_TIMEOUT:-1800}s)"
fi
