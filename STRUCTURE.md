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

---

## AOS Bootstrap Autonomy Contract (Phase 4)

**Status:** locked 2026-04-26 (Phase 4 — AOS: Bootstrap Autonomy)

Phase 4 closes the **creation** gate. Where Phase 2 made `ark deliver` prompt-free for routine resource decisions and Phase 3 made the policy engine self-improving, Phase 4 makes `ark create` accept a one-line natural-language description and infer project-type / stack / deploy / customer with zero prompts. The same audit-log substrate (`policy.db`, `schema_version=1`, `_policy_log`) is reused — bootstrap decisions are first-class citizens of the Phase-3 learner pipeline.

### Components

| Component | Path | Role |
|---|---|---|
| Inference engine | `scripts/bootstrap-policy.sh` | Sourceable library; orchestrator `bootstrap_classify` returns TSV verdict + emits `_policy_log "bootstrap"` audit entry. Sub-functions: `bootstrap_infer_type` (keyword-overlap heuristic), `bootstrap_infer_stack` (template default + override), `bootstrap_infer_deploy` (type→target + customer override), `bootstrap_infer_customer` ("for `<name>`" parser → sanitized slug or `scratch`) |
| Project-type templates | `bootstrap/project-types/*-template.md` | YAML frontmatter — `keywords:`, `default_stack:`, `default_deploy:` — is the SINGLE source of inference signal. No hard-coded keyword tables in code. `custom-template.md` is the empty-keyword catch-all |
| CLAUDE.md template | `bootstrap/claude-md-template.md` + `bootstrap/claude-md-addendum/<type>.md` | Anchor-based composition: base template has named anchors (`{{ADDENDUM}}`, `{{CUSTOMER_FOOTER}}`, etc.); `sed /anchor/r file ; /anchor/d` pipeline assembles base + addendum + customer footer atomically |
| Customer layer | `scripts/lib/bootstrap-customer.sh` + `scripts/lib/policy-config.sh` | mkdir-lock-protected first-time customer-dir init (Phase-3 lock pattern); cascading layer slots between project and vault. Resolution order: `env > project > customer > vault > default` |
| Bootstrap entrypoint | `scripts/ark-create.sh` | Description-mode (zero prompts) + flag-mode (backward-compat) both pass through `bootstrap_classify`; CLAUDE.md and `.planning/policy.yml` written via `tmp.$$ + mv` (atomic); each invocation emits `_policy_log "bootstrap" RESOLVED_FINAL` (description-mode) or `FLAG_OVERRIDE` (flag-mode) |
| Production-side-effect gate | `ARK_CREATE_GITHUB` env var | `gh repo create` is GUARDED. Default UNSET → no GitHub repo created (smoke tests, verifications, and isolated bootstraps are safe). Opt-in only for real publishing. Added after Plan 04-04 incident: an unguarded `gh repo create` call previously created `github.com/goldiejz/acme-sd` during a smoke test |

### Inference contract

`bootstrap_classify "<description>" "<customer-or-empty>"` returns one TSV line on stdout:

```
<project_type>\t<stack>\t<deploy>\t<customer>\t<confidence_pct>\t<verdict>
```

Verdict values:
- `RESOLVED_FINAL` — confidence ≥ threshold; ark-create proceeds with inferred values
- `FLAG_OVERRIDE` — flag-mode call; flags supersede inference
- `LOW_CONFIDENCE` — score < threshold; emit `architectural-ambiguity` escalation, exit 2

Threshold default 50; overridable via `ARK_BOOTSTRAP_CONFIDENCE_THRESHOLD_PCT` (env) or `bootstrap.confidence_threshold_pct` (any policy.yml layer). Custom catch-all uses threshold 0 by design.

### Audit-log class semantics

Class `bootstrap` joins `budget`, `dispatch`, `zero_tasks`, `dispatch_failure`, `escalation`, `self_heal`, `self_improve` as a Phase-3-readable class. Decision values:

- `CLASSIFY_CONFIDENT` — `bootstrap_infer_type` chose a template above threshold (intermediate signal during classification)
- `RESOLVED_FINAL` — description-mode call produced a valid scaffold; full inferred values in `context`
- `FLAG_OVERRIDE` — flag-mode call; user-supplied flags recorded in `context` for traceability

`reason` is the machine-readable token pattern (e.g., `score_80_pct_threshold_50`); `context` is a JSON object with `{description, type, stack, deploy, customer, score, threshold}`. Phase-6 cross-customer learning will read these rows to promote durable bootstrap heuristics.

### Cascading customer layer (cascading config extension)

The Phase-2 cascading config resolver (`scripts/lib/policy-config.sh`) gains one layer:

```
1. Env var (ARK_<UPPER_SNAKE>)
2. <project>/.planning/policy.yml
3. ~/vaults/ark/customers/<customer>/policy.yml   ← NEW (Phase 4)
4. ~/vaults/ark/policy.yml
5. Built-in defaults in scripts/ark-policy.sh
```

Customer detected from `ARK_CUSTOMER` env, then `bootstrap.customer` in any project policy.yml, else fallback to `scratch`. First project for a new customer creates `<customer>/policy.yml` under mkdir-lock with `customer.name` + `customer.created` + commented examples. Idempotent on re-creation.

### Atomic-write discipline

Every Phase-4 file write follows `write tmp.$$ → mv`:
- `<project>/CLAUDE.md` — sed assembly pipeline outputs to `CLAUDE.md.tmp.$$`, then `mv`
- `<project>/.planning/policy.yml` — heredoc to `policy.yml.tmp.$$`, then `mv`
- `<project>/package.json` — same pattern
- `<customer>/policy.yml` — first-init seed via tmp+mv, mkdir-locked

Partial writes are impossible. CLAUDE.md is never overwritten silently — pre-existing CLAUDE.md is a destructive-op escalation.

### Verification (Tier 10)

Tier 10 in `scripts/ark-verify.sh` runs 5 description-mode fixtures + 1 flag-mode + 1 cascading-customer + 1 low-confidence + isolation guarantees, in an isolated tmp `ARK_HOME` (mirrors NEW-W-1 from Phase 2):

- Fixture 1: service-desk (`"service desk for testco"`) → service-desk template, score ≥ threshold, valid CLAUDE.md + policy.yml
- Fixture 2: revops (`"sales pipeline and quoting for foo"`) → revops template
- Fixture 3: ops-intelligence (`"managed-print SLA and incident dashboard"`) → ops-intelligence (threshold 30 for this fixture)
- Fixture 4: custom catch-all (`"one-off cli tool"`) → custom template (threshold 0)
- Fixture 5: garbled (`"garbled xyzzy nonsense quux"`) → exit 2 + `ESCALATIONS.md` `architectural-ambiguity` row
- Audit assertion: ≥4 `class:bootstrap` rows after the 5-fixture run
- Backward-compat: `ark create test --type custom --stack node-cli --deploy none` → project produced + `FLAG_OVERRIDE` audit row
- Customer cascading: project under customer with `bootstrap.confidence_threshold_pct: 80` overrides default (95 fallback) — read-back proves customer layer wins
- `read -p` audit: 0 occurrences in `ark-create.sh`, `bootstrap-policy.sh`, `bootstrap-customer.sh`, `policy-config.sh`
- `ARK_CREATE_GITHUB` UNSET throughout; real `~/vaults/ark/observability/policy.db` md5 unchanged before/after Tier 10

22 checks total. Tier 1–9 retained.

### Cross-references

- Inference functions: `scripts/bootstrap-policy.sh::{bootstrap_classify, bootstrap_infer_type, bootstrap_infer_stack, bootstrap_infer_deploy, bootstrap_infer_customer}`
- Customer layer: `scripts/lib/bootstrap-customer.sh::{bootstrap_customer_dir, bootstrap_customer_resolve_policy, bootstrap_customer_init}`
- Cascading config (extended): `scripts/lib/policy-config.sh::{policy_config_get, policy_config_has}`
- Bootstrap entrypoint: `scripts/ark-create.sh` (description-mode block + flag-mode block + sed-assembly pipeline)
- Tier 10 verify: `scripts/ark-verify.sh` (search "Tier 10")
- Plan-level history: `.planning/phases/04-bootstrap-autonomy/{04-01..04-08}-SUMMARY.md`
- Production-side-effect note: 04-04-SUMMARY.md "Production-side-effect incident (handled)" section

## AOS Portfolio Autonomy Contract (Phase 5)

**Status:** locked 2026-04-26 (Phase 5 — AOS: Portfolio Autonomy)

Phase 5 closes the **portfolio-selection** gate. Where Phase 2 made `ark deliver` prompt-free for routine resource decisions inside a project, Phase 3 made the policy engine self-improving, and Phase 4 made `ark create` description-driven, Phase 5 makes `ark deliver` (no args, no project named) pick the highest-leverage project from the portfolio and run its next phase. Same audit substrate (`policy.db`, `_policy_log`, `schema_version=1`) — `class:portfolio` joins `bootstrap`, `dispatch`, `budget`, `self_heal`, `self_improve`.

### Entry point

`ark deliver` invoked with no `--phase` and no project from outside any `.planning/`-bearing directory. The dispatcher detects no `PROJECT_DIR` and routes through `portfolio_decide` instead of single-project `run_phase`.

### Components

| Component | Path | Role |
|---|---|---|
| Portfolio engine | `scripts/ark-portfolio-decide.sh` | Sourceable library; orchestrator `portfolio_decide` discovers candidates, scores them, applies budget + cool-down filters, and emits the SELECTED winner path. Sub-functions: `_portfolio_discover` (find projects with `.planning/STATE.md` under `${ARK_PORTFOLIO_ROOT:-~/code}`, max depth 3), `_portfolio_attribute_customer` (read `bootstrap.customer` from project policy.yml; missing → `scratch`), `_portfolio_score` (heuristic), `_portfolio_budget_headroom` (cascading-config read of customer monthly cap vs used), `_portfolio_ceo_priority` (basename-match `## Next Priority` in programme.md), `_portfolio_recently_deferred` (sqlite SELECT against `class:portfolio` audit), `portfolio_pick_winner` (filter + tie-break) |
| Deliver routing | `scripts/ark-deliver.sh` | No-args branch sources `ark-portfolio-decide.sh` and invokes `portfolio_decide`. PROJECT_DIR detection appears textually before the `portfolio_decide` call (Tier 11 static-grep gate). `--phase N` and in-project invocations bypass the engine entirely (backward compat) |
| Audit class | `_policy_log "portfolio" ...` | Single-writer through `scripts/lib/policy-db.sh`. 4 decision values |
| Env config | `ARK_PORTFOLIO_ROOT` | Override default `~/code` portfolio root. Used by Tier 11 to point at synthetic mktemp fixture |

### Priority formula

```
priority = stuckness * 3
         + falling_health * 2
         + (monthly_headroom > 20 ? 1 : 0)
         + ceo_priority * 5
```

Signal sources:
- `stuckness` (0|1|2): `status: blocked` in STATE.md frontmatter = 2; mtime of STATE.md > 7d = 1; else 0
- `falling_health` (0|1): pass-count regression detected in newest delivery log under `.planning/delivery-logs/`
- `monthly_headroom` (0..100): `100 - (used / cap * 100)` from customer policy.yml; cascading-config-resolved; ≥ 80% used → headroom 0 → DEFERRED_BUDGET
- `ceo_priority` (0|1): basename match against `## Next Priority` heading in `${ARK_PROGRAMME_MD:-~/vaults/StrategixMSPDocs/programme.md}`; +5 score boost when match (NOT a budget override — budget filter is hard, see "Observed contract" below)

**Tie-break:** highest mtime of `.planning/STATE.md` wins (most-recently-touched).

### Decision classes (audit values)

All emitted via single-writer `_policy_log "portfolio" "<DECISION>" ...`:

1. **`SELECTED`** — winner picked. `context_json` includes: chosen_project, chosen_customer, total_score, stuckness, falling_health, monthly_headroom, ceo_priority, candidates_count.
2. **`DEFERRED_BUDGET`** — customer ≥ 80% monthly cap. Project skipped from winner pool. One row per over-cap project per `portfolio_decide` call.
3. **`DEFERRED_HEALTHY`** — top non-budget-deferred candidate had no actionable signals (score == 0 across stuckness/falling_health/ceo_priority). Project skipped; cool-down armed.
4. **`NO_CANDIDATE_AVAILABLE`** — no projects discovered under root, or all candidates filtered. Caller may escalate `architectural-ambiguity`.

### Cool-down rule

A project DEFERRED in the last 24h for the same reason class is skipped on the next decision pass. Implemented as a read-only `sqlite3 SELECT` against the audit DB at `~/vaults/ark/observability/policy.db`, filtering for `class='portfolio' AND decision IN ('DEFERRED_BUDGET','DEFERRED_HEALTHY') AND ts > now-24h AND context_json LIKE '%<basename>%'`. Tier 11 run3 (1h-old DEFERRED_HEALTHY → still cool) and run4 (25h-old → expired) both green.

### CEO directive — observed contract

Per Tier 11 run2: with `programme.md::## Next Priority` pointing to a project whose customer is over the 80% monthly cap:
- `_portfolio_ceo_priority(project)` → 1 → +5 score boost
- `_portfolio_budget_headroom(customer)` → 0 (over-cap)
- `portfolio_pick_winner` filters rows where headroom ≤ 0 → CEO-favored project excluded from winner pool
- A non-CEO healthy project from a budget-eligible customer wins by default

**The budget filter is hard. CEO directive is a *score* boost, not an *override*.** A future plan that wants CEO to override a DEFERRED_BUDGET decision is a contract change. Tier 11 documents the current behavior.

### Backward compat

- `ark deliver --phase N` from inside any directory → unchanged; bypasses portfolio
- `ark deliver` from inside a project (`.planning/STATE.md` + `.planning/ROADMAP.md` present) → unchanged; bypasses portfolio
- `ark deliver` from outside any project → NEW: routes through `portfolio_decide`
- Static guarantee: `grep -n PROJECT_DIR scripts/ark-deliver.sh | head -1 | cut -d: -f1` < `grep -n portfolio_decide scripts/ark-deliver.sh | head -1 | cut -d: -f1` (Tier 11 assertion)

### Production-safety guarantees

- `ARK_CREATE_GITHUB` is UNSET throughout portfolio-decide path (statically grep-asserted: no `gh repo create` in `ark-portfolio-decide.sh` or the `ark-deliver.sh` no-args branch)
- Real `~/vaults/ark/observability/policy.db` md5 is invariant across Tier 11 (asserted before/after)
- Tier 11 fixture lives entirely under `mktemp -d`; no writes to real `~/code/`

### Verification (Tier 11)

Tier 11 in `scripts/ark-verify.sh` runs a synthetic 3-project / 2-customer fixture under mktemp, exercising all 4 decision classes plus CEO override semantics, cool-down, expiry, and backward-compat:

- T11.1–5: ark-portfolio-decide.sh present, syntax valid, self-test 40/40, ark-deliver wires it in, dispatcher documents `ARK_PORTFOLIO_ROOT`
- T11.6–9: run1 (2 acme over-cap projects + 1 foo-c healthy) → foo-c wins, 1 SELECTED row, ≥1 DEFERRED_BUDGET row, context_json carries customer + total
- T11.10: run2 (CEO directive on over-budget project) → budget filter wins; foo-c still selected
- T11.11: run3 (1h-old DEFERRED_HEALTHY) → cool-down keeps foo-c out of winner pool
- T11.12: run4 (25h-old DEFERRED_HEALTHY) → cool-down expired; SELECTED row appears
- T11.13: run5 (empty portfolio) → NO_CANDIDATE_AVAILABLE
- T11.14: static-grep — PROJECT_DIR appears before portfolio_decide in ark-deliver.sh
- T11.15: static-grep — no `gh repo create` in portfolio code path
- T11.16: real-vault policy.db md5 invariant before/after Tier 11

16 checks total. Tier 7 (14/14), Tier 8 (25/25), Tier 9 (20/20), Tier 10 (22/22) all retained.

### Cross-references

- Portfolio functions: `scripts/ark-portfolio-decide.sh::{portfolio_decide, _portfolio_discover, _portfolio_attribute_customer, _portfolio_score, _portfolio_budget_headroom, _portfolio_ceo_priority, _portfolio_recently_deferred, portfolio_pick_winner}`
- Cascading-config customer cap reader: `scripts/lib/policy-config.sh::policy_config_get` (extended in Phase 4; Phase 5 reads `customer.budget.monthly_cap` and `customer.budget.monthly_used`)
- Audit writer: `scripts/lib/policy-db.sh::_policy_log` (single-writer; class `portfolio`)
- Deliver entrypoint: `scripts/ark-deliver.sh` (PROJECT_DIR gate + no-args branch)
- Tier 11 verify: `scripts/ark-verify.sh` (search "Tier 11")
- Plan-level history: `.planning/phases/05-portfolio-autonomy/{05-01..05-07}-SUMMARY.md`

## AOS Cross-Customer Learning Contract (Phase 6)

**Status:** locked 2026-04-26 (Phase 6 — AOS: Cross-Customer Learning Autonomy)

Phase 6 closes the **cross-tenant learning** gate. Where Phase 3 made the policy engine self-improving WITHIN a project, and Phase 5 made portfolio selection cross-project, Phase 6 makes lessons learned in one customer auto-promote to universal when the same pattern recurs in ≥2 customers. Same audit substrate (`policy.db`, `_policy_log`, `schema_version=1`) — `class:lesson_promote` joins `portfolio`, `bootstrap`, `dispatch`, `budget`, `self_heal`, `self_improve`.

### Discovery scope

Walks `${ARK_PORTFOLIO_ROOT:-~/code}/*/tasks/lessons.md`. One `tasks/lessons.md` per customer project (per project-standard.md convention). Lesson IDs are L-NNN per customer (Strategix L-018 ≠ Customer A L-018 unless content matches).

### Components

| Component | Path | Role |
|---|---|---|
| Similarity primitive | `scripts/lib/lesson-similarity.sh` | Sourceable Bash 3 lib. `lesson_similarity <a-md> <b-md>` returns 0..100 integer (Jaccard token overlap on title + rule body, lowercased, alphanumerics only, 50-word stop list, length<2 dropped) |
| Promoter engine | `scripts/lesson-promoter.sh` | Sourceable + CLI. `promoter_run [--full|--since DATE] [--apply]` orchestrates scan → cluster → classify → apply. Sub-functions: `promoter_scan_lessons` (discover lesson set under `$ARK_PORTFOLIO_ROOT`), `promoter_cluster` (similarity ≥60% → cluster), `promoter_classify` (verdict TSV per cluster), `promoter_apply_pending` (idempotent durable side-effects under mkdir-lock + atomic tmp+mv) |
| Manual surface | `ark promote-lessons` | Dispatcher subcommand in `scripts/ark`. Default `--since 7-days-ago --apply`. Sourced-subshell invocation passes through to `promoter_run` |
| Post-phase trigger | `scripts/ark-deliver.sh::run_phase` | After Phase 3 policy-learner trigger, fires `promoter_run --since 1-hour-ago --apply` non-fatally (`|| log WARN`). Mirrors Phase 3's discipline |
| Audit class | `_policy_log "lesson_promote" ...` | Single-writer through `scripts/lib/policy-db.sh`. 3 decision values |
| Universal target | `~/vaults/ark/lessons/universal-patterns.md` | Managed-section append target for PROMOTED clusters. Each promotion = git commit in vault repo |
| Anti-pattern target | `~/vaults/ark/bootstrap/anti-patterns.md` | Managed-section append target for anti-pattern clusters. Bootstrap policy (Phase 4) reads this when generating CLAUDE.md addenda |
| Conflicts queue | `~/vaults/ark/lessons/conflicts-pending-review.md` | Surfaced cluster-with-contradicting-rules entries (DEPRECATED verdict). Manual review required; not auto-resolved |
| Env config | `ARK_PORTFOLIO_ROOT` | Reused from Phase 5 to scope lesson discovery |

### Promotion thresholds

```
PROMOTE_MIN_CUSTOMERS  = 2    (≥2 distinct customers must contribute)
PROMOTE_MIN_OCCURRENCES = 3   (combined lesson count across cluster ≥3)
SIMILARITY_THRESHOLD    = 60  (Jaccard ≥60% to cluster two lessons)
```

A cluster is auto-PROMOTED only when **all three** thresholds clear. Singleton lessons (one customer, even if multiple internal occurrences) classify as `MEDIOCRE_KEPT_PER_CUSTOMER`.

### Routing — universal vs anti-pattern

Anti-pattern detection is title-string heuristic: cluster title matches `^(anti-pattern|don't|do not|never)` (case-insensitive) → routes to `bootstrap/anti-patterns.md`. Otherwise routes to `lessons/universal-patterns.md`.

### Decision classes (audit values)

All emitted via single-writer `_policy_log "lesson_promote" "<DECISION>" ...`:

1. **`PROMOTED`** — cluster cleared all 3 thresholds, content appended to universal-patterns.md or anti-patterns.md, vault git commit created. `context_json` includes: cluster_signature, customer_count, lesson_count, route (universal|anti-pattern), source lesson IDs.
2. **`DEPRECATED`** — cluster found, but lessons disagree on the rule (POSITIVE imperative + NEGATIVE imperative both present across distinct customers). Surfaced to `lessons/conflicts-pending-review.md`; not auto-promoted.
3. **`MEDIOCRE_KEPT_PER_CUSTOMER`** — singleton or below threshold. No write; per-customer lessons stay where they are.

### Idempotency invariant

Re-running `promoter_run` over unchanged data is a no-op:
- Per-cluster canonical marker (literal-string `grep -F`) prevents duplicate appends
- mkdir-lock at `$ARK_HOME/.lesson-promoter.lock` (released on exit) prevents concurrent runs
- Atomic write via `cat target + new block → tmp → mv` — no partial writes
- Audit row count + git commit count + universal-patterns.md md5 all unchanged on re-run (Tier 12 assertions)

### Out of scope

- ML embeddings / semantic similarity (Jaccard heuristic only)
- Customer-specific lesson redaction (user's responsibility before adding to `tasks/lessons.md`)
- Cross-customer DEPRECATION of per-customer lessons (Phase 6 only PROMOTES; per-customer lessons stay)
- Multi-language translation
- Auto-resolution of contradicting lessons (logged as DEPRECATED for manual review)

### Verification (Tier 12)

Tier 12 in `scripts/ark-verify.sh` runs a synthetic 3-customer fixture under mktemp portfolio + tmp git vault + tmp policy.db:

- T12.1–7: lib/lesson-similarity.sh and scripts/lesson-promoter.sh present, syntax valid, self-test passes; ark dispatcher exposes `promote-lessons`; ark-deliver.sh has post-phase trigger
- T12.8–14: portfolio scan discovers 3 customer lesson files; universal-patterns.md + anti-patterns.md created in tmp vault; RBAC cluster + anti-pattern cluster both promoted; audit DB has ≥2 `lesson_promote PROMOTED` rows; tmp-vault git has ≥2 promote commits
- T12.15: singleton (cust-c only) NOT in universal-patterns.md (negative-grep)
- T12.16–19: lock dir absent after run; idempotent (audit count, git commit count, universal-patterns.md md5 all unchanged on re-run)
- T12.20–22: real-vault md5 invariant (universal-patterns.md, anti-patterns.md, policy.db all unchanged)
- T12.23–24: 0 non-comment `read -p` lines in `scripts/ark` and `scripts/ark-deliver.sh`

24 checks total, 24/24 passing. Tier 7 (14/14), Tier 8 (25/25), Tier 9 (20/20), Tier 10 (22/22), Tier 11 (16/16) all retained.

### Cross-references

- Similarity primitive: `scripts/lib/lesson-similarity.sh::lesson_similarity`
- Promoter functions: `scripts/lesson-promoter.sh::{promoter_run, promoter_scan_lessons, promoter_cluster, promoter_classify, promoter_apply_pending}`
- Audit writer: `scripts/lib/policy-db.sh::_policy_log` (single-writer; class `lesson_promote`)
- Manual surface: `scripts/ark` (`promote-lessons` subcommand)
- Post-phase hook: `scripts/ark-deliver.sh::run_phase` (after Phase 3 policy-learner trigger)
- Tier 12 verify: `scripts/ark-verify.sh` (search "Tier 12")
- Plan-level history: `.planning/phases/06-cross-customer-learning/{06-01..06-06}-SUMMARY.md`

---

## AOS Phase 6.5 — CEO Dashboard Contract

**Phase 6.5 substrate:** Read-only visibility layer over Phase 2-6 audit data. Three-tier delivery; phase exit gate requires all three plus Tier 13 regression sweep. The dashboard is read-only by construction — it never mutates `policy.db`, `ESCALATIONS.md`, `universal-patterns.md`, `anti-patterns.md`, or any vault file. The single permitted "action" path (mark-resolved in Tier B) delegates to the existing single-writer `ark escalations --resolve` command.

### Locked decisions (D-DASH-*)

- **D-DASH-TIER-A-FIRST:** Bash version (`scripts/ark-dashboard.sh`) ships before Rust TUI; phase exit gate requires both. Tier C (web) added in 06.5-08 as a third surface — also part of the exit gate.
- **D-DASH-READONLY:** Dashboard never writes to `policy.db`, `ESCALATIONS.md`, or any vault file. Mark-resolved delegates to `ark escalations --resolve` (existing single-writer; class `escalation`).
- **D-DASH-INVOCATION:**
  - `ark dashboard` (no flag) → Tier A bash (`scripts/ark-dashboard.sh`).
  - `ark dashboard --tui` → Tier B Rust binary (`scripts/ark-dashboard/target/release/ark-dashboard`).
  - `ark dashboard --web [--port N]` → Tier C bash + python3 http.server (`scripts/ark-dashboard-web.sh`).
- **D-DASH-RUST-DEPS:** ratatui + rusqlite + crossterm only. No async runtime. No serde derives beyond what's needed.
- **D-DASH-RUST-BUILD:** `cd scripts/ark-dashboard && cargo build --release` → `scripts/ark-dashboard/target/release/ark-dashboard`.
- **D-DASH-REFRESH-TUI:** Rust TUI polls every 2s via `crossterm::event::poll(500ms)` + 2s elapsed-since-last-tick check.
- **D-DASH-REFRESH-WEB:** Tier C HTML uses `<meta http-equiv="refresh" content="N">` (default 5s). Server-side regen loop refreshes the served HTML on the same cadence; reads via `sqlite3 -readonly`.
- **D-DASH-WEB-PORT:** Tier C default port 7919; override via `--port N` flag (consumed by `scripts/ark`) or `ARK_DASHBOARD_PORT` env (honored by `scripts/ark-dashboard-web.sh` directly).
- **D-DASH-WEB-CLEANUP:** Tier C runs python3 as a child (`python3 -m http.server &`) NOT as `exec`, retains the bash cleanup trap, and uses a polling-trap pattern (`STOP=1` flag from INT/TERM trap + `kill -0 $HTTP_PID; sleep 1` loop). Bash 3 `wait` is uninterruptible by signals; polling gives ≤1s cleanup latency. Trap unconditionally kills both children and `rm -rf` the tmpdir.
- **D-DASH-WEB-ESCAPE:** Tier C HTML-escapes every interpolated value via sed pipeline (defense in depth — server is local-only, but discipline matters).
- **D-DASH-WEB-ATOMIC:** Tier C writes generated HTML via `tmp + mv` so readers never see a half-rendered page.
- **D-DASH-DRIFT-TOLERANCE:** Drift detector (Section 6) treats STATE.md vs disk diffs within 60s as INFO (not RED) to avoid false positives during active phases.
- **D-DASH-DEGRADE:** Color-friendly terminal degradation: `tput colors < 8` OR `NO_COLOR=1` → plain output (Tier A only; Tier C uses CSS light/dark + mobile viewport).
- **D-DASH-CREATE-GH-CARRY:** The `ARK_CREATE_GITHUB` production-safety env gate (Phase 4 D-CREATE-GH) carries forward — dashboard tiers never create GitHub repos and so never need the gate, but its existence is documented here so future tier additions remember the rule.

### Sections (locked priority order, all three tiers)

1. **Portfolio grid** — projects × current phase × last activity × health (green/yellow/red).
2. **Escalations panel** — count of pending blockers by class (4 true-blocker types); list view.
3. **Budget summary** — per-customer monthly burn, headroom percent, `ESCALATE_MONTHLY_CAP` risk.
4. **Recent decisions stream** — last 50 rows from `policy.db` filtered/grouped by class.
5. **Learning watch** — patterns approaching promotion threshold (≥3 customers but <60% similarity yet); patterns just promoted.
6. **Drift detector** — `STATE.md` vs disk reality (catches the drift class 06-03 surfaced).
7. **Tier health** — last verify report's pass/fail count per tier (7-13); link to report.

### Read-only invariant enforcement

- **Tier A (bash):** every `sqlite3` call uses the `-readonly` flag.
- **Tier B (Rust):** `Connection::open_with_flags(..., SQLITE_OPEN_READ_ONLY | SQLITE_OPEN_NO_MUTEX)`. Asserted at the C-API layer.
- **Tier C (web):** every `sqlite3` call in `scripts/ark-dashboard-web.sh` uses `-readonly`. No write paths exist in the script.
- **Tier 13 dashboard-only invariant** captures real-vault `policy.db` md5 before each tier's smoke run and re-asserts after the Tier A → Tier B → Tier C sweep. md5 unchanged across all three. Whole-block invariants additionally cover `ESCALATIONS.md`, `universal-patterns.md`, and `anti-patterns.md`.

### Tier C network surface (LAN / Tailscale notes)

`scripts/ark-dashboard-web.sh` defaults to binding to `127.0.0.1` (loopback only). To make the dashboard reachable from a phone or other device on the same Tailscale tailnet or LAN, swap the bind to `0.0.0.0` (one-line change) and access via the machine's MagicDNS name or LAN IP. The post-startup banner emits the served URL; future iterations may auto-detect Tailscale/MagicDNS and print the externally-reachable URL alongside the localhost one. This is currently out of scope for Phase 6.5 (default loopback is correct for a single-laptop CEO use case).

### Decision classes consumed (read-only)

The dashboard reads (never writes) the full set of audit classes minted across Phases 2-6:
`bootstrap`, `budget`, `dispatch`, `dispatch_failure`, `escalation`, `lesson_promote`, `portfolio`, `self_heal`, `self_improve`, `zero_tasks`. Sections 1, 4, and 5 group/aggregate over this set; Section 2 reads `~/vaults/ark/ESCALATIONS.md`; Section 3 reads `policy.yml` cascading config + per-customer `budget.json` files; Section 5 also reads `~/vaults/ark/lessons/universal-patterns.md` and `~/vaults/ark/bootstrap/anti-patterns.md`; Section 6 cross-checks `~/code/*/.planning/STATE.md` against disk reality; Section 7 reads `~/vaults/ark/observability/verification-reports/*.md`.

### Out of scope (Phase 8+ candidates)

- Push notifications (Slack / macOS) — the queue surface is enough for v1.
- Multi-machine sync (single-laptop vault).
- Historical trend charting (Phase 7 weekly-digest covers this textually).
- Plug-in "employees" UI surface (registry exists; richer plugin model = Phase 8).
- Auto-detection of Tailscale/MagicDNS/LAN URLs in the Tier C banner (manual `--bind 0.0.0.0` swap suffices for v1).
- Authentication / authorization on the Tier C web surface (loopback-only by default; LAN exposure is opt-in).

### Verification (Tier 13)

Tier 13 in `scripts/ark-verify.sh` covers all three tiers + regression sweep over Tiers 7-12 in 30 checks (~47s wall time):

- T13.1–8: Tier A — `scripts/ark-dashboard.sh` exists, syntax OK, all 7 sections render against synthetic vault, runtime <2s, real policy.db md5 unchanged.
- T13.9–14: Tier B — Rust crate builds (cached `target/`), binary launches, refreshes within 2s tick, real policy.db md5 unchanged.
- T13.15–20: Tier C — `scripts/ark-dashboard-web.sh` syntax OK, HTML served on transient port contains `<table>` + `<meta http-equiv="refresh">`, real policy.db md5 unchanged after Tier C smoke.
- T13.21: Dispatcher — `ark dashboard --help` mentions all three tiers.
- T13.22–24: Synthetic vault assertions across portfolio / escalations / recent-decisions sections.
- T13.25: Dashboard-only md5 invariant — real policy.db md5 unchanged across the Tier A + Tier B + Tier C sweep.
- T13.26–30: Regression sweep — Tier 7 14/14, Tier 8 ≥23 (baseline 24/25; pre-existing failure unrelated to dashboard), Tier 9 20/20, Tier 10 22/22, Tier 11 16/16, Tier 12 24/24; whole-block md5 invariants on `ESCALATIONS.md`, `universal-patterns.md`, `anti-patterns.md`.

30/30 passing. Phase 6.5 exit gate met.

### Cross-references

- Tier A: `scripts/ark-dashboard.sh`
- Tier B: `scripts/ark-dashboard/` (Rust crate); binary at `scripts/ark-dashboard/target/release/ark-dashboard`
- Tier C: `scripts/ark-dashboard-web.sh`
- Dispatcher: `scripts/ark` (search `dashboard)`)
- Tier 13 verify: `scripts/ark-verify.sh` (search "Tier 13")
- Plan-level history: `.planning/phases/06.5-ceo-dashboard/{06.5-01..06.5-08}-SUMMARY.md`

## AOS Continuous Operation Contract (Phase 7)

**Phase 7 substrate:** Cron-driven INBOX consumption. User authors intent in markdown at `~/vaults/ark/INBOX/`; macOS launchd daemon ticks every 15 min, parses intent files, dispatches to `ark create` / `ark deliver` / `ark promote-lessons`, archives processed files, escalates true blockers via `ESCALATIONS.md`, and writes a weekly digest. Closes the AOS journey from the original ROADMAP North Star (user authors intent → walks away → returns to find projects shipped).

### Surfaces

- `scripts/ark-continuous.sh` — daemon (tick + INBOX lifecycle + lock + cap + health monitor + subcommands).
- `scripts/lib/inbox-parser.sh` — frontmatter parser + intent dispatcher (sourceable Bash 3 lib).
- `scripts/ark-weekly-digest.sh` — weekly aggregator + standalone plist generator.
- `scripts/ark continuous <subcmd>` — user-facing dispatcher arm (install / uninstall / status / pause / resume / tick).

### INBOX intent file format

- Files at `~/vaults/ark/INBOX/*.md`.
- YAML-ish frontmatter:
  - `intent` (required): one of `new-project`, `new-phase`, `resume`, `promote-lessons`.
  - `customer` (default `scratch`).
  - `priority` (default `medium`).
  - `phase` (only for `new-phase` intent).
- Body: first non-blank line (with leading `# ` stripped) used as the description argument.

### Intent dispatch table

| Intent             | Routes to                                            |
|--------------------|------------------------------------------------------|
| `new-project`      | `ark create "<desc>" --customer "<customer>"`       |
| `new-phase`        | `ark deliver --phase <N>`                            |
| `resume`           | `ark deliver` (portfolio engine picks next project)  |
| `promote-lessons`  | `ark promote-lessons`                                |

### Intent file lifecycle

- **Success:** `mv` to `INBOX/processed/<UTC-date>/`.
- **Dispatch failure:** rename to `<file>.failed` + ESCALATIONS.md entry (class `repeated-failure`).
- **Parse failure:** rename to `<file>.malformed` + audit row (class `INBOX_MALFORMED`).
- **Files NEVER silently dropped.**

### Six safety rails

1. **PAUSE kill-switch** — file at `~/vaults/ark/PAUSE` halts every tick; daemon emits `PAUSE_ACTIVE` audit row and exits cleanly.
2. **mkdir-lock** — `~/vaults/ark/.continuous.lock` (atomic mkdir) prevents tick overlap; contended ticks emit `LOCK_CONTENDED` and exit.
3. **Daily token cap** — `policy.yml::continuous.daily_token_cap` (default 50000); on hit emit `DAILY_CAP_HIT` and SUSPEND until UTC date rollover.
4. **Auto-pause on 3 consecutive failure-ticks** — daemon writes PAUSE file + emits `AUTO_PAUSED` + escalates.
5. **Stuck-phase detection** — STATE.md mtime > 24h AND no commits in 24h; 3 consecutive detections within 60 min on same `(project, phase)` → ESCALATIONS entry (24h dedupe).
6. **Weekly digest separate cron** — independent `com.ark.weekly-digest.plist` (Sunday 09:00 local) so a hung daemon never blocks the digest.

### Audit decision classes (13 total)

All decisions logged via `_policy_log "continuous" "<DECISION>" ...`:

| Decision                  | Trigger                                                            |
|---------------------------|--------------------------------------------------------------------|
| `TICK_START`              | Daemon entered tick body                                           |
| `TICK_COMPLETE`           | Daemon finished tick (any outcome)                                 |
| `INBOX_DISPATCH`          | Intent file routed to subcommand                                   |
| `INBOX_PROCESSED`         | Subcommand exit 0 → file archived                                  |
| `INBOX_FAILED`            | Subcommand exit non-0 → `.failed` rename + ESCALATIONS             |
| `INBOX_MALFORMED`         | Frontmatter parse failure → `.malformed` rename                    |
| `LOCK_CONTENDED`          | mkdir-lock acquisition failed                                      |
| `PAUSE_ACTIVE`            | PAUSE file present at tick start                                   |
| `DAILY_CAP_HIT`           | Daily token cap reached → SUSPEND until UTC rollover               |
| `AUTO_PAUSE_3_FAIL`       | 3 consecutive failure-ticks → PAUSE created                        |
| `STUCK_PHASE_DETECTED`    | Health monitor detected 24h-stuck phase                            |
| `STUCK_ESCALATED`         | Stuck phase escalated to ESCALATIONS (24h dedupe)                  |
| `WEEKLY_DIGEST_WRITTEN`   | Weekly digest aggregator wrote `weekly-digest-YYYY-WW.md`          |

### launchd plists (macOS)

- `~/Library/LaunchAgents/com.ark.continuous.plist`
  - `RunAtLoad = true`, `StartInterval = tick_interval_min * 60` (default 900s = 15 min).
  - Generated atomically by `continuous_install` under `ARK_LAUNCHAGENTS_DIR` test override.
- `~/Library/LaunchAgents/com.ark.weekly-digest.plist`
  - `StartCalendarInterval` Weekday=0 Hour=9 Minute=0 (Sunday 09:00 local).
  - Independent cron — runs even if main daemon is paused or hung.

### Read-only invariants

The continuous daemon writes only to:

- `INBOX/`, `INBOX/processed/<date>/`, `INBOX/*.failed`, `INBOX/*.malformed`
- `ESCALATIONS.md` (delegates to existing single-writer)
- `PAUSE`, `.continuous.lock`
- `observability/policy.db` (via `_policy_log` single-writer)
- `observability/continuous-operation.log`
- `observability/weekly-digest-YYYY-WW.md`

Daemon NEVER writes outside `~/vaults/ark/`. Never invokes `gh repo create` (Phase 4 `ARK_CREATE_GITHUB` env gate carried forward — defaults remain unset).

### Verification (Tier 14)

Tier 14 in `scripts/ark-verify.sh` covers the contract in 28 checks:

- **INBOX lifecycle (3 intents):** synthetic `resume`, `new-phase`, `promote-lessons` files dropped → asserted all 3 reach `INBOX/processed/<UTC-date>/`.
- **Safety rails:** PAUSE / DAILY_CAP_HIT / LOCK_CONTENDED smoke under `ARK_FORCE_*` test hooks.
- **Plist generation:** `continuous_install` under `ARK_LAUNCHAGENTS_DIR` override produces a syntactically valid plist; `plutil -lint` passes.
- **Weekly digest:** synthetic seeded vault → `ark-weekly-digest.sh` writes `weekly-digest-YYYY-WW.md` with all 6 expected section headers.
- **Read-p sweep:** `grep -rn 'read -p'` across `scripts/ark-continuous.sh`, `scripts/lib/inbox-parser.sh`, `scripts/ark-weekly-digest.sh` returns zero hits (no manual-gate regression).
- **Real-vault md5 invariants:** `policy.db`, `ESCALATIONS.md`, `universal-patterns.md`, `anti-patterns.md` md5 unchanged across the synthetic-vault smoke run.
- **Real ~/Library/LaunchAgents invariant:** `com.ark.continuous.plist` and `com.ark.weekly-digest.plist` md5 unchanged when test runs use `ARK_LAUNCHAGENTS_DIR` override.

28/28 passing. Phase 7 exit gate met.

### Cross-references

- Daemon: `scripts/ark-continuous.sh`
- INBOX parser: `scripts/lib/inbox-parser.sh`
- Weekly digest: `scripts/ark-weekly-digest.sh`
- Dispatcher: `scripts/ark` (search `cmd_continuous`)
- Tier 14 verify: `scripts/ark-verify.sh` (search "Tier 14")
- Plan-level history: `.planning/phases/07-continuous-operation/{07-01..07-08}-SUMMARY.md`

### AOS journey terminal

**Phase 7 closes the AOS journey** (Phases 2 → 2.5 → 3 → 4 → 5 → 6 → 6.5 → 7). Original ROADMAP.md North Star achieved: user authors intent in markdown, walks away, returns to find projects shipped (or true blockers escalated via async ESCALATIONS.md queue). Phase 8 (Production Hardening + Reporting) is post-AOS productionization, not autonomy.
