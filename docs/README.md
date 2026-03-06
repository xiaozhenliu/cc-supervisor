# docs/ Directory

This directory contains documentation for cc-supervisor.

## Required Files (Included in Installation)

These files are **required** for the skill to function and are included when installing via `install.sh`:

### Mode Guides
- **`relay-mode.md`** - Detailed guide for relay mode operation (referenced by SKILL.md Phase 3)
- **`auto-mode.md`** - Detailed guide for auto mode operation (referenced by SKILL.md Phase 3)

### Phase Guides
- **`phase-0.md`** - Phase 0: Gather inputs (referenced by SKILL.md)
- **`phase-1.md`** - Phase 1: Start (automated) (referenced by SKILL.md)
- **`phase-2.md`** - Phase 2: Send initial task (referenced by SKILL.md)
- **`phase-3.md`** - Phase 3: Notification loop (referenced by SKILL.md)
- **`phase-4.md`** - Phase 4: Verify and report (referenced by SKILL.md)

### Reference
- **`openclaw-reference.md`** - OpenClaw CLI reference (referenced by CLAUDE.md)

## Development/Reference Files (Excluded from Installation)

These files are for development and reference only, **not** included in installation:

- `DESIGN_DECISIONS.md` - Design rationale and architectural decisions
- `preflight-checks.md` - Preflight check system documentation
- `archive/` - Historical design documents kept for reference only

## Installation Behavior

When running `install.sh`, the script:
1. Includes all files in `docs/` by default
2. Explicitly excludes development/reference files listed above
3. Ensures required files (`relay-mode.md`, `auto-mode.md`, `openclaw-reference.md`) are always installed

This ensures the skill has all necessary documentation while keeping the installation lean.
