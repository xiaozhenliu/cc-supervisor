#!/usr/bin/env bash
# cc_send.sh — Send input to Claude Code running in the tmux session.
#
# Usage:
#   cc_send.sh "text"           — type text and press Enter
#   cc_send.sh --key Up         — send a special key (no Enter)
#   cc_send.sh --key Down
#   cc_send.sh --key Enter
#   cc_send.sh --key 1          — send a single character (no Enter)
#
# Special key names (passed to tmux send-keys):
#   Up, Down, Left, Right, Enter, Escape, Tab, Space, BSpace, DC, Home, End
#   PageUp, PageDown, F1-F12
#   Any single character: y, n, 1, 2, 3, q, etc.
#
# Common aliases are auto-normalized:
#   Esc → Escape, Return → Enter, Backspace/BS → BSpace, Delete/Del → DC
#
# Modifier combos are auto-normalized to tmux prefix syntax:
#   Ctrl+c / ctrl-c / Ctrl-C → C-c     (tmux Ctrl prefix)
#   Alt+x  / alt-x  / Meta-x → M-x     (tmux Meta/Alt prefix)
#   Ctrl+Shift+u              → C-S-u   (tmux Ctrl+Shift prefix)

set -euo pipefail

SESSION_NAME="cc-supervise"

source "$(dirname "$0")/lib/log.sh"

# ── Parse arguments ───────────────────────────────────────────────────────────
MODE="text"
INPUT=""

if [[ $# -lt 1 ]]; then
  log_error "Usage: $0 <text>  OR  $0 --key <keyname>"
  exit 1
fi

if [[ "$1" == "--key" ]]; then
  if [[ $# -lt 2 ]]; then
    log_error "Usage: $0 --key <keyname>"
    exit 1
  fi
  MODE="key"
  INPUT="$2"
else
  MODE="text"
  INPUT="$1"
fi

# ── Verify the target session exists ──────────────────────────────────────────
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  log_error "tmux session '$SESSION_NAME' not found. Run supervisor_run.sh first."
  exit 1
fi

# ── Key name normalization ────────────────────────────────────────────────────
# tmux send-keys only recognizes specific key names (e.g. "Escape", not "Esc")
# and modifier prefixes (e.g. "C-c", not "Ctrl+c").
# Unrecognized names are split into individual characters — a silent, fatal bug.
# This function normalizes common aliases to tmux-recognized syntax.
normalize_key() {
  local key="$1"

  # ── Step 1: Normalize modifier combos (Ctrl+x, Alt+x, etc.) ──────────────
  # Patterns: Ctrl+x, ctrl-x, Control+x, CTRL+X, Ctrl+Shift+x, etc.
  # tmux syntax: C- (Ctrl), M- (Alt/Meta), S- (Shift)
  # Lowercase the key for matching, then build tmux-format output.
  local lk
  lk="$(echo "$key" | tr '[:upper:]' '[:lower:]')"

  # Handle Ctrl+Shift+<key>
  if [[ "$lk" =~ ^(ctrl|control)[+-](shift)[+-](.+)$ ]]; then
    echo "C-S-${BASH_REMATCH[3]}"
    return
  fi
  # Handle Alt/Meta+Shift+<key>
  if [[ "$lk" =~ ^(alt|meta)[+-](shift)[+-](.+)$ ]]; then
    echo "M-S-${BASH_REMATCH[3]}"
    return
  fi
  # Handle Ctrl+<key>
  if [[ "$lk" =~ ^(ctrl|control)[+-](.+)$ ]]; then
    echo "C-${BASH_REMATCH[2]}"
    return
  fi
  # Handle Alt+<key> or Meta+<key>
  if [[ "$lk" =~ ^(alt|meta)[+-](.+)$ ]]; then
    echo "M-${BASH_REMATCH[2]}"
    return
  fi

  # ── Step 2: Normalize standalone key names ────────────────────────────────
  case "$key" in
    Esc|esc|ESC)                         echo "Escape" ;;
    Return|return|RETURN)                echo "Enter" ;;
    Backspace|backspace|BACKSPACE|BS|bs) echo "BSpace" ;;
    Delete|delete|DELETE|Del|del)        echo "DC" ;;
    PageUp|pageup|PgUp|pgup)            echo "PageUp" ;;
    PageDown|pagedown|PgDown|pgdown)    echo "PageDown" ;;
    Home|home|HOME)                      echo "Home" ;;
    End|end|END)                         echo "End" ;;
    *)                                   echo "$key" ;;
  esac
}

# ── Send input ────────────────────────────────────────────────────────────────
if [[ "$MODE" == "text" ]]; then
  # Send text literally, then Enter separately (handles special characters)
  tmux send-keys -t "$SESSION_NAME" -l "$INPUT"
  tmux send-keys -t "$SESSION_NAME" Enter
  log_info "Sent text to '$SESSION_NAME': ${INPUT:0:120}$([ ${#INPUT} -gt 120 ] && echo '...')"
else
  # Normalize key alias to tmux-recognized name
  NORMALIZED="$(normalize_key "$INPUT")"
  if [[ "$NORMALIZED" != "$INPUT" ]]; then
    log_info "Normalized key name: '$INPUT' → '$NORMALIZED'"
  fi
  # Send special key by name (no -l flag, no Enter)
  tmux send-keys -t "$SESSION_NAME" "$NORMALIZED"
  log_info "Sent key to '$SESSION_NAME': $NORMALIZED"
fi
