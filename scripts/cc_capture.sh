#!/usr/bin/env bash
# cc_capture.sh — Snapshot recent output from the Claude Code tmux pane.
# Usage: ./scripts/cc_capture.sh [--tail N]
#   --tail N   Number of lines to capture (default: 50)

set -euo pipefail

SESSION_NAME="cc-supervise"
TAIL_LINES=50

source "$(dirname "$0")/lib/log.sh"

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tail)
      TAIL_LINES="${2:?'--tail requires a number'}"
      shift 2
      ;;
    *)
      log_error "Unknown argument: $1. Usage: $0 [--tail N]"
      exit 1
      ;;
  esac
done

# ── Verify the target session exists ──────────────────────────────────────────
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  log_error "tmux session '$SESSION_NAME' not found"
  exit 1
fi

# ── Capture and output ────────────────────────────────────────────────────────
# -p prints to stdout; -S specifies start line (negative = from bottom of history)
log_info "Capturing last $TAIL_LINES lines from '$SESSION_NAME'"
tmux capture-pane -t "$SESSION_NAME" -p -S "-${TAIL_LINES}"
