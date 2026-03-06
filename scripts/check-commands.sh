#!/usr/bin/env bash
# check-commands.sh - Check required commands are available
# Can be used standalone or called by preflight-check.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"

REQUIRED_COMMANDS=("openclaw" "tmux" "jq")
MISSING_COMMANDS=()

for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if command -v "$cmd" &>/dev/null; then
    log_info "✓ $cmd command"
  else
    log_error "✗ $cmd command"
    MISSING_COMMANDS+=("$cmd")
  fi
done

if [ ${#MISSING_COMMANDS[@]} -gt 0 ]; then
  echo ""
  log_error "Missing required commands: ${MISSING_COMMANDS[*]}"
  log_error ""
  log_error "Install instructions:"
  for cmd in "${MISSING_COMMANDS[@]}"; do
    case "$cmd" in
      openclaw)
        log_error "  - openclaw: npm install -g openclaw@latest"
        ;;
      tmux)
        log_error "  - tmux: brew install tmux (macOS) or apt install tmux (Linux)"
        ;;
      jq)
        log_error "  - jq: brew install jq (macOS) or apt install jq (Linux)"
        ;;
    esac
  done
  exit 1
fi

exit 0
