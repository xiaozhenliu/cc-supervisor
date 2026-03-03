#!/usr/bin/env bash
# install.sh — One-command installer for cc-supervisor skill.
#
# Usage:
#   bash install.sh              # interactive install
#   bash install.sh --dry-run    # preview mode (no writes)
#   curl -fsSL <url> | bash      # non-interactive (pipe) install
#
# Installs to: ~/.openclaw/skills/cc-supervisor
# Injects shell aliases into ~/.zshrc or ~/.bashrc (idempotent)

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
SKILL_DEST="${CC_SUPERVISOR_DEST:-$HOME/.openclaw/skills/cc-supervisor}"
REPO_URL="${CC_SUPERVISOR_REPO:-https://github.com/OWNER/cc-supervisor}"
TARBALL_URL="${CC_SUPERVISOR_TARBALL:-${REPO_URL}/archive/refs/heads/main.tar.gz}"
ALIAS_MARKER="# cc-supervisor aliases — managed by install.sh"

DRY_RUN=false
# Detect pipe/non-interactive: stdin is not a terminal
INTERACTIVE=true
[[ -t 0 ]] || INTERACTIVE=false

# ── Helpers ───────────────────────────────────────────────────────────────────
_info()  { echo "[install] $*"; }
_warn()  { echo "[install] WARN: $*" >&2; }
_error() { echo "[install] ERROR: $*" >&2; }
_die()   { _error "$*"; exit 1; }

_run() {
  # Execute or dry-run a command
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] would: $*"
  else
    "$@"
  fi
}

_run_shell() {
  # Execute or dry-run a shell string
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] would: $*"
  else
    eval "$*"
  fi
}

# ── Argument parsing ──────────────────────────────────────────────────────────
parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY_RUN=true ;;
      --help|-h)
        echo "Usage: bash install.sh [--dry-run] [--help]"
        echo ""
        echo "Options:"
        echo "  --dry-run   Preview all actions without making changes"
        echo "  --help      Show this help"
        exit 0
        ;;
      *) _die "Unknown argument: $arg" ;;
    esac
  done
}

# ── OS detection ──────────────────────────────────────────────────────────────
detect_os() {
  OS_TYPE="unknown"
  if [[ "$(uname)" == "Darwin" ]]; then
    OS_TYPE="macos"
  elif command -v apt-get &>/dev/null; then
    OS_TYPE="linux-apt"
  elif command -v yum &>/dev/null; then
    OS_TYPE="linux-yum"
  elif [[ "$(uname)" == "Linux" ]]; then
    OS_TYPE="linux-unknown"
  fi
  _info "Detected OS: $OS_TYPE"
}

# ── Prerequisite checking ─────────────────────────────────────────────────────
_install_hint() {
  local tool="$1"
  case "$OS_TYPE" in
    macos)
      case "$tool" in
        tmux|jq) echo "  → brew install $tool" ;;
        claude)  echo "  → See: https://docs.anthropic.com/claude-code" ;;
        openclaw) echo "  → See: https://openclaw.ai/docs/install" ;;
      esac
      ;;
    linux-apt)
      case "$tool" in
        tmux|jq) echo "  → sudo apt-get install -y $tool" ;;
        claude)  echo "  → See: https://docs.anthropic.com/claude-code" ;;
        openclaw) echo "  → See: https://openclaw.ai/docs/install" ;;
      esac
      ;;
    linux-yum)
      case "$tool" in
        tmux|jq) echo "  → sudo yum install -y $tool" ;;
        claude)  echo "  → See: https://docs.anthropic.com/claude-code" ;;
        openclaw) echo "  → See: https://openclaw.ai/docs/install" ;;
      esac
      ;;
    *)
      case "$tool" in
        tmux|jq) echo "  → Install via your system package manager" ;;
        claude)  echo "  → See: https://docs.anthropic.com/claude-code" ;;
        openclaw) echo "  → See: https://openclaw.ai/docs/install" ;;
      esac
      ;;
  esac
}

check_prerequisites() {
  _info "Checking prerequisites..."
  local missing=()

  for tool in tmux jq claude openclaw; do
    if ! command -v "$tool" &>/dev/null; then
      missing+=("$tool")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    _error "Missing required tools:"
    for tool in "${missing[@]}"; do
      echo "  ✗ $tool"
      _install_hint "$tool"
    done
    _die "Install the missing tools above, then re-run install.sh"
  fi

  _info "All prerequisites satisfied (tmux, jq, claude, openclaw)"
}

# ── Skill file installation ───────────────────────────────────────────────────
install_skill_files() {
  _info "Installing skill files to: $SKILL_DEST"

  if [[ -d "$SKILL_DEST" ]]; then
    _info "Destination already exists: $SKILL_DEST"
    if [[ "$INTERACTIVE" == "true" && "$DRY_RUN" == "false" ]]; then
      read -r -p "[install] Overwrite with latest version? [Y/n] " answer
      answer="${answer:-Y}"
      if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        _info "Skipping skill file update (existing installation kept)"
        return 0
      fi
    else
      _info "Non-interactive mode — updating existing installation via rsync"
    fi
    _update_via_rsync
    return 0
  fi

  # Fresh install: try git clone first, fall back to tarball
  if command -v git &>/dev/null; then
    _info "Cloning via git..."
    if _run git clone --depth=1 "$REPO_URL" "$SKILL_DEST" 2>/dev/null; then
      _info "git clone succeeded"
      return 0
    fi
    _warn "git clone failed — falling back to tarball download"
  fi

  _install_via_tarball
}

_install_via_tarball() {
  if ! command -v curl &>/dev/null; then
    _die "Neither git nor curl is available — cannot download skill files"
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  local tarball="$tmpdir/cc-supervisor.tar.gz"

  _info "Downloading tarball from $TARBALL_URL ..."
  if ! _run curl -fsSL "$TARBALL_URL" -o "$tarball"; then
    rm -rf "$tmpdir"
    _die "Failed to download tarball from $TARBALL_URL"
  fi

  _info "Extracting..."
  _run mkdir -p "$SKILL_DEST"
  _run tar -xzf "$tarball" -C "$tmpdir"

  # tar extracts to a subdirectory like cc-supervisor-main/
  local extracted_dir
  extracted_dir="$(find "$tmpdir" -maxdepth 1 -mindepth 1 -type d | head -1)"
  if [[ -z "$extracted_dir" ]]; then
    rm -rf "$tmpdir"
    _die "Tarball extraction produced no directory"
  fi

  _run rsync -a --delete \
    --exclude=".git" \
    --exclude="logs/" \
    --exclude="tests/" \
    --exclude="docs/DESIGN_DECISIONS.md" \
    --exclude="docs/ARCHITECTURE.md" \
    --exclude="docs/SCRIPTS.md" \
    --exclude="docs/INSTALL.md" \
    --exclude="docs/preflight-checks.md" \
    --exclude="docs/agent-hierarchy.md" \
    --exclude="docs/flexible-*.md" \
    --exclude="ref/" \
    --exclude="CLAUDE.md" \
    --exclude=".github/" \
    --exclude="*.backup*" \
    "$extracted_dir/" "$SKILL_DEST/"

  rm -rf "$tmpdir"
  _info "Tarball install complete"
}

_update_via_rsync() {
  # Update existing install from current script's own directory (if running locally)
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ -f "$script_dir/SKILL.md" ]]; then
    _info "Updating from local source: $script_dir"
    _run rsync -a --delete \
      --exclude=".git" \
      --exclude="logs/" \
      --exclude="tests/" \
      --exclude="docs/DESIGN_DECISIONS.md" \
      --exclude="docs/ARCHITECTURE.md" \
      --exclude="docs/SCRIPTS.md" \
      --exclude="docs/INSTALL.md" \
      --exclude="docs/preflight-checks.md" \
      --exclude="docs/agent-hierarchy.md" \
      --exclude="docs/flexible-*.md" \
      --exclude="ref/" \
      --exclude="CLAUDE.md" \
      --exclude=".github/" \
      --exclude="*.backup*" \
      "$script_dir/" "$SKILL_DEST/"
  else
    _info "No local source found — re-downloading via tarball"
    _install_via_tarball
  fi
}

# ── Shell alias injection ─────────────────────────────────────────────────────
_detect_shell_rc() {
  local shell_name
  shell_name="$(basename "${SHELL:-bash}")"
  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) echo "$HOME/.bashrc" ;;
    *)    echo "$HOME/.bashrc" ;;
  esac
}

_aliases_already_injected() {
  local rc_file="$1"
  [[ -f "$rc_file" ]] && grep -qF "$ALIAS_MARKER" "$rc_file"
}

inject_shell_aliases() {
  local rc_file
  rc_file="$(_detect_shell_rc)"
  _info "Shell RC file: $rc_file"

  if _aliases_already_injected "$rc_file"; then
    _info "Aliases already present in $rc_file — skipping (idempotent)"
    return 0
  fi

  _info "Injecting shell aliases into $rc_file ..."

  local alias_block
  alias_block="$(cat <<'ALIASES'

# cc-supervisor aliases — managed by install.sh
export CC_SUPERVISOR_HOME=~/.openclaw/skills/cc-supervisor

cc-supervise() {
  local target="${1:?Usage: cc-supervise <project-dir>}"
  CC_PROJECT_DIR="$CC_SUPERVISOR_HOME" \
  CLAUDE_WORKDIR="$target" \
    "$CC_SUPERVISOR_HOME/scripts/supervisor_run.sh"
}

cc-install-hooks() {
  local target="${1:?Usage: cc-install-hooks <project-dir>}"
  CC_PROJECT_DIR="$CC_SUPERVISOR_HOME" \
  CLAUDE_WORKDIR="$target" \
    "$CC_SUPERVISOR_HOME/scripts/install-hooks.sh"
}

cc-send() {
  "$CC_SUPERVISOR_HOME/scripts/cc_send.sh" "$@"
}

cc-capture() {
  "$CC_SUPERVISOR_HOME/scripts/cc_capture.sh" "$@"
}

cc-flush-queue() {
  "$CC_SUPERVISOR_HOME/scripts/flush-queue.sh"
}
# end cc-supervisor aliases
ALIASES
)"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] would append to $rc_file:"
    echo "$alias_block"
  else
    printf '%s\n' "$alias_block" >> "$rc_file"
    _info "Aliases injected successfully"
  fi
}

# ── Next steps ────────────────────────────────────────────────────────────────
print_next_steps() {
  local rc_file
  rc_file="$(_detect_shell_rc)"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " cc-supervisor installed successfully!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo " Next steps:"
  echo ""
  echo "  1. Reload your shell:"
  echo "     source $rc_file"
  echo ""
  echo "  2. Register hooks in your project (once per project):"
  echo "     cc-install-hooks ~/Projects/my-app"
  echo ""
  echo "  3. Start supervision:"
  echo "     cc-supervise ~/Projects/my-app"
  echo ""
  echo "  4. Send a task:"
  echo "     cc-send \"implement the login API\""
  echo ""
  echo " Skill installed at: $SKILL_DEST"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  if [[ "$DRY_RUN" == "true" ]]; then
    _info "DRY-RUN mode — no changes will be made"
  fi

  detect_os
  check_prerequisites
  install_skill_files
  inject_shell_aliases
  print_next_steps
}

main "$@"
