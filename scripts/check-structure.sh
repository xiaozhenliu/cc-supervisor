#!/usr/bin/env bash
# check-structure.sh - Check project structure
# Can be used standalone or called by preflight-check.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"

CC_PROJECT_DIR="${CC_PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

REQUIRED_DIRS=("scripts" "logs")
REQUIRED_FILES=("scripts/supervisor_run.sh" "scripts/lib/log.sh" "scripts/lib/notify.sh")

CHECKS_FAILED=0

for dir in "${REQUIRED_DIRS[@]}"; do
  if [ -d "$CC_PROJECT_DIR/$dir" ]; then
    log_info "✓ Directory exists: $dir/"
  else
    log_error "✗ Missing directory: $dir/"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
done

for file in "${REQUIRED_FILES[@]}"; do
  if [ -f "$CC_PROJECT_DIR/$file" ]; then
    log_info "✓ File exists: $file"
  else
    log_error "✗ Missing file: $file"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
done

if [ $CHECKS_FAILED -gt 0 ]; then
  echo ""
  log_error "Project structure validation failed"
  log_error "CC_PROJECT_DIR: $CC_PROJECT_DIR"
  exit 1
fi

exit 0
