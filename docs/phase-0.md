# Phase 0 — Gather Inputs

**Purpose:** Collect required information from human before starting supervision.

---

## Required Inputs

Human must provide three pieces of information:

1. **Project directory** (absolute path)
   - Example: `/Users/username/Projects/my-app`
   - Must be an existing directory

2. **Task description**
   - What Claude Code should accomplish
   - Example: "Implement user login API"
   - Be specific and clear

3. **Mode** (optional, default: `relay`)
   - `relay` — Human makes all decisions (recommended for sensitive tasks)
   - `auto` — OpenClaw auto-handles only low-risk confirmations; anything ambiguous still escalates

---

## That's It!

No manual checks needed. Phase 1 handles everything else automatically:
- Session ID validation/retrieval
- Environment variable checks
- Hook installation
- tmux session startup

---

## Next Step

Once you have all three inputs, proceed to **Phase 1**.

**Read:** `docs/phase-1.md`
