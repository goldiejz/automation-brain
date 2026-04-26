---
name: ark
description: Autonomous project delivery system. Activate when user invokes /brain, asks to scaffold/build/deliver a project, integrates GSD/Superpowers workflows, or wants brain-managed project lifecycle (design→build→deploy→learn). The brain orchestrates GSD phases + Superpowers practices into one autonomous pipeline.
---

# Ark Skill — Autonomous Project Delivery

The brain is the orchestration layer that converts a design (from `/superpowers:brainstorming` or `/gsd-new-project`) into a fully delivered project — scaffolded, built, tested, deployed, and continuously learning.

## When to use

- User says `/brain`, `/ark create`, `/ark deliver`, `/ark init`, etc.
- User wants to scaffold a new project ("create a service desk for acme")
- User wants to build phases autonomously ("run phase 1", "deliver this project")
- User just finished a brainstorm/spec and wants to start building
- User asks about lessons, insights, or cross-project patterns
- Any project lifecycle action: design → build → deploy

## Vault location

- Vault: `~/vaults/ark/`
- GitHub: https://github.com/goldiejz/ark
- All vault writes auto-commit + push

## The Autonomous Pipeline

```
DESIGN PHASE
  /superpowers:brainstorming  → captures vision in chat
  OR /gsd-new-project          → generates ROADMAP.md with phases
  ↓
SCAFFOLD PHASE
  /ark create <name> --type <type> --customer <customer>
  → Writes CLAUDE.md, .planning/, src/lib/rbac.ts, package.json
  → git init + GitHub repo + brain integration
  ↓
DELIVERY PHASE (per ROADMAP phase)
  /ark deliver
  → For each phase:
    1. /gsd-plan-phase (or AI dispatch)
    2. /gsd-execute-phase (or Codex direct)
    3. /superpowers:test-driven-development (write tests first)
    4. brain verify (npm test + tsc)
    5. brain self-heal (if failure)
    6. brain deploy (wrangler/npm)
    7. /superpowers:verification-before-completion
    8. brain commit + push (atomic per phase)
    9. STATE.md updated
  ↓
LEARN PHASE (continuous)
  Stop hook auto-fires:
    → brain-extract-learnings (regex/AI)
    → Phase 6 daemon detects patterns
    → Vault updated, lessons available to next project
```

## Sub-commands

### `/brain` (default) or `/ark status`

1. Run: `bash ~/vaults/ark/scripts/ark status` via Bash tool
2. Show snapshot version, lesson count, decision count
3. If no `.parent-automation/`, suggest `/ark init`

### `/ark create`

**This is the autonomous scaffold command.**

Required: project name + type + customer

If user hasn't specified, ask:
- Project name?
- Type? (`service-desk` | `revops` | `ops-intelligence` | `custom`)
- Customer name?

Then run via Bash:
```bash
bash ~/vaults/ark/scripts/ark create <name> \
  --type <type> --customer <customer>
```

This writes ALL files (CLAUDE.md, .planning/*, src/lib/rbac.ts, package.json, wrangler.toml, etc.), creates GitHub repo, and integrates brain.

After: tell user `cd <path>` and run `/ark deliver` to start autonomous build.

### `/ark deliver`

**This is the autonomous build command.**

Run via Bash:
```bash
bash ~/vaults/ark/scripts/ark deliver
```

The script reads ROADMAP.md and runs each phase autonomously. If ROADMAP isn't detailed enough, suggest user run `/gsd-plan-phase 1` first to populate Phase 1.

For each phase, the brain:
1. **Plans** — dispatches Codex or invokes `/gsd-plan-phase`
2. **Executes** — dispatches code generation
3. **Verifies** — runs tests, type checks
4. **Self-heals** — auto-fixes failures via Codex/Gemini
5. **Deploys** — wrangler or npm run deploy
6. **Commits** — atomic per phase, pushed to GitHub

Variants:
- `/ark deliver --phase N` — single phase only
- `/ark deliver --resume` — continue from last completed
- `/ark deliver --from-spec FILE` — start from brainstorm output

### `/ark init`

For projects that aren't scaffolded yet (existing imported codebase):
```bash
bash ~/vaults/ark/scripts/ark init
```

Sets up `.parent-automation/`, copies query-brain.ts + bootstrap-v2.ts, syncs snapshot.

### `/ark align`

For imported projects with non-canonical structure:
```bash
bash ~/vaults/ark/scripts/ark align
```

Standardizes: renames LEARNINGS.md → tasks/lessons.md, scans all .md files (including symlinks), generates doc-inventory.md, migrates project lessons to vault.

### `/ark doctor`

Comprehensive health check:
```bash
bash ~/vaults/ark/scripts/ark doctor
```

27 checks: vault, scripts, hooks, registration, AI tools, Phase 6, project integration. Returns exit code for CI use.

### `/ark bootstrap`

Manual decision logging (records that you started a project, doesn't write files):
```bash
bash ~/vaults/ark/scripts/ark bootstrap
```

Use this if you want to record a decision without scaffolding. Most users want `/ark create` instead.

### `/ark insights`

Show cross-project patterns from Phase 6:
```bash
bash ~/vaults/ark/scripts/ark insights
```

### `/ark lessons`

List all lessons in the brain:
```bash
bash ~/vaults/ark/scripts/ark lessons
```

### `/ark phase-6`

Manually trigger Phase 6 daemon:
```bash
bash ~/vaults/ark/scripts/ark phase-6
```

### `/ark sync`

Pull latest vault from GitHub:
```bash
bash ~/vaults/ark/scripts/ark sync
```

## Integration with other skills

### After `/superpowers:brainstorming`
The brainstorm produces a spec in chat. Invoke:
```
/ark create <name> --type custom --customer <user>
# Then edit .planning/PROJECT.md with the spec
/ark deliver
```

### After `/gsd-new-project`
GSD generates ROADMAP.md with phases. Invoke:
```
/ark create <name> --type <detected-type> --customer <user>
# .planning/ already populated by GSD
/ark deliver
```

### Combined with `/gsd-autonomous`
GSD has its own autonomous mode. Ark deliver complements by:
- Running brain-sync before each phase (gets latest patterns)
- Running self-heal after each phase failure
- Auto-deploying after each successful phase
- Recording decisions for cross-project learning

User can choose:
- `/gsd-autonomous` for pure GSD workflow
- `/ark deliver` for brain-orchestrated (calls GSD as needed)

### Combined with Superpowers
Ark deliver always uses these Superpowers patterns:
- `/superpowers:test-driven-development` — tests first, always
- `/superpowers:verification-before-completion` — at verify step
- `/superpowers:requesting-code-review` — after each phase commits
- `/superpowers:systematic-debugging` — when self-heal escalates

## Important rules

1. **Always invoke via Bash tool** — never try to run `brain` as a slash command
2. **Verify .parent-automation/ exists** before deliver/bootstrap commands
3. **Confirm with user before destructive ops** — `ark create` overwrites, `ark align` moves files
4. **Preserve existing customizations** — ark init/align always backs up first
5. **After scaffolding** — actually edit the stub files with real content using `Write` and `Edit` tools
6. **For deliver failures** — read self-healing/proposed/ and apply fixes manually if auto-apply didn't work
7. **Auto-commits are normal** — vault commits to GitHub continuously without user prompt

## Resources

- Vault: `~/vaults/ark/`
- Scripts: `~/vaults/ark/scripts/brain*.sh`
- Hooks: `~/.claude/hooks/brain-*.sh`
- Templates: `~/vaults/ark/templates/`
- Lessons: `~/vaults/ark/lessons/`
- Phase 6 outputs: `~/vaults/ark/observability/`
- Self-heal proposals: `~/vaults/ark/self-healing/proposed/`

## Flow Summary

User says: "build me an acme service desk"

You:
1. Confirm: type=service-desk, customer=acme
2. Run: `! ark create acme-service-desk --type service-desk --customer acme`
3. Help user define real scope: Use `Edit` tool to update `.planning/PROJECT.md` and `.planning/ROADMAP.md`
4. Run: `! ark deliver` (kicks off autonomous build)
5. Monitor progress, intervene if self-heal escalates
6. Final: GitHub repo with working deployed app
