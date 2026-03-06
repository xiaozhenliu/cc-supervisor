#!/usr/bin/env bash
# watchdog-guard.sh — Self-healing wrapper for cc-watchdog.sh.
# Restarts watchdog on crash (non-zero exit); exits cleanly when watchdog
# exits normally (exit 0 = tmux session gone or intentional stop).

set -euo pipefail

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CC_PROJECT_DIR
source "$(dirname "$0")/lib/runtime_context.sh"
runtime_context_init "${CC_SUPERVISION_ID:-default}"

WATCHDOG="${CC_PROJECT_DIR}/scripts/cc-watchdog.sh"
GUARD_PID_FILE="${CC_WATCHDOG_GUARD_PID_FILE}"
RESTART_DELAY=5   # seconds between crash restarts

source "$(dirname "$0")/lib/log.sh"

cleanup() {
  rm -f "$GUARD_PID_FILE"
  log_info "watchdog-guard stopped"
}
trap cleanup EXIT INT TERM

mkdir -p "$(dirname "$GUARD_PID_FILE")"
echo "$$" > "$GUARD_PID_FILE"
log_info "watchdog-guard started (PID=$$)"

while true; do
  bash "$WATCHDOG"
  exit_code=$?
  if (( exit_code == 0 )); then
    log_info "watchdog exited cleanly — guard stopping"
    exit 0
  fi
  log_warn "watchdog crashed (exit=$exit_code) — restarting in ${RESTART_DELAY}s"
  sleep "$RESTART_DELAY"
done
