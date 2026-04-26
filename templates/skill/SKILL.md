---
name: brain
description: Activate the automation brain for the current project. Use when user invokes /brain, asks to start/init/bootstrap a project with the brain, wants to see lessons or insights, or needs to scaffold a project from brain templates.
---

# Brain Skill — Automation Brain Activation

Single entry point for the automation brain system. Handles init, bootstrap, scaffolding, and viewing insights — all from inside Claude Code.

## When to use

- User says `/brain`, `/brain init`, `/brain bootstrap`, `/brain scaffold`, `/brain insights`, `/brain status`
- User asks "start this project with brain", "bootstrap this", "init brain here"
- User wants to import a project and have it inherit the Strategix automation brain
- User asks to see lessons, patterns, or cross-project insights

## Vault location

The automation brain vault is at: `~/vaults/automation-brain/`
GitHub: https://github.com/goldiejz/automation-brain

## Sub-commands

When user invokes `/brain <subcommand>`, follow the matching playbook below.

### `/brain` (default) or `/brain status`

1. Check current working directory has `.parent-automation/`
2. If yes, run: `bash ~/vaults/automation-brain/scripts/brain status`
3. If no, suggest `/brain init` and explain what it does
4. Show:
   - Snapshot version + lesson count
   - Decision log entry count
   - Vault commit hash

### `/brain init`

For initializing a project (new or imported) with brain integration.

1. Run: `bash ~/vaults/automation-brain/scripts/brain init`
2. Verify it created:
   - `.parent-automation/query-brain.ts`
   - `.parent-automation/new-project-bootstrap-v2.ts`
   - `.parent-automation/brain-snapshot/`
   - `.planning/bootstrap-decisions.jsonl`
3. Report success and offer next step: `/brain bootstrap` or `/brain scaffold`

### `/brain bootstrap`

Runs the 12-step brain-aware bootstrap (records decisions, doesn't scaffold files).

1. Run: `bash ~/vaults/automation-brain/scripts/brain bootstrap`
2. Show the cached templates that were applied
3. Show token savings (target: 7-15K vs 25K)
4. Confirm decision logged + Phase 6 triggered
5. Offer next step: `/brain scaffold` to actually create files

### `/brain scaffold`

**This is the action command** — actually writes files based on brain templates.

If the user hasn't given parameters, ask:
- Project type? (service-desk | revops | ops-intelligence | custom)
- Customer name?
- Project name?

Then:
1. Read the relevant cached templates from `.parent-automation/brain-snapshot/cache/query-responses/`:
   - `01-project-section-draft.md` → for `CLAUDE.md` Project section
   - `02-scope-definition.md` → for `CLAUDE.md` Scope section
   - `03-architecture-conventions.md` → for `CLAUDE.md` Architecture section
   - `04-rbac-structure.md` → for `src/lib/rbac.ts`
   - `05-constraints.md` → for `CLAUDE.md` Constraints section
   - `07-vault-structure.md` → for vault scaffold
   - `08-test-coverage.md` → for test setup
   - `09-anti-patterns.md` → for `CLAUDE.md` Anti-patterns

2. Read the project-type template from `.parent-automation/brain-snapshot/templates/[project-type]-template.md`

3. Apply lessons from `.parent-automation/brain-snapshot/lessons/` (especially L-018, L-020, L-021)

4. Generate these files in the project root:
   - `CLAUDE.md` — repo instruction (13-section template per project-standard.md)
   - `.planning/STATE.md` — primary truth file (initialize as Phase 0 bootstrap)
   - `.planning/PROJECT.md` — durable purpose
   - `.planning/ALPHA.md` — gate criteria
   - `.planning/ROADMAP.md` — phase sequencing
   - `.planning/REQUIREMENTS.md` — empty checklist
   - `tasks/todo.md` — initialized
   - `tasks/lessons.md` — initialized
   - `package.json` — with stack from project-type
   - `tsconfig.json`
   - `src/lib/rbac.ts` — centralized roles
   - `wrangler.toml` (if Cloudflare project)
   - Initial Drizzle schema in `src/db/schema.ts`

5. Run `npm install` if user agrees

6. Show summary: "Created X files, Y lines, Z dependencies. Next: `npm run dev`"

7. Run `brain bootstrap` again to log this scaffold decision

### `/brain insights`

Show cross-project patterns from Phase 6 observability.

1. Read: `~/vaults/automation-brain/observability/cross-customer-insights.md`
2. Read: `~/vaults/automation-brain/observability/lesson-effectiveness.md`
3. Show top 5 patterns + top 5 lessons by effectiveness

### `/brain lessons`

List all 55+ lessons in the vault.

1. Run: `bash ~/vaults/automation-brain/scripts/brain lessons`
2. If user asks about a specific lesson, read the file from `~/vaults/automation-brain/lessons/`

### `/brain sync`

Lightweight: just pull latest vault + refresh local snapshot.

1. Run: `bash ~/vaults/automation-brain/scripts/brain sync`
2. Show what was updated (vault commit before/after)

### `/brain phase-6`

Manually trigger Phase 6 observability daemon.

1. Run: `bash ~/vaults/automation-brain/scripts/brain phase-6`
2. Show output (patterns detected, lesson effectiveness updated)

### `/brain dev` or `/brain start`

Start the dev server for the current project.

1. Detect project stack from `package.json`:
   - `"dev": "wrangler dev"` → Cloudflare Workers
   - `"dev": "vite"` → Vite SPA
   - `"dev": "next dev"` → Next.js
2. Run `npm install` if `node_modules` doesn't exist
3. Run `npm run dev`
4. Show URL where dev server is running

## Important

- **Always run shell commands via `Bash` tool** — don't try to invoke `brain` as a slash command
- **Verify .parent-automation/ exists** before running bootstrap-dependent commands
- **For scaffold**: actually write files using `Write` tool — don't just describe what would happen
- **Preserve existing files** — if scaffolding would overwrite, ask first
- **After scaffolding, commit to git** with message like "Initial scaffold from brain templates (vault: <commit>)"

## Resources

- Vault: `~/vaults/automation-brain/`
- GitHub: https://github.com/goldiejz/automation-brain
- Per-project snapshot: `.parent-automation/brain-snapshot/`
- Decision log: `.planning/bootstrap-decisions.jsonl`
- Phase 6 outputs: `~/vaults/automation-brain/observability/`
