# Canonical Directory Structure

**Status:** v1.0 — locked 2026-04-25

This is the authoritative structure for both the vault and any project that uses it. `ark align` enforces this on imported projects.

---

## Vault Structure (`~/vaults/ark/`)

```
ark/
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

---

## AOS Escalation Contract

**Status:** locked 2026-04-26 (Phase 2 — AOS: Delivery Autonomy)

Phase 2 transition: Ark decides routine resource questions autonomously and escalates only true blockers via async queue. The contract below is locked — Phase 3+ observer-learners read these formats.

### True-blocker classes (only 4 reach the user)

| Class | Trigger | Decision function |
|-------|---------|-------------------|
| monthly-budget | Monthly token cap reached (>= 95% of `budget.monthly_escalate_pct` of monthly_cap_tokens) | `policy_budget_decision` → `ESCALATE_MONTHLY_CAP` |
| architectural-ambiguity | Phase has 0 actionable tasks AND policy has no preference | `policy_zero_tasks` → `ESCALATE_AMBIGUOUS` |
| destructive-op | Force-push, drop data, production deploy | (no policy fn — script-local guard with `--confirm`) |
| repeated-failure | Same task fails self-heal max times (default 3) | `policy_dispatch_failure` → `ESCALATE_REPEATED` |

All other questions (BLACK-tier with monthly headroom, CLI quota exhaustion, dispatch routing, zero-task phases, single retries) are decided by the policy engine without prompting.

### Queue location

`~/vaults/ark/ESCALATIONS.md` — created on first escalation. Section format (regex-stable):

```
## ESC-YYYYMMDD-HHMMSS-<6char-rand> — <class> — <open|resolved>
**Created:** <ISO8601 UTC>
**Class:** <class>
**Title:** <one-line>

<body>

---
```

User reviews via `ark escalations` (list/show/resolve). Phase 7 will consume responses written back to the file.

### Audit log

Every policy decision writes one JSON line to `~/vaults/ark/observability/policy-decisions.jsonl`. Schema (locked, `schema_version=1`):

```json
{
  "ts": "<ISO8601 UTC>",
  "schema_version": 1,
  "decision_id": "<YYYYMMDDTHHMMSSZ>-<16-hex>",
  "class": "<budget|dispatch|zero_tasks|dispatch_failure|escalation|self_heal>",
  "decision": "<UPPER_SNAKE_CASE>",
  "reason": "<machine_readable_token_pattern>",
  "context": <json-object-or-null>,
  "outcome": null,
  "correlation_id": null
}
```

Field semantics:

| Field | Phase 2 writer | Phase 3 reader |
|-------|----------------|----------------|
| `ts` | ISO8601 UTC, set by `_policy_log` | Read |
| `schema_version` | Always `1` | Branch on this |
| `decision_id` | Auto-generated unique ID per line. Format: `%Y%m%dT%H%M%SZ-XXXXXXXXXXXXXXXX` (compact ts + 16-hex from `/dev/urandom`, 64-bit entropy). Phase 3 patches `outcome` keyed on this ID. | Patch target |
| `class` | One of the listed enum values | Filter by this |
| `decision` | UPPER_SNAKE_CASE return value of the decision fn | Read |
| `reason` | Machine-readable token pattern (no free text; greppable) | Cluster patterns by this |
| `context` | Decision-specific JSON object (input args, derived values), or `null` | Feature input for learner |
| `outcome` | ALWAYS `null` in Phase 2 | Phase 3 patches this to `"success"` / `"failure"` / `"ambiguous"` after observing the result |
| `correlation_id` | `null` by default; caller may pass a prior `decision_id` to link causally-related decisions | Reconstruct decision chains |

Decision values per class:
- **budget:** `AUTO_RESET` | `PROCEED` | `ESCALATE_MONTHLY_CAP`
- **dispatch:** `codex` | `gemini` | `haiku-api` | `claude-session` | `regex-fallback`
- **zero_tasks:** `SKIP_LOGGED` | `ESCALATE_AMBIGUOUS`
- **dispatch_failure:** `RETRY_NEXT_TIER` | `SELF_HEAL` | `ESCALATE_REPEATED`
- **escalation:** `<class-name>`
- **self_heal:** `RETRY_1_ENRICHED` | `RETRY_2_MODEL_ESCALATE` | `RETRY_3_ESCALATE_QUEUE`

**Why these fields ship in Phase 2:** Phase 3 (self-improving self-heal) needs to (a) tag each decision with its eventual outcome and (b) reconstruct chains of related decisions. Doing this retroactively requires a stable per-line ID and a chain-link field. Adding them after Phase 2 ships would either break `schema_version=1` or require Phase 3 to do log-rewrites without keys. Shipping them now (with `null` defaults) means Phase 2 writes complete records that Phase 3 can patch in place.

### Cascading config

Resolution order (highest wins):

1. Env var (`ARK_<UPPER_SNAKE>`)
2. `<project>/.planning/policy.yml`
3. `~/vaults/ark/policy.yml`
4. Built-in defaults in `scripts/ark-policy.sh`

Keys consumed today: `budget.monthly_escalate_pct`, `self_heal.max_retries`, `budget.phase_cap_default`, `budget.monthly_cap_default`. Keys may be added; existing keys MUST NOT change semantics.

### Layered self-heal contract

`scripts/self-heal.sh --retry <task_id> <prompt> <output>` implements three layers, gated by file-backed retry count at `<phase_dir>/self-heal-retries-<task_id>.txt`:

1. **Retry 1 (count==0 → 1):** enriched prompt — appends `lessons.md` tail + last error blob to the prompt, dispatches via the same dispatcher. Audit `class:self_heal`, `decision:RETRY_1_ENRICHED`.
2. **Retry 2 (count==1 → 2):** model escalate — `policy_dispatcher_route deep` picks next-tier dispatcher, dispatches with the original prompt. Audit `decision:RETRY_2_MODEL_ESCALATE`.
3. **Retry 3 (count==2 → 3):** queue escalation — `ark_escalate repeated-failure`, exits 2. Audit `decision:RETRY_3_ESCALATE_QUEUE`.

`ark-team.sh`'s `dispatch_role` runs an in-process retry loop (count_file reset per `ark team` invocation, 4 dispatches max per role). The two retry surfaces do NOT overlap: ark-team handles single-role dispatcher-swap retries within an invocation; `self-heal.sh` handles task-level cross-invocation retries.

All `class:self_heal` audit lines go through `_policy_log` from sourced `ark-policy.sh` — single writer, single schema (no parallel `_self_heal_log` helper).

### Observer pattern

`manual-gate-hit` (severity: critical, lesson_after_n: 1) — fires on any future occurrence of `read -p`, `read -r`, `press any key`, `continue?`, `(y/N)` in delivery-path log files. Existing intentional gates are tagged `# AOS: intentional gate` in source.

### Cross-references

- Decision functions: `scripts/ark-policy.sh` (`policy_budget_decision`, `policy_dispatcher_route`, `policy_zero_tasks`, `policy_dispatch_failure`)
- Escalation queue helper: `scripts/ark-escalations.sh`
- Layered retry: `scripts/self-heal.sh --retry`
- Verify coverage: Tier 8 in `scripts/ark-verify.sh` (autonomy under stress)
- Plan-level history: `.planning/phases/02-autonomy-policy/02-01..02-09-SUMMARY.md`

---

## AOS Self-Improving Self-Heal Contract (Phase 3)

**Status:** locked 2026-04-26 (Phase 3 — AOS: Self-Improving Self-Heal)

Phase 3 closes the policy feedback loop. The audit log written by `_policy_log` (Phase 2) is read by a learner that scores patterns, auto-promotes the high-success ones into `~/vaults/ark/policy.yml`, and auto-deprecates the duds. The system improves itself without losing the schema lock or the true-blocker contract.

### Components

| Component | Path | Role |
|---|---|---|
| Outcome tagger | `scripts/lib/outcome-tagger.sh` | SINGLE writer for the `outcome` field; reads delivery logs + git history within a configurable window (default 10 min) and patches `outcome` via `UPDATE decisions SET outcome=... WHERE decision_id=?`, idempotent (the patch is a no-op if `outcome IS NOT NULL`) |
| Policy learner | `scripts/policy-learner.sh` | Aggregates tagged decisions into `(class, decision, dispatcher, complexity)` patterns via SQL `GROUP BY`; emits promote/deprecate candidates to `observability/policy-evolution-pending.jsonl` |
| Auto-patcher | inside `policy-learner.sh::learner_apply_pending` | Applies pending candidates to `~/vaults/ark/policy.yml` under a mkdir-lock (macOS-safe; no `flock` dep), atomic-write via `mv tmp policy.yml`, commits each patch to the vault git repo, emits `_policy_log self_improve PROMOTED|DEPRECATED` audit entry |
| Digest writer | `scripts/lib/policy-digest.sh` (`learner_write_digest`) | Writes `~/vaults/ark/observability/policy-evolution.md` (Promoted, Deprecated, Mediocre sections); idempotent |

### Audit-log substrate (Phase 2.5 SQLite)

Phase 2.5 migrated `~/vaults/ark/observability/policy-decisions.jsonl` to SQLite at `~/vaults/ark/observability/policy.db`. Schema is preserved 1-for-1 (`schema_version=1`, every Phase 2 field is a column). Phase 3 reads + patches via `sqlite3` rather than `jq`. The JSONL form remains the canonical wire/log format for new writes; Phase 3 reads the materialized DB.

Per SUPERSEDES.md, all synthetic fixtures and Tier 9 checks use `INSERT INTO decisions ...` against an isolated tmp `policy.db`, not JSONL heredocs.

### Outcome lifecycle

```
NULL
  ↓ outcome-tagger.sh runs (post-phase or `ark learn`)
  ↓ heuristic: subsequent dispatch success in same phase     → "success"
  ↓ heuristic: matching `class:escalation` line              → "failure"
  ↓ heuristic: no follow-up signal within window             → "ambiguous"
"success" | "failure" | "ambiguous"  (patched in place; idempotent)
```

The tagger is the SINGLE writer for `outcome`; nothing else mutates this column.

### Self-improving learner (thresholds)

- **Promote:** `count >= 5 AND success_rate >= 0.80`
- **Deprecate:** `count >= 5 AND success_rate <= 0.20`
- **Ignore (mediocre middle):** `0.20 < success_rate < 0.80` OR `count < 5`

Hardcoded for Phase 3 — configurable via `policy.yml` is deferred until data justifies it (CONTEXT.md decision #4).

### True-blocker classes are NEVER auto-patched

The 4 escalation classes from the Phase 2 contract (monthly-budget, architectural-ambiguity, destructive-op, repeated-failure) are filtered out at SQL aggregation time AND re-checked at apply time (defense in depth). SQL filter: `class NOT IN ('escalation','self_improve')`. Apply-time filter rechecks `class == "escalation"` OR `(class == "budget" AND decision == "ESCALATE_MONTHLY_CAP")`.

### Auto-patch contract

`learner_apply_pending` is the only function that writes `~/vaults/ark/policy.yml`. Its contract:

1. **mkdir-lock** at `$VAULT_PATH/.policy-yml.lock` (30 s timeout). Two simultaneous learner runs serialize through this lock; neither corrupts policy.yml.
2. **Atomic write:** `python3 + PyYAML` produces the patched YAML to a `.tmp` file in the same directory, then `mv tmp policy.yml`. Partial writes are impossible.
3. **Vault git commit:** `git -C $VAULT_PATH commit policy.yml -m "self_improve: ..."` — every auto-patch is reversible via `git revert`. If `$VAULT_PATH` is not a git repo, the commit is a graceful no-op (Tier 9 isolation depends on this).
4. **Audit entry:** one `_policy_log self_improve PROMOTED|DEPRECATED` line per patch.

### Schema commitment (NO change from Phase 2)

`schema_version` stays at `1`. Phase 3 patches `outcome` in place. The `class` value `self_improve` is a NEW value (used by auto-patch audit entries) — this is not a schema migration; the column is `TEXT`/free-form by design.

Audit values for `class:self_improve`:
- `decision`: `PROMOTED` or `DEPRECATED`
- `reason`: `rate_pct_<NN>_count_<N>`
- `context`: `{class, decision, dispatcher, complexity, rate_pct, count}`
- `correlation_id`: the FIRST `decision_id` from the input set (chains the learning back to evidence)

### Run cadence

- **Post-phase:** `scripts/ark-deliver.sh::run_phase` invokes the learner with a windowed `--since` (default 1 h ago) after `update_state`. Non-fatal — learner failure does not fail the phase. Output redirected to `.planning/delivery-logs/learner-phase-N.log`.
- **Manual:** `ark learn` (default: last 7 days), `ark learn --full`, `ark learn --since DATE`, `ark learn --tag-first` (run outcome-tagger before scoring).

### Verification (Tier 9)

Tier 9 in `scripts/ark-verify.sh` runs a synthetic-fixture pipeline test in an isolated tmp vault (mirrors Phase 2 NEW-W-1 isolation pattern) and asserts:
- 5/83% pattern → promotion
- 5/17% pattern → deprecation
- 5/50% pattern → no-op (mediocre middle)
- true-blocker classes (`budget+ESCALATE_MONTHLY_CAP`, `class:escalation`) → no-op
- real vault `policy.db` md5 unchanged after the test (isolation guarantee)
- idempotent re-run: zero new `self_improve` audit entries

20 checks total. Tier 1–8 retained.

### Cross-references

- Decision functions: `scripts/policy-learner.sh::{learner_score_patterns, learner_emit_promotions, learner_emit_deprecations, learner_apply_pending, learner_run}`
- Outcome inference: `scripts/lib/outcome-tagger.sh::{outcome_classify, outcome_tag_decision, outcome_tag_window}`
- Digest: `scripts/lib/policy-digest.sh::{learner_write_digest}`
- Tier 9 verify: `scripts/ark-verify.sh` (search "Tier 9")
- Plan history: `.planning/phases/03-self-improving-self-heal/{03-01..03-08}-SUMMARY.md`
- Substrate notes: `.planning/phases/03-self-improving-self-heal/SUPERSEDES.md`
