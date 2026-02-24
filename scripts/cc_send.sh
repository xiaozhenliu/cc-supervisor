#!/usr/bin/env bash
# cc_send.sh — Send input to Claude Code running in the tmux session.
#
# Usage:
#   cc_send.sh "text"           — type text and press Enter
#   cc_send.sh --key Up         — send a special key (no Enter)
#   cc_send.sh --key Down
#   cc_send.sh --key Enter
#   cc_send.sh --key 1          — send a single character (no Enter)
#
# Special key names (passed to tmux send-keys):
#   Up, Down, Left, Right, Enter, Escape, Tab, Space, BSpace
#   Any single character: y, n, 1, 2, 3, q, etc.

set -euo pipefail

SESSION_NAME="cc-supervise"

source "$(dirname "$0")/lib/log.sh"

# ── Parse arguments ───────────────────────────────────────────────────────────
MODE="text"
INPUT=""

if [[ $# -lt 1 ]]; then
  log_error "Usage: $0 <text>  OR  $0 --key <keyname>"
  exit 1
fi

if [[ "$1" == "--key" ]]; then
  if [[ $# -lt 2 ]]; then
    log_error "Usage: $0 --key <keyname>"
    exit 1
  fi
  MODE="key"
  INPUT="$2"
else
  MODE="text"
  INPUT="$1"
fi

# ── Verify the target session exists ──────────────────────────────────────────
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  log_error "tmux session '$SESSION_NAME' not found. Run supervisor_run.sh first."
  exit 1
fi

# ── Send input ────────────────────────────────────────────────────────────────
if [[ "$MODE" == "text" ]]; then
  # Send text literally, then Enter separately (handles special characters)
  tmux send-keys -t "$SESSION_NAME" -l "$INPUT"
  tmux send-keys -t "$SESSION_NAME" Enter
  log_info "Sent text to '$SESSION_NAME': ${INPUT:0:120}$([ ${#INPUT} -gt 120 ] && echo '...')"
else
  # Send special key by name (no -l flag, no Enter)
  tmux send-keys -t "$SESSION_NAME" "$INPUT"
  log_info "Sent key to '$SESSION_NAME': $INPUT"
fi
