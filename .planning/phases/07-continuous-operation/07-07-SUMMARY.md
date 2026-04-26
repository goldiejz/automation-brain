---
phase: 07-continuous-operation
plan: 07
subsystem: aos-continuous-operation
tags: [verify, tier-14, phase-7-exit-gate, inbox-lifecycle, kill-switch, weekly-digest, plist, regression-sweep]
requirements: [REQ-AOS-47, REQ-AOS-48]
dependency_graph:
  requires:
    - "07-01-SUMMARY (inbox-parser.sh contract)"
    - "07-04-SUMMARY (ark-continuous.sh subcommands + plist)"
    - "07-05-SUMMARY (ark dispatcher cmd_continuous arm)"
    - "07-06-SUMMARY (ark-weekly-digest.sh contract)"
  provides:
    - "Tier 14 verify suite (28 checks) covering Phase 7 acceptance criteria #2/#6/#7/#8/#9"
    - "Phase 7 exit-gate evidence: synthetic 3-intent INBOX lifecycle, safety rails, real-vault md5 invariant, real LaunchAgents absence-check"
  affects:
    - "scripts/ark-verify.sh (Tier 14 dispatch arm + sign-off section entry)"
tech_stack:
  added: []
  patterns:
    - "mktemp -d isolation triplet (vault + portfolio + LaunchAgents)"
    - "Real-vault md5 invariant capture (Phase 4 GitHub-incident lesson)"
    - "Self-referential test-pattern trap (Phase 4): regex assembled char-class-wise so this file does not self-match"
    - "PATH-mocked `ark` so dispatch never invokes real ark/GitHub"
    - "Canonical env var override (ARK_CONTINUOUS_DAILY_TOKEN_CAP=0) to force DAILY_CAP_HIT path"
    - "Pre-create $VAULT_PATH/.continuous.lock dir to force LOCK_CONTENDED path"
key_files:
  created: []
  modified:
    - "scripts/ark-verify.sh (Tier 14 block, ~250 lines, between Tier 13 and Generate-report)"
decisions:
  - "Tier 14 isolates with mktemp -d for vault + portfolio + LaunchAgents (no real-path writes)"
  - "Mock `ark` on PATH so synthetic dispatch returns 0 without invoking real ark/GitHub"
  - "Force DAILY_CAP_HIT via ARK_CONTINUOUS_DAILY_TOKEN_CAP=0 (used=0 ≥ cap=0 → suspended)"
  - "Force LOCK_CONTENDED by pre-creating $VAULT_PATH/.continuous.lock (canonical lock path, top of vault not observability/)"
  - "Tier 7-13 sweep runs informationally only (does not block Tier 14 pass count) — separate `bash scripts/ark-verify.sh --tier N` invocations confirm baselines individually"
  - "read -p regression sweep mirrors the in-script Test 14 hygiene regex (^[[:space:]]*read[[:space:]]+-p), avoiding false positives from string literals like \"Test 14: no read -p in code\""
metrics:
  duration_minutes: 12
  completed: "2026-04-26T20:58:00Z"
  tasks_completed: 1
  files_modified: 1
  commits: 1
---

# Phase 7 Plan 07-07: Tier 14 verify suite Summary

Added a 28-check Tier 14 to `scripts/ark-verify.sh` validating the AOS Continuous-Operation surface end-to-end against synthetic mktemp-isolated fixtures, with real-vault md5 invariants and real `~/Library/LaunchAgents` absence-checks proving the suite never touches production paths. Tier 14 = 28/28 pass. Tiers 7-13 baselines retained (T7=14/14, T8=24/25 [Phase 6.5 deferred], T9=20/20, T10=22/22, T11=16/16, T12=24/24, T13=30/30).

## 28-check matrix

| # | Group | Check | Pass |
|---|-------|-------|------|
| 1 | Static wiring | scripts/ark-continuous.sh exists + executable | ✅ |
| 2 | Static wiring | scripts/lib/inbox-parser.sh exists + sourceable | ✅ |
| 3 | Static wiring | scripts/ark-weekly-digest.sh exists + executable | ✅ |
| 4 | Static wiring | ark dispatcher has cmd_continuous + continuous arm | ✅ |
| 5 | Static wiring | bash -n on all 3 phase-7 scripts | ✅ |
| 6 | Self-test | inbox-parser.sh ≥16/16 pass (actual: 31/31) | ✅ |
| 7 | Self-test | ark-continuous.sh ≥34/34 pass (actual: 65/65) | ✅ |
| 8 | Self-test | ark-weekly-digest.sh ≥11/11 pass (actual: 11/11) | ✅ |
| 9 | INBOX lifecycle | 3 files moved to processed/UTC-date/ | ✅ |
| 10 | INBOX lifecycle | 0 files left in INBOX root | ✅ |
| 11 | INBOX lifecycle | 0 .failed and 0 .malformed siblings | ✅ |
| 12 | INBOX lifecycle | 3 INBOX_PROCESSED audit rows + ≥1 TICK_COMPLETE row | ✅ |
| 13 | INBOX lifecycle | no .tmp* atomic-move detritus | ✅ |
| 14 | Safety rail | PAUSE present → PAUSE_ACTIVE row + INBOX untouched | ✅ |
| 15 | Safety rail | daily cap=0 → DAILY_CAP_HIT row + INBOX untouched | ✅ |
| 16 | Safety rail | lock held → LOCK_CONTENDED row | ✅ |
| 17 | Plist | continuous plist written + plutil -lint OK + StartInterval + ark-continuous.sh ref | ✅ |
| 18 | Weekly digest | file produced + ≥6 section headers + WEEKLY_DIGEST_WRITTEN row | ✅ |
| 19 | Regression | no `read -p` in continuous-path scripts | ✅ |
| 20 | Subcommand | pause creates PAUSE file | ✅ |
| 21 | Subcommand | resume removes PAUSE file | ✅ |
| 22 | Subcommand | status returns 0 + mentions Last tick / no ticks yet | ✅ |
| 23 | Invariant | real policy.db md5 unchanged | ✅ |
| 24 | Invariant | real ESCALATIONS.md md5 unchanged | ✅ |
| 25 | Invariant | real universal-patterns.md md5 unchanged | ✅ |
| 26 | Invariant | real anti-patterns.md md5 unchanged | ✅ |
| 27 | Invariant | real ~/Library/LaunchAgents/com.ark.continuous.plist unchanged | ✅ |
| 28 | Invariant | real ~/Library/LaunchAgents/com.ark.weekly-digest.plist unchanged | ✅ |

**Tier 14: 28/28 pass.**

## Tier 7-13 regression sweep

Each tier was invoked individually after Tier 14 wrote its block. Counts retained vs baseline:

| Tier | Baseline | Post-T14 | Delta |
|------|---------:|---------:|------:|
| 7 (GSD compatibility) | 14/14 | 14/14 | 0 |
| 8 (autonomy under stress) | 24/25 (1 fail, Phase 6.5 deferred) | 24/25 | 0 |
| 9 (self-improving self-heal) | 20/20 | 20/20 | 0 |
| 10 (bootstrap autonomy) | 22/22 | 22/22 | 0 |
| 11 (portfolio autonomy) | 16/16 | 16/16 | 0 |
| 12 (cross-customer learning) | 24/24 | 24/24 | 0 |
| 13 (CEO Dashboard) | 30/30 | 30/30 | 0 |

**No regressions.** Tier 8's single failure is the pre-existing Phase 6.5 deferred item carried forward (out of scope per plan; flagged for 07-08).

## Real-vault md5 capture

Captured at suite start AND suite end on every Tier 14 run; assertions confirm `before == after`:

- `~/vaults/ark/observability/policy.db` md5: `12809f06d82716fba6f2930bbf98e173` (current value at session close — invariant is bit-identical-before-after, not a fixed value across sessions)
- `~/vaults/ark/ESCALATIONS.md`: ABSENT (real file does not exist; invariant treats both before/after as `"ABSENT"` sentinel → equal)
- `~/vaults/ark/lessons/universal-patterns.md`: present, hash captured per-run, invariant held
- `~/vaults/ark/bootstrap/anti-patterns.md`: ABSENT (sentinel)
- `~/Library/LaunchAgents/com.ark.continuous.plist`: ABSENT pre-suite AND post-suite (Tier 14 used `ARK_LAUNCHAGENTS_DIR=$mktemp_dir` exclusively)
- `~/Library/LaunchAgents/com.ark.weekly-digest.plist`: ABSENT (digest --install was not exercised in Tier 14; only --generate)

## Tier 8 deferred-item carry-forward

Tier 8 reports `24 passed / 1 failed`. This is unchanged from the Phase 6.5-close baseline (07-04 SUMMARY confirmed identical posture). Plan 07-07 explicitly out-of-scope per CONTEXT.md / 07-07-PLAN.md. **Carry forward to 07-08** for the documentation-close pass: investigate the single Tier 8 failure and either fix or document as a known-deferred item with an issue/lesson reference.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] LOCK_CONTENDED test created lock at the wrong path**

- **Found during:** First Tier 14 run
- **Issue:** Test pre-created `$VAULT/observability/.continuous.lock`, but `ark-continuous.sh` defines `LOCK_DIR="$VAULT_PATH/.continuous.lock"` (top of vault, not under observability/). The synthetic tick acquired the lock cleanly (no contention), no LOCK_CONTENDED row was logged, and the assertion failed.
- **Fix:** Changed pre-create path to `$T14_LOCK_VAULT/.continuous.lock` (canonical path).
- **Files modified:** `scripts/ark-verify.sh`
- **Re-ran:** Tier 14 → check 16 passes.

**2. [Rule 1 - Bug] read -p regression regex too permissive**

- **Found during:** First Tier 14 run
- **Issue:** Initial regex `^[[:space:]]*[^#]*read -p` matched lines where `read -p` appears inside string literals (e.g., `_ct_assert_eq "1" "0" "Test 14: no read -p in code"` and `echo "  ❌ Bonus 3: lib contains read -p invocation"`). 4 false positives in `ark-continuous.sh` + `inbox-parser.sh`.
- **Fix:** Tightened regex to `^[[:space:]]*read[[:space:]]+-p` — mirroring the existing in-script Test 14 hygiene check. This matches only when `read` is the leading command on a line (allowed leading whitespace), not when it appears inside double-quoted strings or after other tokens.
- **Files modified:** `scripts/ark-verify.sh`
- **Re-ran:** Tier 14 → check 19 passes (0 matches across 3 phase-7 scripts).

### Pre-existing issues observed but NOT fixed (out of scope per plan + scope-boundary rule)

- **Stray `read: -p: option requires an argument` warning** appears on stderr during Tier 7 and Tier 8 runs (and recursive Tier 13/14 sweeps that re-invoke them). Confirmed pre-existing via `git stash && bash scripts/ark-verify.sh --tier 7` — same noise without Tier 14 changes. Not a Tier 14 introduction. **Logged for 07-08 investigation** (likely an `eval` in run_check parsing a regex token boundary in a way bash interprets as a `read` builtin invocation; non-blocking — does not affect pass/fail counts).
- **Tier 8 24/25 (1 failure)** — Phase 6.5 carry-forward deferred item, explicit out-of-scope per plan.

## Output snapshot — Tier 14 final run

```
━━━ Tier 14: AOS Continuous Operation ━━━
  ✅ T14: Static: scripts/ark-continuous.sh exists + executable
  ✅ T14: Static: scripts/lib/inbox-parser.sh exists + sourceable
  ✅ T14: Static: scripts/ark-weekly-digest.sh exists + executable
  ✅ T14: Static: ark dispatcher has cmd_continuous + continuous arm
  ✅ T14: Static: bash -n on all 3 phase-7 scripts
  ✅ T14: Self-test: inbox-parser.sh ≥16/16 pass
  ✅ T14: Self-test: ark-continuous.sh ≥34/34 pass
  ✅ T14: Self-test: ark-weekly-digest.sh ≥11/11 pass
  ✅ T14: INBOX: 3 files moved to processed/2026-04-26/
  ✅ T14: INBOX: 0 files left in INBOX root
  ✅ T14: INBOX: 0 .failed and 0 .malformed siblings
  ✅ T14: INBOX: 3 INBOX_PROCESSED audit rows + ≥1 TICK_COMPLETE row
  ✅ T14: INBOX: no .tmp* atomic-move detritus
  ✅ T14: Safety: PAUSE present → PAUSE_ACTIVE row + INBOX untouched
  ✅ T14: Safety: daily cap=0 → DAILY_CAP_HIT row + INBOX untouched
  ✅ T14: Safety: lock held → LOCK_CONTENDED row
  ✅ T14: Plist: continuous plist written + plutil -lint OK + StartInterval + ark-continuous.sh ref
  ✅ T14: Weekly digest: file produced + ≥6 section headers + WEEKLY_DIGEST_WRITTEN row
  ✅ T14: Regression: no 'read -p' in continuous-path scripts
  ✅ T14: Subcommand: pause creates PAUSE file
  ✅ T14: Subcommand: resume removes PAUSE file
  ✅ T14: Subcommand: status returns 0 + mentions Last tick / no ticks yet
  ✅ T14: Invariant: real policy.db md5 unchanged
  ✅ T14: Invariant: real ESCALATIONS.md md5 unchanged
  ✅ T14: Invariant: real universal-patterns.md md5 unchanged
  ✅ T14: Invariant: real anti-patterns.md md5 unchanged
  ✅ T14: Invariant: real ~/Library/LaunchAgents/com.ark.continuous.plist unchanged
  ✅ T14: Invariant: real ~/Library/LaunchAgents/com.ark.weekly-digest.plist unchanged

  → Tier 7-13 regression sweep (informational):
    Tier 7: 14 passed / 0 failed
    Tier 8: 24 passed / 1 failed
    Tier 9: 20 passed / 0 failed
    Tier 10: 22 passed / 0 failed
    Tier 11: 16 passed / 0 failed
    Tier 12: 24 passed / 0 failed
    Tier 13: 30 passed / 0 failed

  Verification: ✅ APPROVED
  28 passed  0 warnings  0 failed  ⏭ 108 skipped
```

## Self-Check: PASSED

- ✅ `scripts/ark-verify.sh` modified — Tier 14 block (~250 lines) inserted between Tier 13 close and Generate-report. Verified by `grep -n "Tier 14: AOS Continuous Operation" scripts/ark-verify.sh`.
- ✅ `bash scripts/ark-verify.sh --tier 14` exits 0, reports `28 passed / 0 failed`.
- ✅ Tiers 7-13 invoked individually, all retain baseline counts (T7=14/14, T8=24/25-deferred, T9=20/20, T10=22/22, T11=16/16, T12=24/24, T13=30/30).
- ✅ `~/Library/LaunchAgents/com.ark.continuous.plist` ABSENT before AND after suite run (verified via `ls`).
- ✅ Real `~/vaults/ark/observability/policy.db` md5 captured before+after each Tier 14 invocation; assertions held (check #23).
- ✅ `/tmp/ark-tier14-*` directories cleaned up at end of Tier 14 (verified via `find /tmp -maxdepth 1 -name 'ark-tier14-*'` post-run).
- ✅ SUMMARY.md created at `.planning/phases/07-continuous-operation/07-07-SUMMARY.md`.
