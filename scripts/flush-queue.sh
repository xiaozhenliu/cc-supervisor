#!/usr/bin/env bash
# flush-queue.sh — Retry queued notifications that failed to send.
# Agent should call this every 30 minutes to prevent notification backlog.

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$(dirname "$0")/lib/log.sh"

QUEUE_FILE="${CC_PROJECT_DIR}/logs/notification.queue"

if [[ ! -f "$QUEUE_FILE" || ! -s "$QUEUE_FILE" ]]; then
  log_info "Queue is empty — nothing to flush"
  exit 0
fi

if ! command -v openclaw &>/dev/null; then
  log_warn "openclaw not in PATH — cannot flush queue"
  exit 1
fi

TOTAL=0; SUCCESS=0; FAILED=0
FAILED_LINES=()

while IFS='|' read -r ts channel account target event_type msg; do
  TOTAL=$((TOTAL + 1))
  if openclaw agent \
      --agent "$account" \
      --message "$msg" \
      ${channel:+--deliver} \
      ${channel:+--reply-channel "$channel"} \
      ${target:+--reply-to "$target"} \
      2>/dev/null; then
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
