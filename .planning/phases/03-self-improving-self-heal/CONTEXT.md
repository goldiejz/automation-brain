# Phase 3 — AOS: Self-Improving Self-Heal — Context

## Why this phase exists

Phase 2 built the policy engine with an audit log (`policy-decisions.jsonl`) locked at `schema_version=1` with `decision_id` (16-hex from `/dev/urandom`) and `outcome: null` fields specifically so Phase 3 could read those decisions and tag them retroactively.

Without Phase 3, the policy engine is **frozen**: every `policy_dispatch_failure` returns the same verdict every time, regardless of whether the chosen retry strategy actually worked. Patterns that never fix anything keep getting dispatched. Patterns that always work don't get prioritized. The system makes the same mistakes forever.

Phase 3 closes the loop: it reads the audit log, infers outcomes from delivery logs + git history, scores each pattern (which dispatcher + which complexity + which retry layer succeeds for which task class), and auto-promotes high-success patterns into the policy while auto-deprecating duds.

## Position in AOS roadmap

This is Phase 3 of the 6-phase AOS journey. After this:
- Phase 4: Bootstrap autonomy (`ark create` runs hands-off)
- Phase 5: Portfolio autonomy (Ark picks which project to ship next)
- Phase 6: Cross-customer learning autonomy (lessons promote across customers)
- Phase 7: Continuous operation (cron-driven INBOX consumption)

Phase 3 is the **meta-layer** that makes every subsequent phase smarter over time. Phase 4's bootstrap policies, Phase 5's portfolio priorities, Phase 6's lesson promotions all feed the same audit log and benefit from Phase 3's learner.

## User-confirmed architectural decisions

Grilled out via AskUserQuestion before planning:

### 1. Learner output — BOTH digest + auto-patch
- **Weekly digest** at `~/vaults/ark/observability/policy-evolution.md` (human-readable; Phase 7 consumes it)
- **Auto-patch** `~/vaults/ark/policy.yml` for high-confidence patterns
- Aggressive autonomy: when a pattern crosses the threshold, the learner writes the policy.yml change AND records it in the digest for review
- Audit trail: every auto-patch logged via `_policy_log "self_improve" "PROMOTED" ...` with the decision_ids it learned from as `correlation_id`

### 2. Outcome tagging — Heuristic from logs
- Read `<project>/.planning/delivery-logs/*.log` + `git log` within N minutes (configurable, default 10) of each `decision_id`
- If subsequent dispatch in the same phase succeeded → `outcome: "success"`
- If `class:escalation` line appeared with matching task → `outcome: "failure"`
- If neither (no follow-up signal within window) → `outcome: "ambiguous"`
- **NO schema change** — Phase 2 already provisioned `outcome: null`; learner patches in place via `jq`-style rewrites keyed on `decision_id`
- Implementation in `scripts/lib/outcome-tagger.sh` so other AOS subsystems can call the same tagger

### 3. Run cadence — Triggered post-phase
- After every `ark deliver` phase completion, ark-deliver invokes `bash scripts/policy-learner.sh --since-phase $PHASE_NUM`
- Tighter feedback loop than cron — patterns get scored as soon as a phase ships
- Doesn't compete with active deliveries (runs after, not during)
- Manual override: `ark learn [--full | --since <date>]` for ad-hoc runs

### 4. Promotion threshold — ≥5 occurrences + ≥80% success rate
- A pattern is `(class, decision, dispatcher, complexity)` tuple — e.g., `(dispatch_failure, SELF_HEAL, gemini, deep)`
- Count occurrences of the pattern with tagged outcomes
- Promote ONLY when `count >= 5 AND (success_count / count) >= 0.80`
- Deprecate when `count >= 5 AND (success_count / count) <= 0.20` (clearly broken)
- Between 20% and 80%: leave alone (mediocre, but not bad enough to deprecate, not good enough to promote)
- Threshold is hardcoded for Phase 3; can be made configurable via policy.yml in a follow-up if data justifies tuning

## Schema reuse (Phase 2 contract)

Phase 3 consumes the locked schema from Phase 2:
```json
{
  "ts": "<ISO8601>",
  "schema_version": 1,
  "decision_id": "<YYYYMMDDTHHMMSSZ>-<16-hex>",
  "class": "<...>",
  "decision": "<...>",
  "reason": "<...>",
  "context": {...},
  "outcome": null,            ← Phase 3 patches this
  "correlation_id": null      ← Phase 3 reads this for chains
}
```

Phase 3 does NOT bump `schema_version`. It patches `outcome` in-place via `jq` and links related decisions via `correlation_id`.

## Constraints

- Phase 2 acceptance must hold: Tier 7 14/14, Tier 8 25/25, no manual gates surfaced
- Backward compat: scripts that don't source the learner still work
- Auto-patch must be reversible: every policy.yml change committed to git in the vault repo with a clear message
- Learner runs must be idempotent: re-running over the same window produces the same result
- Aggressive autonomy is bounded: only `(class, decision, dispatcher, complexity)` tuples can be promoted; never override the 4 true-blocker escalation classes (those are user-confirmed and stay)

## Acceptance criteria (Phase 3 exit)

1. `scripts/policy-learner.sh` exists; sourceable + executable; self-test passes
2. `scripts/lib/outcome-tagger.sh` reads logs + git history within configurable window, patches `outcome` via `jq`, idempotent
3. `~/vaults/ark/observability/policy-evolution.md` weekly digest is generated by `ark learn`
4. `~/vaults/ark/policy.yml` is auto-patched when a pattern crosses 5/80% threshold; every patch is committed to vault git repo with a clear message and a `_policy_log "self_improve" "PROMOTED"` audit entry
5. ark-deliver invokes the learner post-phase (after `update_state` in `run_phase`)
6. `ark learn` subcommand exists for manual runs (`--full` reprocesses everything, `--since DATE` for windowed)
7. Tier 9 verify: synthetic audit log with known patterns → assert promotion fires for ≥5/≥80%, deprecation fires for ≥5/≤20%, mediocre middle is left alone
8. Existing Tier 1–8 still pass

## Out of scope (deferred to later phases)

- Configurable promotion thresholds via policy.yml (defer until data justifies it)
- Cross-customer pattern promotion (Phase 6)
- Bootstrap-decision learning (Phase 4)
- Real-time tail mode (defer; cron + post-phase trigger is enough for now)
- ML/embeddings — pure heuristic counting only

## Risks

1. **Bad outcome tagging poisons learning** — mitigated by tagger writing to a separate sidecar first, only patching once a verifier confirms the heuristic is right; tagger is itself testable
2. **Auto-patch races** — if two phases finish near-simultaneously and both trigger the learner, two policy.yml writes could conflict. Mitigated by file-lock around the auto-patch step
3. **Mediocre patterns ossify** — patterns that hover between 20–80% success rate are left alone forever. Acceptable trade-off; can be revisited if it becomes a problem.
