# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-02-24

### Added
- **Phase 6 — Supervision Modes**: `CC_MODE` env var selects `relay` (default) or `autonomous`
  mode; `supervisor_run.sh` forwards `CC_MODE` into the tmux session environment
- **autonomous mode Stop notification**: includes `ACTION_REQUIRED: decide_and_continue`
  marker so OpenClaw can drive tasks without human confirmation after each turn
- `SKILL.md` — new `## Supervision Modes` section documenting both modes, usage examples,
  and notification format including `ACTION_REQUIRED`

### Changed
- **Phase 5 — Stop empty summary**: fallback text changed from
  `"(Claude Code finished a response turn)"` to `"[no content]"` (per PRD)
- **Phase 5 — events.ndjson schema**: added `tool_name` field; populated for `PostToolUse`
  events, `null` for all others
- **Notification prefix**: all `openclaw send` messages now include `[cc_mode]` tag,
  e.g. `[cc-supervisor][relay] Stop: ...` for easier log filtering
- `SKILL.md` — updated notification table and event log format examples to reflect new schema

## [0.4.0] - 2026-02-24

### Added
- `SKILL.md` (repo root) — standard ClawHub skill definition with YAML frontmatter:
  `name`, `description`, `version`, `metadata.openclaw` (emoji, `requires.bins`,
  `install` array for brew deps, `os` restriction); replaces `config/cc-supervisor-skill.md`

### Changed
- Install path changed from `~/tools/cc-supervisor` to `~/.openclaw/skills/cc-supervisor`
  (standard OpenClaw skill directory); `clawhub install cc-supervisor` is now the
  primary install method
- `README.md` / `README_en.md` — updated all paths to `~/.openclaw/skills/cc-supervisor/`,
  ClawHub as primary install method, shell aliases updated accordingly
- `docs/SCRIPTS.md` — updated `supervisor_run.sh` and `install-hooks.sh` usage examples
  to use `~/.openclaw/skills/cc-supervisor/` paths

### Removed
- `config/cc-supervisor-skill.md` — superseded by `SKILL.md` at repo root

## [0.3.0] - 2026-02-24

### Added
- `CLAUDE_WORKDIR` environment variable to `supervisor_run.sh` and `install-hooks.sh`,
  separating "where cc-supervisor lives" (`CC_PROJECT_DIR`) from "where Claude Code
  works" (`CLAUDE_WORKDIR`); defaults preserve all existing behaviour

### Changed
- `README.md` / `README_en.md` — expanded "在其他项目中使用 / Using with an Existing
  Project" section with full external-project commands, shell alias examples, OpenClaw
  skill install instructions, and uninstall steps; all in a single README, no separate
  install guide
- `docs/SCRIPTS.md` — updated `supervisor_run.sh` and `install-hooks.sh` entries to
  document `CLAUDE_WORKDIR`

## [0.2.0] - 2026-02-24

### Added
- `docs/ARCHITECTURE.md` — system design, component responsibilities, complete
  data-flow trace, Hook event processing logic, environment variables reference,
  and log file formats
- `docs/SCRIPTS.md` — per-script interface reference: arguments, environment
  variables (read/set), side effects, and exit codes for all 8 scripts
- `CHANGELOG.md` and `VERSION` file (`0.2.0`)
- `README_en.md` — English README mirroring the Chinese README structure

### Changed
- `README.md` — added version badge, Quick Start section (3-line install),
  and converted the doc cross-reference list to a linked table
- `scripts/install-hooks.sh` — target changed from `~/.claude/settings.json`
  (global) to `.claude/settings.local.json` (project-local, machine-specific);
  hooks are now scoped to this project only

## [0.1.0] - 2026-02-24

### Added
- `scripts/supervisor_run.sh` — create/reuse tmux session `cc-supervise`, launch
  Claude Code, export `CC_PROJECT_DIR`, start watchdog
- `scripts/cc_send.sh` — send text + Enter to Claude Code via `tmux send-keys -l`
- `scripts/cc_capture.sh` — snapshot tmux pane output for diagnostics
- `scripts/lib/log.sh` — shared structured JSON logging to `logs/supervisor.log`
- `tests/test_phase1.sh` — 10 integration tests for Phase 1 scripts (all passing)
- `scripts/on-cc-event.sh` — unified Hook callback: dedup by `session_id+event_id`,
  append to `events.ndjson`, notify OpenClaw; graceful degradation if `openclaw`
  not in PATH
- `scripts/install-hooks.sh` — idempotent deep-merge installer for Hook config
- `config/claude-hooks.json` — hook registration template with `__HOOK_SCRIPT_PATH__`
  placeholder
- `scripts/cc-watchdog.sh` — inactivity watchdog daemon; monitors `events.ndjson`
  mtime, alerts after `CC_TIMEOUT` seconds (default 30 min); PID-file managed
- `README.md` — user-facing documentation (Simplified Chinese)
- `config/cc-supervisor-skill.md` — OpenClaw skill definition (English)
- `scripts/demo.sh` — end-to-end demo using plain bash shell; no API or network
  required

[Unreleased]: https://github.com/OWNER/cc-supervisor/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/OWNER/cc-supervisor/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/OWNER/cc-supervisor/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/OWNER/cc-supervisor/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/OWNER/cc-supervisor/releases/tag/v0.1.0
