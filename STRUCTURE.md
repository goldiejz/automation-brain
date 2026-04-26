# Canonical Directory Structure

**Status:** v1.0 — locked 2026-04-25

This is the authoritative structure for both the vault and any project that uses it. `ark align` enforces this on imported projects.

---

## Vault Structure (`~/vaults/ark/`)

```
automation-brain/
├── README.md                    Overview, getting started
├── STRUCTURE.md                 This file (canonical layout)
├── DEPLOYMENT_STATUS.md         Live deployment state
├── DEPLOYMENT_GUIDE.md          Step-by-step deployment
├── IMPLEMENTATION_COMPLETE.md   Architecture overview
├── 00-Index.md                  Obsidian navigation hub
├── package.json                 Node deps for ts-node
├── tsconfig.json                TypeScript config
│
├── lessons/                     KNOWLEDGE BASE
│   ├── universal/               Cross-project lessons (ALL projects benefit)
│   ├── by-customer/             Customer-scoped lessons
│   │   ├── strategix/
│   │   ├── customerA/
│   │   └── ...
│   └── auto-captured/           Session-extracted lessons (Stop hook output)
│
├── bootstrap/                   PROJECT TEMPLATES
│   ├── project-types/           Per-domain templates
│   │   ├── service-desk-template.md
│   │   ├── revops-template.md
│   │   └── ops-intelligence-template.md
│   ├── claude-md-sections.md    13-section CLAUDE.md template
│   └── anti-patterns.md         What to avoid
│
├── cache/                       TOKEN OPTIMIZATION
│   ├── query-responses/         Cached query templates (queryId → markdown)
│   │   ├── 01-project-section-draft.md
│   │   ├── 02-scope-definition.md
│   │   └── ...
│   ├── prompt-library/          Optimized prompts
│   ├── tier-selection-rules.md  Model selection decision tree
│   └── model-registry.json      Auto-updated model metadata
│
├── findings/                    AUDIT FINDINGS
│   ├── by-customer/
│   ├── schema-drift/
│   ├── rbac-lockout/
│   └── summary-by-date.md
│
├── doctrine/                    STANDARDS
│   └── shared-conventions.md    Universal rules (RBAC, currency suffix, etc.)
│
├── observability/               PHASE 6 OUTPUTS
│   ├── phase-6-daemon.ts        Pattern detection daemon
│   ├── phase-6-daemon-extended.ts  Model registry refresh
│   ├── phase-7-tier-resolver.ts    Model selection
│   ├── phase-7-multi-model-resolver.ts  Multi-CLI routing
│   ├── phase-7-model-registry.ts        Dynamic registry
│   ├── cross-customer-insights.md       Auto-generated patterns
│   ├── lesson-effectiveness.md          Per-lesson stats
│   ├── token-spend-log.md               Cost tracking
│   └── model-weight-adjustments.md      Weekly model changes
│
├── self-healing/                AUTONOMOUS REPAIR
│   ├── proposed/                AI-diagnosed fix proposals
│   └── applied/                 Auto-applied (high confidence)
│
├── templates/                   PROJECT-INSTALLABLE FILES
│   └── parent-automation/       What ark init copies into projects
│       ├── query-brain.ts
│       ├── new-project-bootstrap-v2.ts
│       └── tsconfig.json
│
├── scripts/                     CLI TOOLS
│   ├── brain                    Main entry point
│   ├── brain-sync.sh            Pull vault to project
│   ├── extract-learnings.sh     AI-powered session extraction
│   ├── self-heal.sh             AI-powered error diagnosis
│   └── generate-snapshot.sh     Create offline snapshot
│
├── hooks/                       CLAUDE CODE INTEGRATION
│   ├── brain-session-start.sh   SessionStart hook
│   ├── brain-session-end.sh     Stop hook (Phase 6 trigger)
│   ├── brain-extract-learnings.sh  Stop hook (lesson extraction)
│   └── brain-error-monitor.sh   Stop hook (error detection)
│
└── logs/                        Daemon execution logs (gitignored)
```

---

## Project Structure (any project using brain)

```
your-project/
├── .parent-automation/          BRAIN INTEGRATION
│   ├── brain-snapshot/          Offline copy of vault (synced via brain-sync)
│   │   ├── lessons/
│   │   ├── cache/query-responses/
│   │   ├── templates/
│   │   └── SNAPSHOT-MANIFEST.json
│   ├── query-brain.ts           Snapshot interface (copied from vault)
│   ├── new-project-bootstrap-v2.ts  Bootstrap with brain queries
│   └── tsconfig.json
│
├── .planning/                   PROJECT TRUTH FILES
│   ├── PROJECT.md               Durable purpose
│   ├── STATE.md                 Live implementation truth
│   ├── ALPHA.md                 Gate criteria
│   ├── ROADMAP.md               Phase sequencing
│   ├── REQUIREMENTS.md          Mandatory items
│   └── bootstrap-decisions.jsonl  Decision log (Phase 6 input)
│
├── tasks/                       WORK SURFACE
│   ├── todo.md                  Active backlog
│   └── lessons.md               Project-local lessons (legacy — synced to vault)
│
├── .claude/                     CLAUDE CODE LOCAL CONFIG
│   ├── settings.json            Project-specific overrides
│   └── agents/                  Project agents (if any)
│
├── src/                         PROJECT CODE (project-specific)
├── CLAUDE.md                    Repo instructions (13-section template)
└── package.json (or equivalent)
```

---

## What `ark align` Does

When run on an imported project, `ark align`:

1. **Detects existing structure** — scans for `.planning/`, `tasks/`, `lessons.md`, `CLAUDE.md`
2. **Migrates lessons** — moves any project-local `tasks/lessons.md` entries to `~/vaults/ark/lessons/by-customer/<customer>/`
3. **Standardizes filenames** — renames non-canonical files (e.g., `LEARNINGS.md` → `tasks/lessons.md`)
4. **Backfills missing files** — creates stub `STATE.md`, `PROJECT.md`, `ALPHA.md` from templates if missing
5. **Validates conventions** — checks for currency suffix, inline RBAC, tenant scoping per `doctrine/shared-conventions.md`
6. **Reports deviations** — writes `.planning/alignment-report.md` with what was changed and what needs review
7. **Logs decision** — adds an alignment entry to `bootstrap-decisions.jsonl` so Phase 6 sees the migration

Backups are created at `.parent-automation/pre-align-backup-<timestamp>/` before any changes.
