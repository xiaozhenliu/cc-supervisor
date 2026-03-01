#!/usr/bin/env bash
# cc_capture.sh — Snapshot recent output from the Claude Code tmux pane.
# Usage: ./scripts/cc_capture.sh [--tail N] [--grep PATTERN]
#   --tail N          Number of lines to capture (default: 50)
#   --grep PATTERN    Filter output with grep -iE (case-insensitive extended regex)

set -euo pipefail

SESSION_NAME="cc-supervise"
TAIL_LINES=50
GREP_PATTERN=""

source "$(dirname "$0")/lib/log.sh"

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tail)
      TAIL_LINES="${2:?'--tail requires a number'}"
      shift 2
      ;;
    --grep)
      GREP_PATTERN="${2:?'--grep requires a pattern'}"
      shift 2
      ;;
    *)
      log_error "Unknown argument: $1. Usage: $0 [--tail N] [--grep PATTERN]"
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
if [[ -n "$GREP_PATTERN" ]]; then
  tmux capture-pane -t "$SESSION_NAME" -p -S "-${TAIL_LINES}" | grep -iE "$GREP_PATTERN" || true
else
  tmux capture-pane -t "$SESSION_NAME" -p -S "-${TAIL_LINES}"
fi
