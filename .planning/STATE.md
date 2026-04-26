---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: "Phase 5 (AOS: Portfolio Autonomy)"
status: completed
last_updated: "2026-04-26T17:53:02.715Z"
progress:
  total_phases: 7
  completed_phases: 4
  total_plans: 39
  completed_plans: 37
  percent: 95
---

# Ark — Implementation State

**Last updated:** 2026-04-26T18:30:00Z
**Current Phase:** Phase 5 (AOS: Portfolio Autonomy)
**Status:** complete

## Phase 0 — Bootstrap (complete)

- [x] Vault structure established (lessons/, cache/, observability/, scripts/, hooks/, employees/, dashboard/)
- [x] 24 CLI commands wired into `ark`
- [x] 14 employees in registry
- [x] Hooks installed (SessionStart, Stop)
- [x] Skill /ark registered in Claude Code
- [x] GitHub repo: goldiejz/ark
- [x] Brain → Ark rename complete
- [x] ark verify suite (36/36 pass)
- [x] Continuous observer daemon running
- [x] Production safety gate verified

## Phase 1 — GSD Integration (in-progress)

See `.planning/phases/01-gsd-integration/PLAN.md`

Goal: Make Ark fully aware of GSD's planning structure so `ark deliver` works correctly on GSD projects.

## Phase 2 — AOS: Delivery Autonomy (complete)

See `.planning/phases/02-autonomy-policy/`

**Goal:** Ark decides routine resource questions autonomously; only 4 true-blocker classes reach the user via `~/vaults/ark/ESCALATIONS.md`.

**Exit gate:** Tier 8 25/25 + Tier 1–7 14/14 retained (`scripts/ark-verify.sh`).

| Plan | Outcome |
|------|---------|
| 02-01 | `scripts/ark-policy.sh` foundation: cascading config loader, decision functions, audit log with 64-bit `decision_id` (16-hex from `/dev/urandom`), `outcome`/`correlation_id` Phase-3-ready fields |
| 02-02 | `~/vaults/ark/ESCALATIONS.md` queue + `ark escalations` (list/show/resolve) command |
| 02-03 | `scripts/ark-budget.sh` BLACK halt replaced with `policy_budget_decision` delegation |
| 02-04 | `scripts/execute-phase.sh` dispatch routing via `policy_dispatcher_route`; session-handoff sentinel cost recorded (observable BEFORE/AFTER delta) |
| 02-05 | `scripts/ark-deliver.sh` zero-task and phase-collision paths delegate to policy |
| 02-06 | `scripts/ark-team.sh` in-process retry loop (4 dispatches max); post-loop `ark_escalate` always-fire; `execute-phase.sh::dispatch_task` invokes `self-heal.sh --retry` |
| 02-06b | `scripts/self-heal.sh` refactored to layered 3-retry contract (enriched → model-escalate → queue); audit via single `_policy_log` writer |
| 02-07 | Remaining `read -p` calls stripped or tagged `# AOS: intentional gate`; observer pattern `manual-gate-hit` shipped |
| 02-08 | Tier 8 verify suite (autonomy under stress): isolated dedup test, schema integrity, entropy stress, dispatcher-route assertions |
| 02-09 | STRUCTURE.md AOS Escalation Contract; REQ-AOS-01..07 minted; STATE.md updated |

## Phase 3 — AOS: Self-Improving Self-Heal (complete)

See `.planning/phases/03-self-improving-self-heal/`

**Goal:** Audit log → outcome tagger → pattern learner → auto-patch policy.yml under file-lock + git commit + audit entry. Self-improving without losing the schema lock or the true-blocker contract.

**Exit gate:** Tier 9 20/20 + Tier 1–8 retained — confirmed `bash scripts/ark-verify.sh --tier 7` 14/14, `--tier 8` 25/25, `--tier 9` 20/20 (after `execute-phase.sh` restored from `.HALTED` snapshot in 03-08).

**Substrate note:** Phase 2.5 migrated the audit log to SQLite at `~/vaults/ark/observability/policy.db` (schema preserved, `schema_version=1`). Phase 3 reads + patches via `sqlite3`; synthetic fixtures use `INSERT INTO decisions`. See `.planning/phases/03-self-improving-self-heal/SUPERSEDES.md`.

| Plan | Outcome |
|------|---------|
| 03-01 | `scripts/lib/outcome-tagger.sh`: SINGLE writer for `outcome` column; idempotent SQL UPDATE; window-configurable inference (success/failure/ambiguous) |
| 03-02 | `scripts/policy-learner.sh`: pattern scoring by `(class, decision, dispatcher, complexity)` via SQL GROUP BY; 5/80%/20% thresholds; true-blocker filter (`class NOT IN ('escalation','self_improve')`) |
| 03-03 | `learner_apply_pending`: mkdir-lock + python3/PyYAML atomic patch + vault git commit + `_policy_log self_improve PROMOTED|DEPRECATED` audit |
| 03-04 | `scripts/lib/policy-digest.sh::learner_write_digest`: `~/vaults/ark/observability/policy-evolution.md` with Promoted, Deprecated, Mediocre sections; idempotent |
| 03-05 | `scripts/ark-deliver.sh::run_phase` post-phase trigger (after `update_state`, non-fatal, windowed `--since` 1h-ago, output to `.planning/delivery-logs/learner-phase-N.log`); restored ark-deliver.sh from `.HALTED` snapshot |
| 03-06 | `ark learn` subcommand (default last-7-days, `--full`, `--since DATE`, `--tag-first`) |
| 03-07 | Tier 9 verify suite (synthetic SQLite fixture, isolated tmp vault, 20 checks; mirrors Phase 2 NEW-W-1 isolation; md5 guarantee on real vault DB) |
| 03-08 | STRUCTURE.md AOS Self-Improving Self-Heal Contract; REQ-AOS-08..14 minted; STATE.md Phase 3 close; SKILL.md updated; `scripts/execute-phase.sh` restored from `.HALTED` (closes T7+T8 source-count regression) |

## Phase 4 — AOS: Bootstrap Autonomy (complete)

See `.planning/phases/04-bootstrap-autonomy/`

**Goal:** `ark create "<one-line description>" --customer <name>` runs to completion with zero prompts. Inference engine + audit trail + atomic CLAUDE.md/policy.yml writes; backward-compat for flag-mode; production-side-effect gate around `gh repo create`.

**Exit gate:** Tier 10 22/22 + Tier 7/8/9 retained — confirmed `bash scripts/ark-verify.sh --tier 7` 14/14, `--tier 8` 25/25, `--tier 9` 20/20, `--tier 10` 22/22.

| Plan | Outcome |
|------|---------|
| 04-01 | `scripts/bootstrap-policy.sh`: keyword-overlap inference engine; `bootstrap_classify` orchestrator emitting TSV verdict + `_policy_log "bootstrap"` audit; confidence threshold escalates `architectural-ambiguity` to ESCALATIONS.md; bash 3 compat; 16-test self-test in isolated tmp vault |
| 04-02 | `bootstrap/project-types/*-template.md` frontmatter tagged with `keywords:`, `default_stack:`, `default_deploy:`; phrase-aware tokenizer; new `custom-template.md` empty-keyword catch-all; absolute-match scoring (matched × 20, capped 100) |
| 04-03 | `bootstrap/claude-md-template.md` base with named anchors + 4 `claude-md-addendum/<type>.md` files (service-desk, revops, ops-intelligence, custom); anchor-on-own-line discipline for sed `r`+`d` composition |
| 04-04 | `scripts/ark-create.sh` description-mode wired through `bootstrap_classify`; sed-pipeline + atomic mv for CLAUDE.md; auto-generated `.planning/policy.yml`; `_policy_log "bootstrap" RESOLVED_FINAL/FLAG_OVERRIDE` audit; `ARK_CREATE_GITHUB` env gate added (default off) after unguarded-`gh repo create` incident |
| 04-05 | `scripts/lib/bootstrap-customer.sh` mkdir-lock customer dir + idempotent seed; `scripts/lib/policy-config.sh` extended with customer layer (env > project > customer > vault > default) |
| 04-06 | `scripts/ark` dispatcher `cmd_create` pass-through to ark-create.sh; help text reflects description-mode + flag-mode + `ARK_CREATE_GITHUB` gate; no `read -p` regression |
| 04-07 | Tier 10 verify suite (5 fixtures × multi-assert + flag-mode + cascading-customer + low-confidence + isolation md5; 22 checks total); Tier 1-9 regression sweep clean |
| 04-08 | REQ-AOS-15..REQ-AOS-22 minted; STATE.md Phase 4 close; ROADMAP.md checkboxes; STRUCTURE.md AOS Bootstrap Autonomy Contract; SKILL.md Phase 4 posture |

**Known issue (out-of-scope manual cleanup):** During Plan 04-04's first smoke test, an unguarded `gh repo create` block in `ark-create.sh` created an unauthorized public repo at `https://github.com/goldiejz/acme-sd`. The defect was fixed in 04-04 (`ARK_CREATE_GITHUB` env gate, default off). The leftover repo could not be deleted by the agent (token lacked `delete_repo` scope). User must manually delete via `gh repo delete goldiejz/acme-sd --yes` (after granting `delete_repo` scope) or GitHub web UI. See `.planning/phases/04-bootstrap-autonomy/04-04-SUMMARY.md` "Production-side-effect incident (handled)".

## Phase 5 — AOS: Portfolio Autonomy (complete)

See `.planning/phases/05-portfolio-autonomy/`

**Goal:** `ark deliver` (no args) picks the highest-leverage project from the portfolio and runs its next phase, audit-logged, with cross-project budget routing and 24h cool-down.

**Exit gate:** Tier 11 16/16 + Tier 7/8/9/10 retained — confirmed `bash scripts/ark-verify.sh --tier 7` 14/14, `--tier 8` 25/25, `--tier 9` 20/20, `--tier 10` 22/22, `--tier 11` 16/16.

| Plan | Outcome |
|------|---------|
| 05-01 | `scripts/ark-portfolio-decide.sh` foundation: discovery + scoring + winner; sentinel sections; bash-3 self-test |
| 05-02 | `_portfolio_budget_headroom`: per-customer monthly cap reader via existing cascading config; 0 headroom signals DEFERRED_BUDGET |
| 05-03 | `_portfolio_ceo_priority`: programme.md `## Next Priority` parser; +5 weight when match |
| 05-04 | `_portfolio_recently_deferred` + full `portfolio_decide`: 4 decision classes (SELECTED/DEFERRED_BUDGET/DEFERRED_HEALTHY/NO_CANDIDATE_AVAILABLE) audit-logged via single-writer `_policy_log`; 24h cool-down via sqlite SELECT against `class:portfolio` history |
| 05-05 | `scripts/ark-deliver.sh` no-args portfolio routing branch; `scripts/ark` help text; backward compat for `--phase N` and in-project invocation |
| 05-06 | Tier 11 verify suite (synthetic 3-project / 2-customer fixture, 16 checks; isolated mktemp vault; real DB md5 invariant) |
| 05-07 | REQ-AOS-23..30 minted; STATE.md Phase 5 close; ROADMAP.md checkboxes; STRUCTURE.md AOS Portfolio Autonomy Contract; SKILL.md Phase 5 posture |

## Phase 6+ — Future

Next per `.planning/ROADMAP.md`: **Phase 6 — Cross-Customer Learning Autonomy** (lessons learned in one customer auto-promote to universal when the same pattern recurs in 2+ customers; Tier 12 verify).
