---
phase: 03-self-improving-self-heal
plan: 03
subsystem: aos-policy-auto-patcher
status: complete
tags: [aos, phase-3, auto-patch, policy-yml, self-improve, mkdir-lock, idempotent]
requires:
  - scripts/policy-learner.sh             # learner_collect_pending + $PENDING_FILE (03-02)
  - scripts/ark-policy.sh                 # _policy_log (single audit writer)
  - scripts/lib/policy-db.sh              # db_path, db_insert_decision
provides:
  - learner_apply_pending                # JSONL pending → policy.yml patch + git + audit
  - _lrn_acquire_lock                    # portable mkdir-lock (macOS-safe; no flock)
  - _lrn_release_lock                    # rmdir-based release
  - _lrn_is_true_blocker                 # defense-in-depth re-check
affects:
  - "~/vaults/ark/policy.yml"             # auto-created on first patch with header
  - "~/vaults/ark/.policy-yml.lock/"      # transient lock dir during apply
  - vault git repo                        # 1 commit per applied verdict
  - "observability/policy.db"             # +1 self_improve row per applied verdict
tech-stack:
  added: [mkdir-lock-pattern, atomic-yaml-rename, idempotent-shasum-guard]
  patterns: [single-writer-rule, defense-in-depth-blocker-filter, graceful-git-degradation, archived-pending-trail]
key-files:
  created:
    - .planning/phases/03-self-improving-self-heal/03-03-SUMMARY.md
  modified:
    - scripts/policy-learner.sh
decisions:
  - mkdir-lock pattern over flock(1). macOS does not ship flock by default; mkdir is atomic on POSIX and works without extra deps. Lock is $VAULT_PATH/.policy-yml.lock; pid is stamped inside for diagnostics; rmdir on release.
  - Idempotency by content hash. Compute shasum of policy.yml before and after the python patch. If unchanged, no audit entry and no git commit. Re-running the same pending file is a true no-op (verified by self-test).
  - Pending file archived only when at least one patch applied. Pure no-op runs leave $PENDING_FILE in place so the next invocation with new context can retry. Archive name is ${PENDING_FILE}.applied-<epoch>.
  - Defense-in-depth true-blocker filter. 03-02 already filters in collect_pending, but 03-03 re-checks _lrn_is_true_blocker on every line before patching. If 03-02 ever regresses, the patcher still refuses to write a true-blocker into policy.yml.
  - PyYAML-preferred / dotted-key fallback. PyYAML is the primary patch path because it preserves YAML structure across runs. A dotted-key append fallback is provided so the patcher remains operational on minimal Python installs (no pip yaml). Fallback skips itself if all new lines are already present (idempotent).
  - Auto-apply is opt-in. learner_run only calls learner_apply_pending when LEARNER_AUTO_APPLY=1. This keeps the 03-02 sidecar shasum-idempotency self-test working unchanged and makes ark-deliver the integrating layer that decides when to flip the bit.
  - First-write policy.yml header. When policy.yml does not exist, learner_apply_pending creates it with an explanatory comment block so a future human reader knows the file is auto-managed and which classes are excluded.
  - Audit `class:self_improve` decisions. PROMOTED for promote actions, DEPRECATED for deprecate actions. Reason field is `rate_pct_${rate_pct}_count_${count}` for grep-friendliness. Context JSON carries the full pattern tuple. correlation_id = first decision_id from the verdict's decision_ids array (chains audit back to source evidence) when present, else NULL.
  - Vault git not required. If $VAULT_PATH is not a git repo, the patch is still written and the audit row still emitted; only the commit is skipped (with a stderr warning). The user-facing reversibility guarantee degrades but the learning loop continues.
  - Concurrent runs serialize, do not deadlock. Two parallel learner_apply_pending invocations both go through mkdir-lock; the loser waits up to 30s. Self-test launches two background invocations with the same pending file and asserts the lock dir is gone afterward and the commit count stays bounded (4-5 commits, never double-applied).
metrics:
  tests_added: 16
  tests_total: 43
  duration_seconds: ~4 (self-test wall time, includes concurrent-run sleep)
  completed: 2026-04-26
---

# Phase 3 Plan 03-03: policy.yml auto-patcher Summary

Closed the learning loop: pending verdicts from 03-02 are now applied to `~/vaults/ark/policy.yml` atomically, every patch produces a vault git commit + a `class:self_improve` audit row, and concurrent invocations cannot corrupt the file. This is the first plan that actually mutates the policy substrate based on observed outcomes.

## Public API additions

`scripts/policy-learner.sh` (extends 03-02; same source-or-execute lib pattern):

| Function | Signature | Returns |
|---|---|---|
| `learner_apply_pending` | `[pending_file]` (default `$PENDING_FILE`) | echoes summary line, returns 0 on success, 1 on lock failure |
| `_lrn_acquire_lock` | `<lock_dir> [timeout_seconds]` | 0 on acquired, 1 on timeout |
| `_lrn_release_lock` | `<lock_dir>` | always 0 (rmdir best-effort) |
| `_lrn_is_true_blocker` | `<class> <decision>` | 0 if blocker, 1 otherwise |

CLI subcommand: `bash scripts/policy-learner.sh apply [PENDING_FILE]` for ad-hoc invocation.

Opt-in auto-apply: `LEARNER_AUTO_APPLY=1 bash scripts/policy-learner.sh run` chains score → apply in one call.

## Lock pattern

```
$VAULT_PATH/.policy-yml.lock/
└── pid       # this run's $$ for diagnostics
```

`mkdir` is atomic on macOS and Linux. No flock(1) dependency. Acquire loop polls every 1s up to 30s. Release is `rmdir` (best-effort; ignored if already gone). The lock is held only during the python patch + shasum compare; audit log writes and git commits happen outside the lock to keep the critical section minimal.

## YAML patch shape

```yaml
learned_patterns:
  dispatch_failure:
    SELF_HEAL:
      gemini:
        deep:
          confidence_pct: 100
          preferred: true
      RETRY:
        haiku:
          simple:
            confidence_pct: 20
            deprecated: true
  self_heal:
    ATTEMPT:
      codex:
        deep:
          confidence_pct: 83
          preferred: true
```

Path: `learned_patterns.<class>.<decision>.<dispatcher>.<complexity>.{preferred|deprecated, confidence_pct}`. `preferred` and `deprecated` are mutually exclusive — promoting clears any prior `deprecated`, and vice versa. `confidence_pct` is always overwritten with the latest score.

## Audit class addition

`class:self_improve` is a NEW class value in the audit log. `schema_version` stays at 1 (no schema bump). Two decision values:

| Decision | Trigger |
|---|---|
| `PROMOTED` | An `action:promote` verdict was successfully applied to policy.yml |
| `DEPRECATED` | An `action:deprecate` verdict was successfully applied to policy.yml |

Reason field: `rate_pct_<NN>_count_<N>` (grep-friendly). Context: `{"class","decision","dispatcher","complexity","rate_pct","count"}` from the source verdict. correlation_id: first decision_id from the verdict's `decision_ids` array, or NULL if absent.

The 03-02 SQL aggregator excludes `class IN ('escalation','self_improve')`. This is critical: it prevents the learner's own audit trail from feeding back into its own scoring (recursive amplification). 03-03 emitting `self_improve` rows is therefore safe — they will never be scored.

## Defense-in-depth blocker filter

03-02's `_pl_is_true_blocker` filters during scoring. 03-03's `_lrn_is_true_blocker` filters again before patching. They share the same logic (label match + `class=escalation` + `(class=budget AND decision=ESCALATE_MONTHLY_CAP)`) but live in independent code paths so a regression in one cannot leak true-blockers into policy.yml. The self-test step 8 includes a `class=budget,decision=ESCALATE_MONTHLY_CAP` line in the synthetic pending file with `count:100, rate_pct:100` and asserts it does NOT appear in the patched policy.yml content (comments are excluded from the grep).

## Idempotency guarantee

Re-applying the same pending file produces:
- 0 new audit rows
- 0 new git commits
- policy.yml byte-identical to prior run

Mechanism: shasum policy.yml before and after the python patch under the lock. If equal, treat as no-op and continue without auditing or committing. PyYAML's `safe_dump(sort_keys=True)` produces deterministic output. Dotted-key fallback path also short-circuits when all target lines are present.

Verified by self-test: rebuild the same pending JSONL, re-run apply, assert commit count and self_improve row count unchanged (still 3).

## Self-test (`bash scripts/policy-learner.sh test` step 8)

16 new assertions on top of 03-02's 27 (43 total, all passing). Isolated to `mktemp -d` tmp vault and `/tmp/ark-apply-test-$$.db`:

1. policy.yml created in tmp vault on first apply
2. ≥2 `preferred: true` entries (matches 2 PROMOTE verdicts)
3. ≥1 `deprecated: true` entry (matches 1 DEPRECATE verdict)
4. true-blocker (`ESCALATE_MONTHLY_CAP`) absent from policy.yml content (header comment excluded)
5. lock dir removed after run
6. 3 git commits in tmp vault (2 auto-promote + 1 auto-deprecate; blocker skipped)
7. 2 commits with `auto-promote` prefix
8. 1 commit with `auto-deprecate` prefix
9. 3 `class:self_improve` rows in audit DB
10. 2 `decision:PROMOTED` rows
11. 1 `decision:DEPRECATED` row
12. correlation_id of first promote == `dec_a` (first decision_id from input set)
13. pending file archived (renamed) after apply
14. exactly 1 `.applied-<ts>` archive exists
15. re-apply leaves commit count unchanged (idempotent)
16. re-apply leaves audit row count unchanged (idempotent)
17. lock dir released after concurrent runs
18. concurrent runs produced 4-5 total commits (no double-apply)

Plus the existing 03-02 self-test (27 assertions) still passes unchanged (`learner_run` does not auto-apply unless `LEARNER_AUTO_APPLY=1`).

## Verification

- `bash scripts/policy-learner.sh test` → exit 0, 43/43 pass
- `bash scripts/lib/outcome-tagger.sh test` → still 18/18 (no regression)
- `bash scripts/ark-policy.sh test` → still 15/15 (no regression)
- `grep -c '_policy_log "self_improve"' scripts/policy-learner.sh` → 2 (the audit-emit call + the comment header reference)
- `grep -E '_lrn_acquire_lock|_lrn_release_lock' scripts/policy-learner.sh | wc -l` → 4 (def + use of both)
- No `>>` redirect to `policy-decisions.jsonl` anywhere in policy-learner.sh — only `_policy_log` writes audit data (single-writer rule preserved)

## Deviations from Plan

1. **Auto-apply is opt-in via `LEARNER_AUTO_APPLY=1`, not unconditional.** The plan says "Update `learner_run` to call `learner_apply_pending` at the end". Doing this unconditionally would break the 03-02 self-test (which calls `learner_run` twice and shasum-compares the sidecar file — apply archives the sidecar, breaking the second hash compare). Honored the plan's intent (`learner_run` can chain into apply) by adding the env-var gate, which keeps both 03-02 and 03-03 self-tests green and lets ark-deliver flip the bit when integration is ready. (Rule 3 — fix blocking issue caused by exact-spec interpretation.)
2. **Source-shielding of ark-policy.sh.** The plan suggested `source "$_LRN_SCRIPTS_DIR/ark-policy.sh"` directly. ark-policy.sh's tail block runs the self-test when `$1=test`, which would fire every time policy-learner.sh is invoked with `test`. Save+clear `$@`, source, restore — `_LRN_SAVED_ARGS` array. Rule 3 — without this guard, the self-test crashes mid-source.
3. **First-write policy.yml header.** Plan says "create on first patch with explanatory header" — I added a small block describing auto-management and the true-blocker exclusion list. The test had to switch to `grep -v '^[[:space:]]*#' | grep -c "ESCALATE_MONTHLY_CAP"` to avoid matching the header comment that mentions the blocker by name. Acceptance assertion #4 covers the corrected check.
4. **Pending sidecar's `decision_ids` field is optional.** The 03-02 sidecar emitter does NOT currently include `decision_ids` (it emits `class, decision, dispatcher, complexity, count, rate_pct, rate` only). My patcher tries to read `$.decision_ids[0]`; when absent, correlation_id is set to NULL. The self-test's synthetic pending lines include `decision_ids` to verify correlation_id propagation. A future plan should patch 03-02 to include `decision_ids` for production correlation chaining.
5. **JSON parsing via sqlite3 `:memory:`** rather than jq. Consistent with 03-02's pattern (sqlite3 is already a hard dep; jq is not formally listed). One sqlite3 invocation per JSON field per pending line; could be optimised in a follow-up.
6. **Dotted-key fallback writer is lossy** — appends rather than replaces existing keys. Acceptable for the Phase 3 self-test which uses PyYAML; the fallback only fires on systems without pip-yaml installed, where the loss-of-fidelity tradeoff is preferable to crashing the learning loop.

## Deferred (out of scope for 03-03)

- 03-02's `learner_run` writes the digest to the real `~/vaults/ark/observability/policy-evolution.md` even during self-test (because the test doesn't override `_DIGEST_VAULT_PATH`). Pre-existing 03-02 issue; logged for a future cleanup. The policy.db isolation in 03-02 is correct via `ARK_POLICY_DB`; only the digest path is leaky.
- 03-02 sidecar JSONL does not yet include `decision_ids[]` per verdict. Tracked as a follow-up so future correlation_ids in `class:self_improve` rows can be non-null in production.

## Self-Check: PASSED

- Modified file exists: scripts/policy-learner.sh ✅
- Self-test passes 43/43: ✅
- Dependency tests still pass (outcome-tagger 18/18, ark-policy 15/15): ✅
- Acceptance grep — `_policy_log "self_improve"` ≥1: ✅ (2)
- Acceptance grep — `_lrn_acquire_lock|_lrn_release_lock` ≥4: ✅ (4)
- Acceptance grep — `_lrn_is_true_blocker.*escalation` succeeds: ✅
- No `>>` append to policy-decisions.jsonl outside `_policy_log`: ✅
- Commit hash: 6ec3029 ✅
