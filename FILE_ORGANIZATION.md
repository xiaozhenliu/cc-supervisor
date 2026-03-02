# cc-supervisor File Organization

## Installed in Skill (Runtime Files)

These files are copied to `~/.openclaw/skills/cc-supervisor/` during installation:

- `SKILL.md` - Skill definition and operational procedures
- `README.md` / `README_en.md` - User documentation
- `VERSION` - Version identifier
- `install.sh` - Installation script
- `scripts/` - All runtime scripts
- `config/` - Configuration templates

## Excluded from Skill (Development Files)

These files remain in the Git repository but are NOT installed:

- `CLAUDE.md` - AI development guidelines (for Claude Code development)
- `docs/` - All documentation in docs/ directory:
  - `docs/DESIGN_DECISIONS.md` - Design rationale and decisions
  - `docs/openclaw-reference.md` - OpenClaw CLI reference for developers
- `tests/` - Test files and fixtures
- `logs/` - Runtime logs (created during execution)
- `.git/` - Git repository metadata
- `.github/` - GitHub-specific files (workflows, templates)
- `*.backup*` - Backup files

## Rationale

**Runtime files** are needed for the skill to function when installed by end users.

**Development files** are for:
- Contributors who want to understand design decisions
- AI assistants (Claude) developing the skill
- Maintainers documenting the project

These development files should stay in the Git repository for reference but don't need to be distributed with the skill installation.
