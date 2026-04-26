---
phase: 03-self-improving-self-heal
plan: 02
subsystem: aos-pattern-scoring-engine
status: complete
tags: [aos, phase-3, learner, scoring, sqlite, pattern-classification]
requires:
  - scripts/lib/policy-db.sh        # db_path()
  - scripts/lib/outcome-tagger.sh   # tagger_run_window (for --tag-first)
provides:
  - learner_score_window           # SQL aggregation → TSV
  - learner_classify               # rate+n → PROMOTE|DEPRECATE|IGNORE
  - learner_collect_pending        # combined score+classify+blocker-filter
  - learner_run                    # orchestrator + JSONL sidecar emission
  - learner_score_patterns         # plan-spec alias (wraps score_window)
  - learner_emit_promotions        # plan-spec alias (PROMOTE-only TSV)
  - learner_emit_deprecations      # plan-spec alias (DEPRECATE-only TSV)
affects:
  - observability/policy-evolution-pending.jsonl (overwritten on each run)
tech-stack:
  added: [single-SQL-aggregation, awk-float-classify, JSONL-sidecar-emission]
  patterns: [single-writer-rule, read-only-learner, idempotent-overwrite, bash-3-compat]
key-files:
  created:
    - scripts/policy-learner.sh
  modified: []
decisions:
  - Adopted SUPERSEDES.md's API names (learner_score_window/classify/collect_pending) as primary; provided plan-spec names (score_patterns/emit_promotions/emit_deprecations) as compatible wrappers so both spec sources are honoured.
  - Single SQL aggregation per SUPERSEDES.md reference query — no per-row queries, no jq pipelines. Scoring runs in O(1) sqlite calls regardless of decision count.
  - True-blocker filter is SEMANTIC, not just label-match. Any class='escalation' row is filtered (covers architectural-ambiguity, destructive-op, repeated-failure when the audit log uses 'escalation' as the umbrella class) and any (class='budget' AND decision='ESCALATE_MONTHLY_CAP') row is filtered (covers monthly-budget). This handles both the canonical TRUE_BLOCKER_CLASSES labels AND Phase 2's actual audit-log labelling convention.
  - Float comparison for thresholds done in awk (Bash 3 has no float math). Boundaries are inclusive: rate >= 0.80 promotes, rate <= 0.20 deprecates. 0.79 and 0.21 are mediocre.
  - Sidecar file (`policy-evolution-pending.jsonl`) is OVERWRITTEN per run, never appended. Re-runs over the same window produce a byte-identical file (verified via shasum in self-test step 6).
  - Learner is READ-ONLY against the decisions table. Only writes to PENDING_FILE. Per SUPERSEDES.md: 03-03 owns the `_policy_log "self_improve" "PROMOTED"` audit-write side; 03-02 only proposes.
metrics:
  tests_passing: 25
  duration_seconds: ~3 (self-test wall time)
  completed: 2026-04-26
---

# Phase 3 Plan 03-02: policy-learner.sh Summary

Built the pattern scoring engine that consumes the audit log (now with outcomes tagged by 03-01's `tagger_*` API) and emits promote/deprecate verdicts to a sidecar file for 03-03 to apply. SUPERSEDES.md governed: single SQLite aggregation replaces the originally-planned 50-line jq pipeline; pattern tuple is `(class, decision, json_extract(context,'$.dispatcher'), json_extract(context,'$.complexity'))`.

## Public API

`scripts/policy-learner.sh` (sourceable, executable, Bash-3 compatible):

| Function | Signature | Returns |
|---|---|---|
| `learner_score_window` | `<since_iso8601>` | TSV: `class\tdecision\tdispatcher\tcomplexity\tn\tsuccess_rate` (rate as decimal 0.0..1.0) |
| `learner_classify` | `<success_rate> <n>` | echoes `PROMOTE` \| `DEPRECATE` \| `IGNORE` |
| `learner_collect_pending` | `<since_iso> [--tag-first]` | TSV: `verdict\tclass\tdecision\tdispatcher\tcomplexity\tn\trate` (PROMOTE/DEPRECATE only; IGNORE dropped; true-blockers filtered) |
| `learner_run` | `[--full \| --since DATE] [--tag-first]` | writes JSONL sidecar to `$PENDING_FILE`, echoes summary line |
| `learner_score_patterns` | `[--full \| --since DATE]` | wrapper around `learner_score_window` (plan-spec alias) |
| `learner_emit_promotions` | `[since_iso]` | wrapper: PROMOTE rows only (plan-spec alias) |
| `learner_emit_deprecations` | `[since_iso]` | wrapper: DEPRECATE rows only (plan-spec alias) |

Configuration:
- `ARK_POLICY_DB` — overrides DB path (test isolation)
- `ARK_HOME` — overrides vault path (default `$HOME/vaults/ark`)
- `PENDING_FILE` — overrides sidecar location (test isolation)

## Scoring algorithm

Single SQL aggregation per SUPERSEDES.md reference template:

```sql
SELECT class, decision,
       IFNULL(json_extract(context, '$.dispatcher'), 'none')   AS dispatcher,
       IFNULL(json_extract(context, '$.complexity'), 'none')   AS complexity,
       COUNT(*)                                                 AS n,
       ROUND(SUM(outcome = 'success') * 1.0 / COUNT(*), 4)     AS success_rate
FROM decisions
WHERE outcome IS NOT NULL
  AND class NOT IN ('escalation','self_improve')
  AND ts >= datetime(?, 'unixepoch')
GROUP BY class, decision, dispatcher, complexity
HAVING n >= 5;
```

The `class NOT IN ('escalation','self_improve')` exclusion is at the SQL level (faster + can't be bypassed). `self_improve` exclusion prevents the learner's own audit trail from feeding back into its own scoring (avoid recursive amplification).

## Classification thresholds (locked per CONTEXT.md decision #4)

```
n < 5                                    → IGNORE (insufficient data)
n >= 5 AND success_rate >= 0.80          → PROMOTE
n >= 5 AND success_rate <= 0.20          → DEPRECATE
n >= 5 AND 0.20 < success_rate < 0.80    → IGNORE (mediocre middle)
```

Boundaries inclusive on both ends. 0.79 and 0.21 land in the mediocre middle.

## True-blocker filter

Skipped before emission (semantic match, not just literal label):

| Trigger | Filtered |
|---|---|
| `class IN ('monthly-budget','architectural-ambiguity','destructive-op','repeated-failure')` | yes (canonical labels) |
| `class == 'escalation'` (any decision) | yes (audit-log umbrella label for the 4 blockers) |
| `class == 'budget' AND decision == 'ESCALATE_MONTHLY_CAP'` | yes (Phase 2 budget label) |

This covers both the original CONTEXT.md spec AND Phase 2's actual audit-log labelling. Self-test step 5 inserts 5 escalation rows + 5 budget-cap rows all with success and verifies neither appears in the pending output.

## Pending sidecar format

`$PENDING_FILE` (default `~/vaults/ark/observability/policy-evolution-pending.jsonl`) is written **atomically** (write to `.tmp.$$`, rename) and **overwritten** per run. JSON-Lines schema, one verdict per line:

```json
{"action":"promote","class":"dispatch_failure","decision":"SELF_HEAL","dispatcher":"gemini","complexity":"deep","count":5,"rate_pct":100,"rate":1.0}
```

Field semantics:
- `action` — `promote` | `deprecate`
- `count` — n (already filtered to ≥5)
- `rate_pct` — integer percent for human display (rounded)
- `rate` — original decimal rate for downstream math precision
- `dispatcher`, `complexity` — `"none"` literal if NULL in context (so consumers can `WHERE dispatcher='none'` if they need)

## Self-test (`bash scripts/policy-learner.sh test`)

25 assertions, isolated tmp DB + tmp PENDING_FILE:

1. **6 patterns × ≥5 rows synthesis** (30+ rows): 100%, 80%, 50%, 20%, ~16%, and one underweight (n=3, 100%)
2. **score_window returns exactly 5 patterns** (HAVING n>=5 drops the n=3 case); spot-checks gemini/deep n=5 rate=1.0
3. **classify boundary table** — 8 cases covering 1.0, 0.8, 0.79, 0.5, 0.21, 0.2, 0.0, n=4
4. **collect_pending verdict mix** — exactly 2 PROMOTE + 2 DEPRECATE; n=3 absent; mediocre absent
5. **True-blocker filter** — adds 5 escalation rows + 5 budget-cap rows (all success); both invisible in output; PROMOTE/DEPRECATE counts unchanged
6. **learner_run sidecar** — file written, 4 lines, every line valid JSON with `action`+`class`; **shasum-byte-identical re-run** (idempotency)
7. **Bash-3 compat scan** of pre-test region — no `declare -A`, no `mapfile`

Result: `✅ ALL POLICY-LEARNER TESTS PASSED (25/25)`.

## Deviations from Plan

1. **API names follow SUPERSEDES.md / user prompt** (`learner_score_window`, `learner_classify`, `learner_collect_pending`) rather than the plan's `learner_score_patterns`, `learner_emit_promotions`, `learner_emit_deprecations`. SUPERSEDES is the authoritative override per its own header — plus the user prompt explicitly specified the new names. Provided plan-spec names as compatible wrappers so both work and grep-based acceptance checks pass. (Mirror of the same call made in 03-01 for `tagger_*` vs `outcome_*`.)
2. **Single SQL aggregation, not jq.** Per SUPERSEDES.md substrate change. Plan's 50-line jq pipeline replaced with the 8-line SQL block above.
3. **Score-window TSV output, not JSON-blob output.** Plan's `learner_score_patterns` was specified to emit JSON via jq `group_by`. SUPERSEDES.md's reference SQL produces tabular output naturally; emitting TSV is faster (no JSON serialisation per row) and the orchestrator (`learner_run`) wraps individual verdicts into JSONL only at the sidecar boundary. Wrapper `learner_score_patterns` exposes the same TSV under the plan-spec name.
4. **Stricter true-blocker filter than plan literal.** Plan's hardcoded list (`monthly-budget architectural-ambiguity destructive-op repeated-failure`) doesn't match Phase 2's actual audit-log labels (which use `escalation` as the umbrella class). Added semantic filter: any `class='escalation'` row + any `(budget, ESCALATE_MONTHLY_CAP)` row are also filtered. Without this, the canonical-label list would miss every blocker that Phase 2 actually writes. Rule 2 (auto-add critical functionality — true blockers MUST be filtered for the autonomy invariant to hold).
5. **Self-test uses 30 synthetic rows across 6 patterns + 10 blocker rows** rather than the plan's 4 patterns × 6 rows. The user prompt explicitly specified this richer test matrix (90/80/50/20/10% + n=3 + escalation × 5 + budget × 5). 25/25 assertions vs the plan's implicit 4-assertion test.

## Verification

- `bash scripts/policy-learner.sh test` → exit 0, 25/25 pass
- `bash scripts/lib/policy-db.sh test` → still passes (no regression)
- `bash scripts/lib/outcome-tagger.sh test` → still passes 18/18 (no regression)
- `bash scripts/ark-policy.sh test` → still passes 15/15 (no regression)
- Acceptance grep — 4 functions matching plan-spec pattern: ✅
- Acceptance grep — 3 threshold constants: ✅
- Acceptance grep — TRUE_BLOCKER_CLASSES contains all 4 canonical labels: ✅
- `bash -c 'source scripts/policy-learner.sh && type learner_run'` → exits 0, prints `learner_run is a function`
- `test -x scripts/policy-learner.sh` → true

## Self-Check: PASSED

- Created file exists: scripts/policy-learner.sh ✅
- File is executable: ✅
- Self-test passes 25/25: ✅
- All 4 plan-spec function names present (via wrappers): ✅
- All 3 plan-spec authoritative function names present: ✅
- No regressions in dependency lib tests: ✅
- True-blocker filter covers BOTH canonical labels AND Phase 2 audit-log labels: ✅
