---
phase: 03-self-improving-self-heal
plan: 06
subsystem: ark-dispatcher
tags: [ark, dispatcher, learn, policy-learner, observability]
requirements: [REQ-AOS-13]
dependency-graph:
  requires: [03-02 (policy-learner.sh), 03-03 (lib helpers)]
  provides:
    - "ark learn — manual entry point for policy learning runs"
    - "Stable CLI used by Phase 7 cron"
  affects: [scripts/ark]
tech-stack:
  added: []
  patterns:
    - "Case-arm dispatch pattern (matches existing escalations/budget arms)"
    - "BSD + GNU date compatibility fallback chain"
    - "Graceful failure when downstream dependency (policy-learner.sh) absent"
key-files:
  created:
    - .planning/phases/03-self-improving-self-heal/03-06-SUMMARY.md
  modified:
    - scripts/ark
decisions:
  - "Default window = 7 days (last week); matches plan + Phase 7 cron expectation"
  - "Used non-`local` shell variable `_ark_since` because the case arm sits at script top-level, not inside a function (would error under `set -u`)"
  - "Added `--tag-first` flag (best-effort outcome-tagger pre-pass) per executor brief, in addition to plan's three modes"
  - "Graceful failure (exit 1, clear message) when scripts/policy-learner.sh missing — avoids crash when 03-02 not yet installed"
metrics:
  duration: ~5 minutes
  completed: 2026-04-26
---

# Phase 3 Plan 03-06: `ark learn` Subcommand Wiring — Summary

`ark learn` is now a first-class subcommand of the ark dispatcher with three plan-specified modes (default-windowed, `--full`, `--since DATE`) plus an executor-brief `--tag-first` mode, listed under OBSERVABILITY in `ark help`, and wired to fail gracefully when `scripts/policy-learner.sh` is not yet installed (Phase 3 still in flight).

## What was built

### Help-line addition (`cmd_help`, OBSERVABILITY group)

```
  OBSERVABILITY:
    insights    Show cross-project insights from Phase 6
    lessons     List all lessons in the ark
    learn       Run the policy-learner (--full | --since DATE; default: last 7 days)
    phase-6     Manually trigger Phase 6 observability daemon
```

### Case-arm shape (top-level dispatch)

```bash
learn)
  shift
  if [[ ! -f "$VAULT_PATH/scripts/policy-learner.sh" ]]; then
    echo -e "${RED}❌ scripts/policy-learner.sh not found — Phase 3 not yet installed${NC}" >&2
    exit 1
  fi
  case "${1:-}" in
    --full)        bash "$VAULT_PATH/scripts/policy-learner.sh" --full ;;
    --since)       shift
                   [[ -z "${1:-}" ]] && { echo "❌ --since requires an ISO8601 date" >&2; exit 1; }
                   bash "$VAULT_PATH/scripts/policy-learner.sh" --since "$1" ;;
    --tag-first)   [[ -f "$VAULT_PATH/scripts/lib/outcome-tagger.sh" ]] && \
                     bash "$VAULT_PATH/scripts/lib/outcome-tagger.sh" || true
                   _ark_since=$(date -u -v-7d ... || date -u -d '7 days ago' ... || date -u ...)
                   bash "$VAULT_PATH/scripts/policy-learner.sh" --since "$_ark_since" ;;
    "")            _ark_since=$(...)  # last 7 days, BSD/GNU compatible
                   bash "$VAULT_PATH/scripts/policy-learner.sh" --since "$_ark_since" ;;
    *)             echo "❌ Unknown flag: $1" >&2
                   echo "Usage: ark learn [--full | --since ISO8601 | --tag-first]" >&2
                   exit 1 ;;
  esac
  ;;
```

## Verification (smoke results)

All run from `/Users/jongoldberg/vaults/automation-brain`:

| Check | Result |
|-------|--------|
| `bash -n scripts/ark` | ✅ exit 0 (syntax valid) |
| `bash scripts/ark help \| grep "^[[:space:]]*learn[[:space:]]"` | ✅ matches |
| `bash scripts/ark learn` (no learner installed) | ✅ exit 1, clear message |
| `bash scripts/ark learn --bogus` | ✅ exit 1, "Unknown flag" |
| `bash scripts/ark learn --since` (no arg) | ✅ exit 1, "requires an ISO8601 date" |
| `bash scripts/ark learn` (with stub learner) | ✅ exit 0, stub called with `--since 2026-04-19T...Z` (7-days-ago window) |
| `bash scripts/ark learn --full` (with stub) | ✅ exit 0, stub called with `--full` |
| `bash scripts/ark learn --since 2026-01-01` (with stub) | ✅ exit 0, stub called with `--since 2026-01-01` |
| Existing subcommands (help, unknown command) | ✅ no regression |

## Behavior in absence of policy-learner.sh

When `scripts/policy-learner.sh` is missing (current state — Plan 03-02 not yet shipped), `ark learn` (any flag combination) emits:

```
❌ scripts/policy-learner.sh not found — Phase 3 not yet installed
```

…and exits 1. The dispatcher itself does not crash. Once 03-02 lands, the subcommand becomes operational with no further changes to scripts/ark.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Replaced `local _since` with regular variable**
- **Found during:** Task 1 implementation
- **Issue:** Plan specified `local _since` inside the case arm, but the arm sits at script top-level (not inside a function). `local` would error under `set -euo pipefail`.
- **Fix:** Used regular variable `_ark_since` (underscore-prefixed to avoid clashing with sourced scripts).
- **Files modified:** scripts/ark
- **Note:** The plan's <action> block called this out as a possibility ("If `local` errors here, replace with a regular assignment").

### Additions beyond plan

**2. [Executor brief] Added `--tag-first` flag**
- The executor brief (not the plan) requested `ark learn --tag-first` to run outcome-tagger before scoring.
- Implemented as best-effort: if `scripts/lib/outcome-tagger.sh` exists, runs it (errors tolerated via `|| true`); then dispatches the default 7-day window run.
- Plan's `must_haves.truths` did not enumerate this flag, but did not exclude it either — added because the brief is the more recent direction.

### Out-of-scope items not changed

- Did not modify `cmd_help` example block at the bottom (kept original three examples).
- Did not modify any other case arm.

## Auth gates encountered

None.

## Known Stubs

None. The case arm is fully wired; the only "stub-like" behavior is the graceful-failure path when `scripts/policy-learner.sh` is absent, which is intentional per the executor brief (Plan 03-02 ships the learner).

## Self-Check: PASSED

- ✅ scripts/ark modified (verified via `git status --short`)
- ✅ scripts/ark contains `^[[:space:]]+learn\)` case arm (1 occurrence)
- ✅ scripts/ark help lists learn under OBSERVABILITY
- ✅ bash -n scripts/ark exits 0
- ✅ All flag paths exercised against stubbed learner with expected outputs/exit codes
- ✅ Graceful failure verified when learner missing
