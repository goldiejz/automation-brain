---
phase: 07-continuous-operation
plan: 02
subsystem: continuous-operation
tags: [daemon, tick-loop, mkdir-lock, daily-cap, inbox-lifecycle, bash3, sentinel-sections]
requires: ["07-01 (inbox-parser.sh)"]
provides:
  - "scripts/ark-continuous.sh — Phase 7 AOS daemon body"
  - "continuous_tick / continuous_process_inbox / continuous_check_daily_cap"
  - "continuous_acquire_lock / continuous_release_lock"
  - "continuous_record_failure / continuous_record_success (3-fail auto-pause)"
  - "continuous_self_test (34 assertions in mktemp-d isolation)"
  - "Sentinel section: health-monitor (Plan 07-03 fills in)"
  - "Sentinel section: subcommands (Plan 07-04 fills in)"
affects: ["07-03 (extends file at health-monitor sentinel)", "07-04 (extends file at subcommands sentinel)", "07-05 (ark dispatcher will call continuous_tick + subcommands)", "07-07 (Tier 14 verify against synthetic INBOX)"]
tech-stack:
  added: []
  patterns:
    - "mkdir-style lock with EXIT/INT/TERM trap discipline"
    - "PAUSE-then-lock-then-cap ordering (so PAUSE honored even with stale lock)"
    - "single-writer audit (every decision via _policy_log)"
    - "sentinel comment regions for parallel-wave file extension"
    - "graceful-degradation lib loads (script works even if a dep is missing)"
    - "3-strike auto-pause with idempotent escalation queueing"
    - "ARK_HOME-rooted paths + _continuous_refresh_paths for test isolation"
    - "monkey-patched policy_config_get inside self-test for cap=0 simulation"
key-files:
  created:
    - scripts/ark-continuous.sh
  modified: []
decisions:
  - "PAUSE check before lock acquisition: stale locks must not defeat the kill-switch (CONTEXT.md D-CONT-PAUSE)"
  - "mkdir-lock not flock: macOS doesn't ship flock; mkdir is atomic on every fs we care about (CONTEXT.md D-CONT-LOCK)"
  - "Daily cap reads class IN ('budget','dispatch','dispatcher') from policy.db (coarse-but-honest per D-CONT-DAILY-CAP — audit log is truth)"
  - "Fail counter persisted to disk (.continuous-fail-count): survives daemon restart, mirrors Phase 4 lifecycle pattern"
  - "ESCALATIONS routed only via ark_escalate (never direct file append): preserves single-writer + idempotent dedup"
  - "Trap on EXIT/INT/TERM (not just EXIT): cron-restart and Ctrl-C must release lock"
  - "Sentinel sections placed BEFORE the CLI guard so 07-03/07-04 can extend without breaking the guard"
  - "Self-test isolates ARK_HOME + ARK_POLICY_DB so real ~/vaults/ark/observability/policy.db md5 is invariant (Test 15 verified before+after)"
metrics:
  duration_minutes: 12
  completed: 2026-04-26
  tests_passed: 34
  tests_total: 34
  file_lines: 809
---

# Phase 7 Plan 07-02: ark-continuous.sh — Daemon Core Summary

Phase 7 daemon core implemented: `continuous_tick` orchestrates PAUSE → lock → cap → INBOX scan with full lifecycle (`processed/<date>/`, `.malformed`, `.failed`), 3-strike auto-pause, and 34/34 self-test assertions in mktemp-d isolation. Real-vault `policy.db` md5 unchanged before/after self-test.

## Files

- **Created:** `scripts/ark-continuous.sh` (809 lines, executable, sourceable lib + CLI guard)

## Function list

| Function | Returns | Purpose |
|----------|---------|---------|
| `continuous_acquire_lock` | 0 acquired / 1 contended | mkdir-style lock at `~/vaults/ark/.continuous.lock` |
| `continuous_release_lock` | 0 (idempotent) | rmdir lock |
| `continuous_check_daily_cap` | 0 PROCEED / 1 SUSPENDED | reads `continuous.daily_token_cap` (default 50000); SUMs `class IN ('budget','dispatch','dispatcher')` for today UTC from policy.db |
| `continuous_process_inbox <file>` | 0 success / 1 failure | parse → validate → dispatch (eval) → mv to `processed/<UTC-date>/` or rename `.failed`/`.malformed` |
| `continuous_record_failure` | 0 | bumps `.continuous-fail-count`; at 3 consecutive → touch PAUSE + audit + escalate |
| `continuous_record_success` | 0 | resets fail counter |
| `continuous_tick` | 0 | full orchestrator: PAUSE → lock → audit TICK_START → cap → scan INBOX → counters → audit TICK_COMPLETE → release |
| `continuous_self_test` | 0/1 | 34 assertions in mktemp-d isolation |

CLI: `ark-continuous.sh --self-test` runs the test suite; `ark-continuous.sh --tick` runs one tick (the launchd entrypoint, wired by Plan 07-04/07-05).

## Audit-class wiring matrix (D-CONT-AUDIT-CLASS)

| Decision | Wired in | Notes |
|----------|----------|-------|
| `TICK_START` | 07-02 (this) | Logged after lock acquired, before cap check |
| `TICK_COMPLETE` | 07-02 (this) | Final row each tick; reason = `p:N f:N m:N` |
| `INBOX_DISPATCH` | 07-02 (this) | Pre-eval, captures intent + customer + priority |
| `INBOX_PROCESSED` | 07-02 (this) | Post-eval success; file moved to `processed/<date>/` |
| `INBOX_FAILED` | 07-02 (this) | Dispatch exit ≠ 0; `.failed` rename + escalation |
| `INBOX_MALFORMED` | 07-02 (this) | Parse rc=2 OR unknown intent; `.malformed` rename |
| `LOCK_CONTENDED` | 07-02 (this) | Another tick holds lock |
| `PAUSE_ACTIVE` | 07-02 (this) | PAUSE file present; tick returns 0 immediately |
| `DAILY_CAP_HIT` | 07-02 (this) | `continuous_check_daily_cap` returned 1 |
| `AUTO_PAUSE_3_FAIL` | 07-02 (this) | 3 consecutive failure ticks → auto-PAUSE + escalate (idempotent) |
| `STUCK_PHASE_DETECTED` | **07-03** | Health-monitor extends sentinel section |
| `AUTO_PAUSED` (stuck-phase variant) | **07-03** | Plan 07-03 deferred |
| `WEEKLY_DIGEST_WRITTEN` | **07-06** | Separate `ark-weekly-digest.sh` script |

10 of 13 audit decisions wired here; remaining 3 are explicitly deferred to 07-03 / 07-06 per INDEX.md wave structure.

## Sentinel section line numbers (for downstream plans)

```
375:  # === SECTION: health-monitor (Plan 07-03) ===
380:  # === END SECTION: health-monitor ===
394:# === SECTION: subcommands (Plan 07-04) ===
402:# === END SECTION: subcommands ===
```

Plan 07-03 inserts the body of `continuous_health_monitor` between lines 375-380 (inside `continuous_tick`, after counter update, before TICK_COMPLETE — the hook is already wired, only the body call is needed).

Plan 07-04 inserts subcommand definitions (`continuous_install`, `continuous_uninstall`, `continuous_status`, `continuous_pause`, `continuous_resume`, `continuous_plist_emit`) between lines 394-402 (top-level functions, BEFORE the CLI guard so the guard stays the last block).

Both sentinels are open/close paired (greppable count = 2 each), and the file remains valid bash with empty bodies.

## Self-test result

```
RESULT: 34/34 pass
✅ ALL ARK-CONTINUOUS CORE TESTS PASSED
```

Tests cover (15 logical groups, 34 assertions):

1. Empty INBOX tick (5 asserts)
2. Valid resume file → processed/<date>/ (3 asserts)
3. Malformed file → .malformed (2 asserts)
4. Failing dispatch → .failed + ESCALATIONS.md (3 asserts)
5. PAUSE file → tick no-op (4 asserts)
6. Lock contention → LOCK_CONTENDED (2 asserts)
7. Daily cap exceeded (cap=0) → DAILY_CAP_HIT (2 asserts)
8. Daily cap under threshold → returns 0 (1 assert)
9. Mixed batch (good + malformed) (3 asserts)
10. Lock cleanup after every tick (1 assert)
11. 3-fail auto-pause + AUTO_PAUSE_3_FAIL row (2 asserts)
12. Success clears fail counter (1 assert)
13. Sentinel sections present (2 asserts)
14. Hygiene: no `read -p`, no bash 4 constructs (2 asserts)
15. Real-vault `policy.db` md5 invariant before/after (1 assert)

## Real-vault md5 invariant verification

```
md5 ~/vaults/ark/observability/policy.db
  before self-test: 8cee1b759ff78144da0cc4760995aa6e
  after  self-test: 8cee1b759ff78144da0cc4760995aa6e   ✅ unchanged
```

Self-test sets `ARK_HOME=$mktemp/vault` and `ARK_POLICY_DB=$mktemp/vault/observability/policy.db` so every `_policy_log` call lands in the isolated DB. Test 15 captures the real db md5 before isolation, then asserts the real db md5 is byte-identical after the suite — verified inline in the suite output.

## Constraints honored

- ✅ Bash 3 compat (no `declare -A`, no `mapfile`, no `${var,,}` in code; verified by Test 14a)
- ✅ Single-writer audit (every continuous-class decision via `_policy_log`; never raw INSERT)
- ✅ mkdir-lock not flock (D-CONT-LOCK)
- ✅ PAUSE-first ordering (D-CONT-PAUSE — checked before lock acquisition)
- ✅ Atomic `mv` for INBOX file lifecycle (D-CONT-LIFECYCLE)
- ✅ No `read -p` anywhere (verified by Test 14)
- ✅ Sourceable with zero stdout side effects
- ✅ ARK_CREATE_GITHUB unset (test-time invariant; daemon does not set it)
- ✅ ARK_AUTONOMOUS implicit (no interactive prompts; cron-driven)
- ✅ Sentinel sections greppable (2 open + 2 close, line-stable)

## Deviations from plan

None — plan executed as written. The plan called for "12+ assertions"; the implementation delivered 34 (15 logical groups, more sub-assertions per group for tighter coverage of file-rename + audit-row joints). Plan called for "Print '✅ ALL ARK-CONTINUOUS CORE TESTS PASSED' on success" — printed verbatim.

## Self-Check: PASSED

- [x] `scripts/ark-continuous.sh` exists, executable, 809 lines (verified `[ -f ... ]` + `wc -l`)
- [x] Self-test passes 34/34 (verified by direct run)
- [x] Sentinel `# === SECTION: health-monitor (Plan 07-03) ===` present (line 375)
- [x] Sentinel `# === SECTION: subcommands (Plan 07-04) ===` present (line 394)
- [x] No real `read -p` invocation (`grep -nE '^[[:space:]]*read[[:space:]]+-p'` → 0 matches)
- [x] No bash 4 constructs in code (only inside regex strings of self-test)
- [x] Sourceable produces zero output (verified by `bash -c 'source scripts/ark-continuous.sh'`)
- [x] Real-vault `policy.db` md5 unchanged: `8cee1b759ff78144da0cc4760995aa6e` before AND after self-test
