#!/usr/bin/env bash
# flush-queue.sh — Retry queued notifications that failed to send.
# Agent should call this every 30 minutes to prevent notification backlog.

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR

source "$(dirname "$0")/lib/runtime_context.sh"
source "$(dirname "$0")/lib/log.sh"
source "$(dirname "$0")/lib/notify.sh"

REQUESTED_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      REQUESTED_ID="${2:?'--id requires a supervision id'}"
      shift 2
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

runtime_context_init "${REQUESTED_ID:-${CC_SUPERVISION_ID:-default}}"

QUEUE_FILE="${CC_NOTIFICATION_QUEUE_FILE}"

if [[ ! -f "$QUEUE_FILE" || ! -s "$QUEUE_FILE" ]]; then
  log_info "Queue is empty — nothing to flush"
  exit 0
fi

if [[ -z "${OPENCLAW_SESSION_ID:-}" ]]; then
  log_warn "OPENCLAW_SESSION_ID not set — cannot flush (messages remain queued)"
  log_warn "Set it with: export OPENCLAW_SESSION_ID=<uuid>"
  exit 1
fi

TOTAL=0; SUCCESS=0; FAILED=0
FAILED_LINES=()

while IFS='|' read -r ts channel account target event_type msg; do
  TOTAL=$((TOTAL + 1))
  # Temporarily set OPENCLAW_TARGET from queue entry for correct delivery routing
  local_target="$target"
  if OPENCLAW_TARGET="$local_target" notify_from_queue \
      "${OPENCLAW_SESSION_ID}" "$channel" "$local_target" "$event_type" "$msg" 2>/dev/null; then
    SUCCESS=$((SUCCESS + 1))
    log_info "Flushed: $event_type ($ts)"
  else
    FAILED=$((FAILED + 1))
    FAILED_LINES+=("${ts}|${channel}|${account}|${target}|${event_type}|${msg}")
    log_warn "Still failing: $event_type ($ts)"
  fi
done < "$QUEUE_FILE"

if [[ ${#FAILED_LINES[@]} -eq 0 ]]; then
  rm -f "$QUEUE_FILE"
else
  printf '%s\n' "${FAILED_LINES[@]}" > "$QUEUE_FILE"
fi

log_info "Flush complete: total=$TOTAL success=$SUCCESS failed=$FAILED"
