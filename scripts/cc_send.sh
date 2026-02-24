#!/usr/bin/env bash
# cc_send.sh — Send text to Claude Code running in the tmux session.
# Usage: ./scripts/cc_send.sh "your prompt text here"
#
# Text and Enter are sent separately to avoid special-character issues.

set -euo pipefail

SESSION_NAME="cc-supervise"

source "$(dirname "$0")/lib/log.sh"

# ── Validate arguments ────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  log_error "Missing argument. Usage: $0 <text>"
  exit 1
fi

TEXT="$1"

# ── Verify the target session exists ──────────────────────────────────────────
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  log_error "tmux session '$SESSION_NAME' not found. Run supervisor_run.sh first."
  exit 1
fi

# ── Send text, then Enter (separated to handle special characters) ────────────
tmux send-keys -t "$SESSION_NAME" -l "$TEXT"
tmux send-keys -t "$SESSION_NAME" Enter

log_info "Sent to '$SESSION_NAME': ${TEXT:0:120}$([ ${#TEXT} -gt 120 ] && echo '...')"
