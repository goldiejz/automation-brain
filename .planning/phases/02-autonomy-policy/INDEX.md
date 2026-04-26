# Phase 02 — AOS: Delivery Autonomy — Plan Index

This phase is split into 10 plans across 5 waves. Each plan is independent within its wave;
later waves consume the artifacts created earlier.

| Plan   | Title                                                                                  | Wave | Depends on                                | Files modified |
|--------|----------------------------------------------------------------------------------------|------|-------------------------------------------|----------------|
| 02-01  | ark-policy.sh foundation (config loader, decision fns, audit log w/ 64-bit decision_id) | 1    | —                                         | scripts/ark-policy.sh, scripts/lib/policy-config.sh |
| 02-02  | ESCALATIONS.md queue + `ark escalations` command                                       | 2    | 02-01                                     | scripts/ark-escalations.sh, scripts/ark, ~/vaults/ark/ESCALATIONS.md (created on first blocker) |
| 02-03  | Wire ark-budget.sh to policy (replace BLACK halt)                                      | 2    | 02-01                                     | scripts/ark-budget.sh |
| 02-04  | Wire execute-phase.sh to policy (dispatch routing + session sentinel cost, verified)   | 2    | 02-01                                     | scripts/execute-phase.sh |
| 02-05  | Wire ark-deliver.sh to policy (zero-task, phase-collision)                             | 2    | 02-01                                     | scripts/ark-deliver.sh |
| 02-06  | Wire ark-team.sh to policy (in-process retry, post-loop always-escalate) + wire execute-phase.sh → self-heal.sh --retry | 2    | 02-01, 02-06b                             | scripts/ark-team.sh, scripts/execute-phase.sh |
| 02-06b | Refactor self-heal.sh to layered retry contract (audit via _policy_log)                | 2    | 02-01, 02-02                              | scripts/self-heal.sh |
| 02-07  | Strip remaining `read -p` calls + observer `manual-gate-hit` pattern                   | 3    | 02-03, 02-04, 02-05, 02-06, 02-06b        | scripts/*.sh (delivery path), observability/observer/patterns.json |
| 02-08  | Tier 8 verify suite (isolated dedup, schema integrity, entropy stress)                 | 4    | 02-01..02-07 (incl. 02-06b)               | scripts/ark-verify.sh |
| 02-09  | STRUCTURE.md + skill docs (AOS escalation contract w/ Phase-3-ready schema)            | 5    | 02-08                                     | STRUCTURE.md, ~/.claude/skills/ark/SKILL.md |

## Wave structure

- **Wave 1:** 02-01 (foundation — everything else depends on it)
- **Wave 2:** 02-02, 02-03, 02-04, 02-05, 02-06b, 02-06 (parallel within wave; 02-06 now depends on 02-06b because 02-06 Task 2 wires execute-phase.sh to invoke `self-heal.sh --retry` from 02-06b)
- **Wave 3:** 02-07 (audit + observer; consumes the wired scripts including 02-06b's self-heal.sh)
- **Wave 4:** 02-08 (Tier 8 verify; needs all wiring done)
- **Wave 5:** 02-09 (docs; written after the system is proven)

Note: 02-06 → 02-06b dependency means 02-06b must complete before 02-06's Task 2 runs. Within Wave 2, 02-06b sequences before 02-06 (still parallel with 02-02/02-03/02-04/02-05).

## Revision summary (post-checker)

This INDEX has been updated to reflect targeted fixes from the plan-checker pass:

- **B-1 / W-1:** Added 02-06b as a Wave-2 first-class plan for self-heal.sh layered-retry refactor (CONTEXT.md decision #4). Previously buried as a conditional step in 02-07; now has explicit pre-state capture and 3-layer implementation. 02-07 is now a pure audit pass.
- **B-2:** 02-04 records token sentinel cost on the claude-session handoff branch so Tier 8 quota stubs don't mask budget tracking.
- **B-3:** 02-03 Task 2 heredoc replaced with the working env-passing idiom (`BUDGET_FILE="$BUDGET_FILE" python3 - <<'PY'` + `os.environ['BUDGET_FILE']`).
- **B-4:** 02-06 retry semantics locked: 1 initial + 3 retries (4 dispatches max). count_file reset at start of each `ark team` invocation. SELF_HEAL branch now concretely writes `${role}-enriched-prompt.md` (distinct from RETRY_NEXT_TIER).
- **W-2:** 02-04 Task 2 split into 2a (router) + 2b (failure handling).
- **W-3:** 02-08 adds audit-log de-duplication test via real execute-phase delivery path.
- **W-4:** 02-08 dispatcher-route check split into two specific assertions (`^claude-session$`, `^regex-fallback$`).
- **W-5:** 02-07 Task 1 wording aligned: "zero matches except lines tagged `# AOS: intentional gate`".
- **W-6:** 02-01 audit-log schema (still schema_version=1) extended with `decision_id`, `outcome` (null on write), `correlation_id`. STRUCTURE.md (02-09) documents the full schema.

### Iter 3 fixes (this revision)

- **NEW-B-1 (02-06):** Moved `ark_escalate repeated-failure` from inside the (unreachable) ESCALATE_REPEATED case branch to the post-loop rejection block. Escalation now ALWAYS fires when the rejection sentinel is written, regardless of which case branch caused exhaustion. `done` block now includes a synthetic 4-dispatch-fail test that verifies ark_escalate was actually invoked (via ESCALATIONS.md or audit log grep).
- **NEW-B-2 (02-06b):** Removed inline `_self_heal_log` helper which wrote a shorter schema (no decision_id/outcome/correlation_id). All class:self_heal audit writes now go through `_policy_log` from sourced ark-policy.sh — single writer, single schema. 02-08 mirrors the budget-class decision_id assertion for class:self_heal lines.
- **NEW-W-1 (02-08):** Dedup test now uses isolated VAULT_PATH (tmp dir + copied scripts + empty log) to prevent concurrent-write poisoning. Plan body documents the BLACK-tier call graph; expected DELTA pattern is `(1|2)` until the executor pins it from the trace.
- **NEW-W-2 (02-06 + 02-06b):** Added 02-06 Task 2 wiring `execute-phase.sh::dispatch_task` to invoke `self-heal.sh --retry` on dispatch failure (BEFORE the policy_dispatch_failure escalation block). This makes 02-06b live code in Phase 2, fulfilling CONTEXT.md decision #4's layered self-heal contract within this phase (not deferred to Phase 3). 02-06 now also modifies `scripts/execute-phase.sh`.
- **NEW-W-3 (02-04 + 02-08):** Synthetic test added to 02-04 Task 2a `done` AND a Tier 8 check verifies the session-handoff sentinel cost record is OBSERVABLE in the budget log (BEFORE/AFTER delta ≥ 1 with the literal `claude-session-handoff` string). Guards against the `|| true` silently swallowing a wrong --record signature.
- **NEW-W-4 (02-01 + 02-08):** decision_id suffix changed from 6-decimal-digit `RANDOM*RANDOM%1000000` (~20 effective bits) to 16 hex chars from `/dev/urandom` via `od -An -tx8` (64-bit entropy, macOS-safe). 02-01 self-test adds a stress assertion (100 calls → 100 distinct IDs); 02-08 mirrors it as a Tier 8 check.

## Requirements coverage

REQ-AOS-01..REQ-AOS-07 map to the 7 Phase 2 acceptance criteria in CONTEXT.md.
These IDs are minted in plan frontmatter; add them to `.planning/REQUIREMENTS.md` as part of 02-09.

| Req | Covered by |
|-----|------------|
| REQ-AOS-01 (zero stdin, simulated quota run) | 02-08 (verify), 02-04/02-05/02-06/02-06b/02-07 (the wiring that makes it true) |
| REQ-AOS-02 (ark-policy.sh + cascading config + delegation) | 02-01, 02-03, 02-04, 02-05, 02-06, 02-06b |
| REQ-AOS-03 (ESCALATIONS.md + `ark escalations`) | 02-02 |
| REQ-AOS-04 (policy-decisions.jsonl audit log w/ decision_id/outcome/correlation_id) | 02-01 |
| REQ-AOS-05 (Tier 8 verify, Tier 1–7 still pass) | 02-08 |
| REQ-AOS-06 (observer manual-gate-hit pattern) | 02-07 |
| REQ-AOS-07 (STRUCTURE.md AOS contract) | 02-09 |

## Notes on the existing draft

The previous single-file `PLAN.md` and the existing draft `scripts/ark-policy.sh` are
**superseded** by this multi-plan set. 02-01 refines the existing module (cascading config
loader is the missing piece) rather than replacing it.
