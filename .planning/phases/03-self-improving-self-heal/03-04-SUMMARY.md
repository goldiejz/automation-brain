---
phase: 03-self-improving-self-heal
plan: 04
subsystem: aos-policy-evolution-digest
status: complete
tags: [aos, phase-3, learner, digest, sqlite, observability]
requires:
  - scripts/lib/policy-db.sh        # db_path + schema
  - scripts/policy-learner.sh        # 03-02 — sources policy-digest.sh and calls learner_write_digest from learner_run
provides:
  - learner_write_digest             # ~/vaults/ark/observability/policy-evolution.md writer
affects:
  - ~/vaults/ark/observability/policy-evolution.md  # atomic overwrite each run
tech-stack:
  added: [policy-digest.sh standalone library, atomic tmp+mv, awk-bucketed scoring stream, SQL true-blocker exclusion]
  patterns: [single-quoted-heredoc-for-SQL, read-only-over-decisions, idempotent-overwrite, bash-3-compat]
key-files:
  created:
    - scripts/lib/policy-digest.sh
    - .planning/phases/03-self-improving-self-heal/03-04-SUMMARY.md
  modified:
    - scripts/policy-learner.sh   # appended digest shim + wired learner_run call + `digest` CLI subcommand
decisions:
  - Built policy-digest.sh as a STANDALONE module (vs. inline in policy-learner.sh) because 03-02's policy-learner.sh had not landed during the 60s polling window; it appeared mid-test, after which the digest was wired in via a shim. This kept the digest self-test independently runnable and avoided a merge race against an in-flight 03-02 commit.
  - Computed scoring directly in SQL (single GROUP BY query) rather than relying on 03-02's `learner_score_window`. Tradeoff= mild duplication of aggregation logic vs. independence from 03-02 API drift; consistent with SUPERSEDES.md's reference SQL.
  - True-blocker exclusion enforced at SQL level (`NOT (class='escalation') AND NOT (class='budget' AND decision='ESCALATE_MONTHLY_CAP')`) — same predicate 03-02's `_pl_is_true_blocker` uses, but applied earlier so excluded rows never even appear in the table-scan stream.
  - Idempotency normalised by stripping both `**Generated:** …` and `**Window:** …` lines in the diff, since the window's `until` defaults to `now` and changes between runs.
metrics:
  tests_passing: 11        # digest self-test (12 asserts; 1 fold combined into row-count)
  tests_passing_03_02: 25  # 03-02 learner self-test still passes 25/25 (no regression)
  duration_seconds: ~2     # digest self-test wall time
  completed: 2026-04-26
---

# Phase 3 Plan 03-04: policy-evolution.md digest writer Summary

Built the human-readable, read-only Phase 3 digest surface. Each `learner_run` now produces, alongside the pending sidecar (03-02) and policy.yml patch (03-03), a markdown view at `~/vaults/ark/observability/policy-evolution.md` summarising every pattern Ark has scored — promoted, deprecated, mediocre — plus the four immutable true-blocker classes that learning never touches. This is the surface Phase 7 (continuous operation) and humans alike consume.

## Public API

`scripts/lib/policy-digest.sh` (sourceable, executable, Bash-3 compatible):

| Function | Signature | Returns |
|---|---|---|
| `learner_write_digest` | `[since-iso8601]` (default `1970-01-01T00:00:00Z`) | `0` on success; writes to `$ARK_HOME/observability/policy-evolution.md` |

Configuration:
- `ARK_HOME` — vault root, default `$HOME/vaults/ark`
- `ARK_POLICY_DB` — DB path override (test isolation)

CLI:
- `bash scripts/policy-learner.sh digest [SINCE]` — write only the digest (no scoring/sidecar side-effect)
- `bash scripts/policy-learner.sh test` / `--full` / `--since` — digest is auto-written as part of `learner_run`

## Output schema (atomic-write, overwrite-each-run)

```markdown
# Policy Evolution Digest
**Window:** <since> → <until>
**Generated:** <iso8601>

## Promoted (≥5 occurrences, ≥80% success)
| Class | Decision | Dispatcher | Complexity | n | Success rate |
|...|...|...|...|...|...|

## Deprecated (≥5 occurrences, ≤20% success)
[same columns]

## Mediocre middle (20–80%, left alone)
[same columns]

## True-blocker classes (excluded from learning)
- monthly-budget
- architectural-ambiguity
- destructive-op
- repeated-failure
```

## Atomic-write guarantee

Writer streams the full digest to `${digest}.tmp.$$`, then `mv -f` to the final path. Single-syscall rename = readers never see a half-written file. No `.tmp.*` files are leaked on success (verified in self-test).

## Idempotency guarantee

Re-running `learner_write_digest` over the same DB state produces a byte-identical file modulo the `**Generated:** …` and `**Window:** …` timestamp lines. Self-test asserts this by diffing two consecutive runs with those lines stripped.

## True-blocker enforcement

Four classes are excluded from PROMOTE/DEPRECATE/MEDIOCRE at the SQL `WHERE` clause:
- `class = 'escalation'` — covers architectural-ambiguity, destructive-op, repeated-failure (all surfaced as escalation events in the audit log)
- `class = 'budget' AND decision = 'ESCALATE_MONTHLY_CAP'` — the monthly-budget true-blocker

These four classes still appear as a static list in the digest's bottom section so humans can see they're excluded by design, never by accident. Self-test asserts no escalation/budget tuple ever lands in any of the three data tables.

## Read-only invariant

The writer issues exactly one read-only SQL statement against `decisions` (single GROUP BY aggregation) and never `INSERT`s, `UPDATE`s, or `DELETE`s. Verified by inspection — no write SQL keywords in `_digest_score_tsv`. The digest also never modifies `policy.yml` (that is 03-03's exclusive responsibility).

## Integration with 03-02

When this plan started, `scripts/policy-learner.sh` did not exist. Per the executor instructions ("If 03-02 hasn't landed yet, write a NEW file `scripts/lib/policy-digest.sh` instead"), the digest was implemented as a standalone library. 03-02's policy-learner.sh landed mid-test; the integration is now:

1. `scripts/policy-learner.sh` `source`s `scripts/lib/policy-digest.sh` (guarded by `_LEARNER_DIGEST_LOADED`).
2. `learner_run` calls `learner_write_digest "$since_iso"` immediately after `mv "$tmp_pending" "$PENDING_FILE"`. Failure is non-fatal (digest is the human view; the pending sidecar consumed by 03-03 remains authoritative).
3. CLI subcommand `bash scripts/policy-learner.sh digest [SINCE]` invokes the digest writer in isolation (handy for debugging without touching the sidecar).

A future cleanup option is to inline `learner_write_digest` directly into `policy-learner.sh` and delete `policy-digest.sh`. The current shim was preferred to:
- keep 03-04's tests independently runnable (`bash scripts/lib/policy-digest.sh test`),
- avoid a merge race against 03-02's commit,
- keep the digest writer's surface area minimal (`policy-digest.sh` is ~140 lines).

## Self-test (`bash scripts/lib/policy-digest.sh test`)

11 assertions covering:
- digest file exists at expected path
- 4 section headers present (Promoted, Deprecated, Mediocre, True-blocker classes)
- exactly 1 data row in each of Promoted / Deprecated / Mediocre for the synthetic fixture (gemini/deep@83%, codex/simple@16%, haiku/medium@50%)
- true-blocker tuples (`ESCALATE_MONTHLY_CAP`, `ESCALATE_REPEATED_FAILURE`) excluded from all three data tables
- idempotency: two consecutive runs produce byte-identical output modulo timestamp lines
- atomic-write hygiene: no leftover `.tmp.*` files

Result: `✅ ALL DIGEST TESTS PASSED` (11 passed / 0 failed).

## Verification

- `bash scripts/lib/policy-digest.sh test` → exit 0, 11/11 pass
- `bash scripts/policy-learner.sh test` → still passes 25/25 (03-02 self-test, no regression; digest is now also exercised inside `learner_run` step 6)
- `bash scripts/lib/policy-db.sh test` → passes (no regression)
- `bash scripts/lib/outcome-tagger.sh test` → passes 18/18 (no regression)
- `bash -c 'source scripts/lib/policy-digest.sh && type learner_write_digest'` → exits 0
- Manual fixture run produces digest matching the prompt's reference schema exactly

## Deviations from Plan

1. **Wrote standalone `scripts/lib/policy-digest.sh` rather than appending to `scripts/policy-learner.sh` directly.** Plan 03-04 specifies appending to `policy-learner.sh`. The user prompt's contingency clause governed: 03-02 had not landed within the 60s polling window, so I wrote `policy-digest.sh`. When 03-02 appeared mid-test, I added a thin sourcing shim into `policy-learner.sh` (per the user prompt's "if it exists already, append … don't replace"). Net result is functionally equivalent — `learner_write_digest` is reachable from `policy-learner.sh`'s `learner_run` and from its `digest` CLI subcommand — with the bonus that the digest writer remains independently testable.
2. **Section header text differs from plan's stated schema.** Plan template says `## Promoted patterns (rate ≥ 80%, n ≥ 5)`; user prompt says `## Promoted (≥5 occurrences, ≥80% success)`. The prompt is the authoritative override (written after the plan), and 03-02's self-test now grep-matches `^## Promoted` which works under either wording. Likewise for Deprecated and Mediocre.
3. **No "Recent self_improve audit entries" section.** Plan template includes a fourth section listing the last 20 `class:self_improve` audit entries. The user prompt's required section list is exactly four (Promoted / Deprecated / Mediocre / True-blocker classes); the prompt is authoritative. Phase 3 Plan 03-03 (which writes the `self_improve` audit entries) can extend the digest writer in a follow-up if humans request that surface.
4. **Read-only over the audit DB only — no pending-sidecar consumption.** Plan suggests reading 03-02's pending sidecar to also list "what was just promoted/deprecated this run". The prompt's required schema is purely the score-bucketing view; consuming the sidecar would couple the digest to 03-02's wire format. Keeping it pure is preferred and matches `must_haves.truths[2]` ("read-only over the audit log + pending sidecar; never modifies policy.yml") — the plan's own prose says read-only.

## Self-Check: PASSED

- Created file exists: `scripts/lib/policy-digest.sh` ✅
- Modified file exists: `scripts/policy-learner.sh` (with `learner_write_digest` shim + `learner_run` call + `digest` CLI subcommand) ✅
- Both files executable: ✅ (`-rwxr-xr-x`)
- Digest self-test: 11/11 passing ✅
- 03-02 learner self-test: 25/25 still passing ✅ (no regression)
- Outcome-tagger and policy-db self-tests: still passing ✅
- `bash -c 'source scripts/lib/policy-digest.sh && type learner_write_digest'` → exits 0 ✅
- True-blocker classes never appear in promote/deprecate/mediocre tables ✅
- Idempotent: two consecutive runs produce byte-identical output (modulo timestamps) ✅
