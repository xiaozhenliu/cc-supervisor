#!/usr/bin/env bash
# demo.sh — Demonstrate the full cc-supervisor multi-turn supervision loop.
#
# This demo uses a plain bash shell instead of Claude Code so it runs
# without network access or API credentials. It simulates:
#   1. Session startup
#   2. Sending a task prompt
#   3. Hook event pipeline (firing on-cc-event.sh manually)
#   4. A second turn (simulating OpenClaw sending a follow-up)
#   5. Session end
#
# Usage: ./scripts/demo.sh [--clean]
#   --clean    Kill the demo session before starting (for a fresh run)

set -euo pipefail

DEMO_SESSION="cc-supervise"
CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR

SCRIPTS="${CC_PROJECT_DIR}/scripts"
EVENTS="${CC_PROJECT_DIR}/logs/events.ndjson"

# ── Helpers ───────────────────────────────────────────────────────────────────

log() { echo "[demo] $*"; }

simulate_hook_event() {
  local event_type="$1"
  local extra_json="${2:-}"
  local session_id="demo-session-001"
  local event_id="evt-$(date +%s%N | tail -c 6)"

  # Build base payload, then merge extra fields if provided
  local payload
  payload="$(jq -cn \
    --arg hook_event_name "$event_type" \
    --arg session_id      "$session_id" \
    --arg event_id        "$event_id" \
    '{hook_event_name:$hook_event_name, session_id:$session_id, event_id:$event_id}')"
  if [[ -n "$extra_json" ]]; then
    payload="$(echo "$payload" | jq ". + ${extra_json}")"
  fi

  log "→ Firing Hook: $event_type"
  echo "$payload" | bash "${SCRIPTS}/on-cc-event.sh" 2>&1 | sed 's/^/   /'
}

# ── Parse args ────────────────────────────────────────────────────────────────
CLEAN=false
for arg in "$@"; do
  [[ "$arg" == "--clean" ]] && CLEAN=true
done

# ── Step 0: Clean up previous demo session if requested ──────────────────────
if $CLEAN || tmux has-session -t "$DEMO_SESSION" 2>/dev/null; then
  log "Killing existing tmux session '$DEMO_SESSION'..."
  tmux kill-session -t "$DEMO_SESSION" 2>/dev/null || true
  sleep 0.3
fi

# ── Step 1: Start a demo tmux session with a plain shell ─────────────────────
log "Step 1: Creating tmux session '$DEMO_SESSION' (with bash, not claude)"
tmux new-session -d -s "$DEMO_SESSION" -c "$CC_PROJECT_DIR" \
  -e "CC_PROJECT_DIR=$CC_PROJECT_DIR"
sleep 0.3
log "  Session ready. Attach anytime: tmux attach -t $DEMO_SESSION"

# ── Step 2: Send initial task prompt ─────────────────────────────────────────
log ""
log "Step 2: Sending initial task prompt..."
"${SCRIPTS}/cc_send.sh" "echo 'Simulating Claude Code — task started'; sleep 0.5; echo 'Task in progress...'"
sleep 0.8

log "  Capturing pane output:"
"${SCRIPTS}/cc_capture.sh" --tail 5 2>/dev/null | sed 's/^/    /'

# ── Step 3: Simulate PostToolUse Hook (successful tool) ──────────────────────
log ""
log "Step 3: Simulating PostToolUse Hook (Bash tool, success)..."
simulate_hook_event "PostToolUse" \
  '{"tool_name":"Bash","toolResult":{"isError":false,"content":[{"text":"Files listed successfully"}]}}'

# ── Step 4: Simulate Stop Hook (first turn done) ─────────────────────────────
log ""
log "Step 4: Simulating Stop Hook (first turn complete)..."
simulate_hook_event "Stop" '{}'

# ── Step 5: OpenClaw sends follow-up prompt ───────────────────────────────────
log ""
log "Step 5: OpenClaw sends follow-up prompt (simulating multi-turn)..."
"${SCRIPTS}/cc_send.sh" "echo 'Received follow-up. Continuing task...'; sleep 0.3; echo 'Done.'"
sleep 0.8

# ── Step 6: Simulate Stop Hook (second turn done) ────────────────────────────
log ""
log "Step 6: Simulating Stop Hook (second turn — task complete)..."
simulate_hook_event "Stop" '{}'

# ── Step 7: Simulate SessionEnd ──────────────────────────────────────────────
log ""
log "Step 7: Simulating SessionEnd Hook..."
simulate_hook_event "SessionEnd" '{}'

# ── Step 8: Show event log ────────────────────────────────────────────────────
log ""
log "Step 8: Events logged to $EVENTS:"
if [[ -f "$EVENTS" ]]; then
  jq -r '"  [\(.ts)] \(.event_type): \(.summary | .[0:80])"' "$EVENTS" 2>/dev/null | tail -10
else
  log "  (no events file found)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Demo complete."
log "  Session still running: tmux attach -t $DEMO_SESSION"
log "  Kill session:          tmux kill-session -t $DEMO_SESSION"
log "  Full event log:        cat $EVENTS | jq ."
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
