# Changelog

All notable changes to cc-supervisor will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2026-03-03

### Added
- **Flexible agent hierarchy**: Agents can now dynamically identify their role without hardcoded IDs
  - New environment variable: `CC_SUPERVISOR_ROLE`
    - Unset or `primary`: Agent can invoke cc-supervisor skill
    - `supervisor`: Agent is executing supervision, cannot invoke skill again (prevents recursion)
  - Any agent can be primary agent (main, ruyi, custom agents)
  - Supervisor role is set automatically when skill is invoked
  - Recursion prevention: Supervisor agents cannot call cc-supervisor again
  - Files changed: `SKILL.md`, `supervisor_run.sh`, `logs/hook.env`

### Fixed
- **Hook session routing**: Clarified that hooks should notify the **caller** (supervisor agent), not Claude Code's internal session
  - Root cause: Confusion between two different session IDs:
    - `OPENCLAW_SESSION_ID` (env var) = caller's session (main/ruyi agent) ✓ Use this
    - `session_id` (hook JSON) = Claude Code's internal session ✗ Don't use for routing
  - Solution: Hook uses `OPENCLAW_SESSION_ID` environment variable to notify the caller
  - Changes:
    - `on-cc-event.sh`: Uses `OPENCLAW_SESSION_ID` (caller's session) for notifications
    - `supervisor_run.sh`: Writes `logs/hook.env` with caller's session ID for reliability
    - `on-cc-event.sh`: Auto-sources `logs/hook.env` if environment variables are missing
  - Architecture: Primary agent → Supervisor agent → cc-supervisor skill → Claude Code (tool)
  - Hook notifications flow: Claude Code → Supervisor agent → (Supervisor decides) → Primary agent
  - Impact: Notifications now correctly route to the skill caller (supervisor agent), not to Claude Code's internal session

- **Preflight check session ID validation**: Removed meaningless auto-generation of random session IDs
  - Previous behavior: When `OPENCLAW_SESSION_ID` was unavailable, preflight check would generate a random UUID
  - Problem: Random session IDs cannot deliver notifications correctly
  - New behavior: Preflight check now fails with clear error message if session ID is unavailable
  - Files changed: `scripts/preflight-check.sh`

### Documentation
- Added `docs/agent-hierarchy.md`: Comprehensive architecture documentation explaining:
  - Claude Code is a tool, not an agent
  - Hook notification routing logic
  - Session ID disambiguation
  - Call flow examples
  - Troubleshooting guide
- Added `docs/flexible-agent-hierarchy.md`: Design document for flexible agent hierarchy
- Added `docs/flexible-hierarchy-examples.md`: Usage examples for different agent scenarios

## [0.8.0] - 2026-03-02

### Changed
- **auto mode redesign**: OpenClaw is now a strict state machine — no free-form content generation
  - Replaced ad-hoc Stop type handling with 7 explicit action chains (L1–L7)
  - Removed `Blocked` self-recovery logic (OpenClaw no longer generates technical suggestions)
  - `Complete` now triggers testing (L4) before reporting success, not direct Phase 4
  - Added explicit test→commit→report pipeline: L4 → L5 → L6
  - `Question` and `Choice` unified into L3: select Claude's recommended option
  - `Blocked` now always escalates to human (L7) instead of retrying with suggestions

### Documentation
- `docs/DESIGN_DECISIONS.md`: Updated auto mode section with L1–L7 chain definitions and rationale

## [0.7.0] - 2026-03-02

### Added
- **Modular preflight check system**: New unified validation with independent, reusable scripts
  - `preflight-check.sh`: Orchestrator that calls independent validation scripts
  - `check-commands.sh`: Verify required commands (openclaw, tmux, jq, uuidgen)
  - `check-env.sh`: Check optional environment variables
  - `check-structure.sh`: Verify project structure
  - Auto-generates OPENCLAW_SESSION_ID if not available
  - Clear error messages with installation instructions
- **Distinctive test notifications**: Test messages now include timestamps, session IDs, routing info, and emoji markers for easy verification
- Documentation: `docs/preflight-checks.md` explaining architecture and usage

### Changed
- **Session-based routing**: Notifications now query OpenClaw session metadata to determine source channel, ensuring messages return to the correct channel instead of webchat
  - `scripts/lib/notify.sh`: Added session metadata query functions
  - Always use `--deliver` and `--reply-channel` parameters
  - Fallback to environment variables if session metadata unavailable
- **cc-start.sh**: Now runs preflight checks at Step 0 before any other operations
- **SKILL.md**: Simplified workflow - Phase 0 collects inputs, Phase 1 handles all checks internally
- **Agent autonomy**: Agent can now auto-generate session ID without human intervention

### Fixed
- Notification routing: Messages no longer incorrectly route to webchat when sent from Discord
- Session ID reliability: Proactive validation prevents "session ID not set" errors during execution

### Documentation
- `docs/session-routing-implementation.md`: Complete implementation details
- `docs/notification-routing-analysis.md`: Problem analysis and solutions
- `docs/session-based-routing.md`: Implementation plan
- Updated SKILL.md with clearer phase responsibilities

## [0.6.9] - Previous releases

See git history for earlier changes.

## [Unreleased]

### Added
- **Flexible agent hierarchy**: Agents can now dynamically identify their role without hardcoded IDs
  - New environment variable: `CC_SUPERVISOR_ROLE`
    - Unset or `primary`: Agent can invoke cc-supervisor skill
    - `supervisor`: Agent is executing supervision, cannot invoke skill again (prevents recursion)
  - Any agent can be primary agent (main, ruyi, custom agents)
  - Supervisor role is set automatically when skill is invoked
  - Recursion prevention: Supervisor agents cannot call cc-supervisor again
  - Files changed: `SKILL.md`, `supervisor_run.sh`, `logs/hook.env`

### Fixed
- **Hook session routing**: Clarified that hooks should notify the **caller** (sub agent), not Claude Code's internal session
  - Root cause: Confusion between two different session IDs:
    - `OPENCLAW_SESSION_ID` (env var) = caller's session (main/ruyi agent) ✓ Use this
    - `session_id` (hook JSON) = Claude Code's internal session ✗ Don't use for routing
  - Solution: Hook uses `OPENCLAW_SESSION_ID` environment variable to notify the caller
  - Changes:
    - `on-cc-event.sh`: Uses `OPENCLAW_SESSION_ID` (caller's session) for notifications
    - `supervisor_run.sh`: Writes `logs/hook.env` with caller's session ID for reliability
    - `on-cc-event.sh`: Auto-sources `logs/hook.env` if environment variables are missing
  - Architecture: Main agent → Sub agent → cc-supervisor skill → Claude Code (tool)
  - Hook notifications flow: Claude Code → Sub agent → (Sub agent decides) → Main agent
  - Impact: Notifications now correctly route to the skill caller (sub agent), not to Claude Code's internal session

- **Preflight check session ID validation**: Removed meaningless auto-generation of random session IDs
  - Previous behavior: When `OPENCLAW_SESSION_ID` was unavailable, preflight check would generate a random UUID
  - Problem: Random session IDs cannot deliver notifications correctly
  - New behavior: Preflight check now fails with clear error message if session ID is unavailable
  - Files changed: `scripts/preflight-check.sh`

### Documentation
- Added `docs/agent-hierarchy.md`: Comprehensive architecture documentation explaining:
  - Claude Code is a tool, not an agent
  - Hook notification routing logic
  - Session ID disambiguation
  - Call flow examples
  - Troubleshooting guide


