#!/usr/bin/env bash
# check-env.sh - Check optional environment variables
# Can be used standalone or called by preflight-check.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"

if [ -n "${OPENCLAW_CHANNEL:-}" ]; then
  log_info "✓ OPENCLAW_CHANNEL: $OPENCLAW_CHANNEL"
else
  log_warn "⚠ OPENCLAW_CHANNEL not set (will use session-based routing)"
fi

if [ -n "${OPENCLAW_TARGET:-}" ]; then
  log_info "✓ OPENCLAW_TARGET: $OPENCLAW_TARGET"
else
  log_warn "⚠ OPENCLAW_TARGET not set (will use session-based routing)"
fi

if [ -n "${OPENCLAW_ACCOUNT:-}" ]; then
  log_info "✓ OPENCLAW_ACCOUNT: $OPENCLAW_ACCOUNT"
else
  log_warn "⚠ OPENCLAW_ACCOUNT not set (optional)"
fi

exit 0
