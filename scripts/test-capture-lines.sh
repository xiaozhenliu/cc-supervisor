#!/usr/bin/env bash
# test-capture-lines.sh — Test tmux capture to understand output structure.
# Captures N lines and shows them with line numbers to identify which is the actual "last line".

set -euo pipefail

SESSION_NAME="${1:-cc-supervise}"
LINES="${2:-20}"

echo "=== Capturing last $LINES lines from session: $SESSION_NAME ==="
echo ""

# Check if session exists
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "ERROR: Session '$SESSION_NAME' not found"
    exit 1
fi

# Capture the pane content
echo "--- Raw capture (line numbers) ---"
tmux capture-pane -t "$SESSION_NAME" -p -S "-${LINES}" | nl -ba

echo ""
echo "--- Last 5 lines ---"
tmux capture-pane -t "$SESSION_NAME" -p -S "-5" | nl -ba

echo ""
echo "=== Analysis ==="

# Get the raw capture for analysis
CAPTURE=$(tmux capture-pane -t "$SESSION_NAME" -p -S "-${LINES}")

# Check for separators
echo "--- Separator detection ---"
echo "$CAPTURE" | grep -n "^─" | head -5 || echo "No separator lines found"

# Check for queued messages (start with >)
echo ""
echo "--- Queued message detection (lines starting with >) ---"
echo "$CAPTURE" | grep -n "^>" || echo "No queued messages found"

# Check for prompt/input indicators
echo ""
echo "--- Prompt detection (❯, ➜, →, $, > at line start) ---"
echo "$CAPTURE" | grep -nE "^❯|^➜|^→|^[$]" | head -5 || echo "No prompt found"

# Check for ellipsis
echo ""
echo "--- Ellipsis detection (…) ---"
echo "$CAPTURE" | grep -n "…" || echo "No ellipsis found"

# Show last line directly
echo ""
echo "--- Last line (raw) ---"
tmux capture-pane -t "$SESSION_NAME" -p -S -1
