#!/usr/bin/env bash
# preflight-check.sh - Unified preflight checks orchestrator
# Calls independent validation scripts in sequence
#
# Usage: eval "$(./scripts/preflight-check.sh)"
# Returns: exports required env vars if successful, exits with error otherwise

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"

# Track check results
CHECKS_PASSED=0
CHECKS_FAILED=0

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Running preflight checks for cc-supervisor..."
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Check 1: Required commands ────────────────────────────────────────────────
log_info "[1/4] Checking required commands..."

CHECK_COMMANDS_SCRIPT="${SCRIPT_DIR}/check-commands.sh"
if [ -f "$CHECK_COMMANDS_SCRIPT" ]; then
  if bash "$CHECK_COMMANDS_SCRIPT" 2>&1; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    exit 1
  fi
else
  log_error "✗ check-commands.sh not found"
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  exit 1
fi

echo ""

# ── Check 2: OPENCLAW_SESSION_ID ──────────────────────────────────────────────
log_info "[2/4] Checking OPENCLAW_SESSION_ID..."

ENSURE_SESSION_SCRIPT="${SCRIPT_DIR}/ensure-session-id.sh"
if [ -f "$ENSURE_SESSION_SCRIPT" ]; then
  if SESSION_ID_EXPORT=$(bash "$ENSURE_SESSION_SCRIPT" 2>&1); then
    eval "$SESSION_ID_EXPORT"
    log_info "✓ Session ID validated: ${OPENCLAW_SESSION_ID:0:8}...${OPENCLAW_SESSION_ID: -4}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    # ensure-session-id.sh failed, auto-generate temporary session ID
    log_warn "⚠ Session ID not available, auto-generating..."
    GENERATED_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    export OPENCLAW_SESSION_ID="$GENERATED_ID"
    log_info "✓ Auto-generated temporary session ID: ${OPENCLAW_SESSION_ID:0:8}...${OPENCLAW_SESSION_ID: -4}"
    log_warn "  This is sufficient for the current session."
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  fi
else
  log_error "✗ ensure-session-id.sh not found"
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  exit 1
fi

echo ""

# ── Check 3: Optional environment variables ───────────────────────────────────
log_info "[3/4] Checking optional environment variables..."

CHECK_ENV_SCRIPT="${SCRIPT_DIR}/check-env.sh"
if [ -f "$CHECK_ENV_SCRIPT" ]; then
  bash "$CHECK_ENV_SCRIPT" 2>&1
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  log_warn "⚠ check-env.sh not found, skipping"
fi

echo ""

# ── Check 4: Project structure ────────────────────────────────────────────────
log_info "[4/4] Checking project structure..."

CHECK_STRUCTURE_SCRIPT="${SCRIPT_DIR}/check-structure.sh"
if [ -f "$CHECK_STRUCTURE_SCRIPT" ]; then
  if bash "$CHECK_STRUCTURE_SCRIPT" 2>&1; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    exit 1
  fi
else
  log_error "✗ check-structure.sh not found"
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  exit 1
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $CHECKS_FAILED -eq 0 ]; then
  log_info "✅ All preflight checks passed"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  log_info "Ready to start cc-supervisor!"
  echo ""

  # Export all required variables
  CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
  echo "export OPENCLAW_SESSION_ID='$OPENCLAW_SESSION_ID'"
  echo "export CC_PROJECT_DIR='$CC_PROJECT_DIR'"
  exit 0
else
  log_error "❌ Preflight checks failed"
  log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  log_error "Cannot proceed. Fix the errors above and retry."
  exit 1
fi
