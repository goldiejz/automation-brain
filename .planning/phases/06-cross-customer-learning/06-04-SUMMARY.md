---
phase: 06-cross-customer-learning
plan: 04
title: ark promote-lessons subcommand + post-phase hook in ark-deliver.sh
status: complete
requirements: [REQ-AOS-37]
files_created: []
files_modified:
  - scripts/ark
  - scripts/ark-deliver.sh
diff_size:
  scripts/ark: "+38 lines (subcommand arm + help-text line)"
  scripts/ark-deliver.sh: "+18 lines (post-phase hook block, after Phase 3 trigger)"
key_decisions:
  - "Use sourced-subshell invocation `( source lesson-promoter.sh && promoter_run --since X --apply )` instead of `bash lesson-promoter.sh --since X --apply`. Reason: lesson-promoter.sh's CLI dispatcher (lines 374-386) handles only ONE flag per invocation, so the literal multi-flag pattern in the plan would not have worked. Sourcing the script (which 06-02 explicitly verified as sourceable) and calling promoter_run directly gives us the full multi-flag function API. The subshell isolates env side-effects."
  - "Phase 6 hook placed AFTER the existing Phase 3 policy-learner trigger (between line 347 and the Step 7 record_decision call in run_phase). Both hooks share the non-fatal discipline (`|| log WARN`)."
  - "Default behaviour for `ark promote-lessons` (no args) is `--since 7-days-ago --apply`, matching the must_have truth. The post-phase hook in ark-deliver uses a tighter window (`--since 1-hour-ago`) mirroring the Phase 3 learner hook's window."
---

# Phase 6 Plan 06-04: ark promote-lessons + post-phase hook Summary

One-liner: Wired the lesson promoter into `ark promote-lessons` (manual surface) and `ark-deliver.sh::run_phase` (autonomous post-phase trigger) — both routes invoke `promoter_run` via sourced subshell to bypass the single-flag CLI dispatcher in 06-02's lesson-promoter.sh, with full multi-flag (`--since DATE --apply`) support and identical non-fatal discipline to the Phase 3 policy-learner hook.

## Patches delivered

### Patch A — `scripts/ark` (+38 lines)

1. New `promote-lessons)` arm in the main `case "$COMMAND" in` block, between `lessons)` and `learn)`. Mirrors the `learn)` arm structurally:
   - `ark promote-lessons` (no args) → `promoter_run --since <7-days-ago> --apply`
   - `ark promote-lessons --full` → `promoter_run --full --apply`
   - `ark promote-lessons --since DATE` → `promoter_run --since DATE --apply`
   - `ark promote-lessons --dry-run` → `promoter_run --dry-run` (no apply)
   - Unknown flag → usage error, exit 1
   - Missing `scripts/lesson-promoter.sh` → error with red-X, exit 1

2. One new help-text line under the **OBSERVABILITY** section of `cmd_help`:

```
    promote-lessons  Promote cross-customer lessons (--full | --since DATE | --dry-run; default: last 7 days)
```

### Patch B — `scripts/ark-deliver.sh` (+18 lines)

Single contiguous block inserted in `run_phase()`, immediately after the existing Phase 3 03-05 `policy-learner.sh` block and before the Step 7 `record_decision` call:

```bash
# === Phase 6 hook (Plan 06-04) — non-fatal cross-customer lesson promoter ===
# Mirrors Phase 3 03-05 discipline: observability, not delivery gate.
# Failure here MUST NOT abort phase completion.
if [[ -f "$VAULT_PATH/scripts/lesson-promoter.sh" ]]; then
  _lp_since=$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u +%Y-%m-%dT%H:%M:%SZ)
  _lp_log="$PROJECT_DIR/.planning/delivery-logs/lesson-promoter-phase-${phase_num}.log"
  mkdir -p "$(dirname "$_lp_log")" 2>/dev/null || true
  log INFO "Phase $phase_num: invoking lesson-promoter (non-fatal, --since $_lp_since)"
  ( source "$VAULT_PATH/scripts/lesson-promoter.sh" && promoter_run --since "$_lp_since" --apply ) \
    >>"$_lp_log" 2>&1 \
    || log WARN "lesson-promoter post-phase hook failed (non-fatal); see $_lp_log"
fi
# === END Phase 6 hook ===
```

## Deviation from plan (Rule 3 — blocking)

**Found during:** Drafting Patch A.
**Issue:** The plan's literal patch wrote `bash "$VAULT_PATH/scripts/lesson-promoter.sh" --full $_apply_flag` and `bash "$VAULT_PATH/scripts/lesson-promoter.sh" --since "$_lp_since" --apply`. But the lesson-promoter.sh CLI dispatcher (lines 374–386, owned by 06-02) handles only ONE positional flag per invocation — `--full`, `--since DATE`, `--apply`, or `--dry-run` are mutually exclusive at the CLI surface. Multi-flag invocation silently drops everything after the first match (the case arm calls `promoter_run --full` and immediately `exit 0`).
**Fix:** Use sourced-subshell invocation `( source "$VAULT_PATH/scripts/lesson-promoter.sh" && promoter_run --full --apply )`. The internal `promoter_run` function DOES accept all four flag combinations (its argument parser is the loop at lines 320–326). 06-02's SUMMARY explicitly verified the script is sourceable. The subshell isolates env mutations, and `set -uo pipefail` (no `set -e`) does not propagate.
**Why not modify lesson-promoter.sh:** Touching 06-02's file would (a) violate the plan's "minimal patches to two disjoint files" contract, (b) require re-running 06-02's 18-assertion self-test, (c) risk regressing the locked CLI surface. The sourcing pattern is purely additive in scope.

## Smoke test results

| # | Check                                                                    | Result |
|---|--------------------------------------------------------------------------|--------|
| 1 | `bash -n scripts/ark`                                                    | PASS   |
| 2 | `bash -n scripts/ark-deliver.sh`                                         | PASS   |
| 3 | `bash scripts/ark help \| grep -q 'promote-lessons'`                     | PASS   |
| 4 | `bash scripts/ark promote-lessons --dry-run` → exit 0                    | PASS   |
| 5 | Real-vault `~/vaults/ark/lessons/universal-patterns.md` md5 unchanged after dry-run | PASS (`7afcb1fc...` before == after) |
| 6 | `bash scripts/ark promote-lessons --bogus-flag` → exit 1, usage shown    | PASS   |
| 7 | `grep -c 'lesson-promoter.sh' scripts/ark-deliver.sh` (≥ 1 expected)     | PASS (3) |
| 8 | `grep -c 'promote-lessons' scripts/ark` (≥ 2 expected)                   | PASS (3) |
| 9 | No new `read -p` lines (delta vs HEAD)                                   | PASS (0 new) |
| 10| Phase 3 policy-learner trigger byte-for-byte preserved (`git diff` shows pure additions only) | PASS (`+38, +18, -0` per `git diff --stat`) |
| 11| Real dry-run output: 19 clusters classified, all MEDIOCRE_KEPT_PER_CUSTOMER, 0 PROMOTE, 0 DEPRECATED | PASS (matches 06-02-SUMMARY's empirical real-data observation) |

## Constraints honoured

- **Bash 3 compat:** No `declare -A`, `mapfile`, or `${var,,}`. BSD/GNU date dual fallback (`date -u -v-7d` || `date -u -d '7 days ago'` || `date -u`).
- **No `read -p` introduced:** Verified — count unchanged (delta vs HEAD = 0 new in either file).
- **Backward compat:** `ark deliver --phase N`, `ark deliver --resume`, `ark deliver --from-spec`, and the no-args portfolio routing are all untouched. The new hook fires only AFTER `update_state "$phase_num" "complete"`, so it cannot short-circuit any existing path.
- **Non-fatal discipline:** Both the absent-script branch (silently no-op via `[[ -f … ]]` guard) and the failed-promoter branch (`|| log WARN`) cannot return non-zero from `run_phase`. Phase 6 is observability, not a delivery gate.
- **Existing Phase 3 hook untouched:** `git diff` shows pure additions on `scripts/ark-deliver.sh` (`+18 lines`, 0 deletions).

## Confirmation

- REQ-AOS-37 (manual run via single command): satisfied — `ark promote-lessons [--full | --since DATE | --dry-run]` works.
- CONTEXT.md decision #5 (D-CADENCE — automatic post-phase trigger): satisfied — hook fires for every successful phase completion, mirroring Phase 3 03-05.
- All 6 must_have truths from the plan frontmatter satisfied.

## Verification commands

```bash
bash -n scripts/ark
bash -n scripts/ark-deliver.sh
bash scripts/ark help | grep promote-lessons
bash scripts/ark promote-lessons --dry-run
md5 -q $HOME/vaults/ark/lessons/universal-patterns.md   # 7afcb1fc... unchanged
git diff --stat scripts/ark scripts/ark-deliver.sh      # +38, +18, -0
```

## Self-Check: PASSED

- File modified: `scripts/ark` (+38 lines, subcommand arm at lines 275-313, help line at line 215)
- File modified: `scripts/ark-deliver.sh` (+18 lines, hook block after existing Phase 3 trigger)
- All 11 smoke-test assertions PASS
- No new `read -p` lines
- Existing Phase 3 hook byte-for-byte preserved (zero deletions in diff)
