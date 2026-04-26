---
phase: 02-autonomy-policy
plan: 05
subsystem: delivery-autonomy
tags: [aos, policy, zero-tasks, audit-log]
requires: [02-01]
provides: [policy-routed-zero-task-handling]
affects: [scripts/ark-deliver.sh]
tech-stack:
  patterns:
    - graceful-degradation-source
    - policy-helper-indirection
key-files:
  modified:
    - scripts/ark-deliver.sh
decisions:
  - "Single helper `_deliver_handle_zero_tasks` replaces all three warn-and-return zero-task sites"
  - "`ark-policy.sh` and `ark-escalations.sh` sourced with graceful degradation (file-exists guard)"
  - "Helper sanitizes `plan_count` input to guarantee valid JSON in the audit log (pre-existing upstream `0\\n0` bug)"
  - "Existing `while IFS= read -r pf` loop tagged `# AOS: intentional gate` (loop iterator, not user-input)"
metrics:
  duration_seconds: 600
  completed: 2026-04-26
status: complete
---

# Phase 02 Plan 05: ark-deliver.sh wired to policy — Summary

`ark-deliver.sh` now delegates every zero-task decision to `policy_zero_tasks` via a single `_deliver_handle_zero_tasks` helper; the pipeline can no longer halt on a zero-task phase, and every decision is audit-logged at `observability/policy-decisions.jsonl`.

## What changed

### scripts/ark-deliver.sh

1. **Sourced policy + escalations libs near top (post `VAULT_PATH=...`):**
   ```bash
   if [[ -f "$VAULT_PATH/scripts/ark-policy.sh" ]]; then source "$VAULT_PATH/scripts/ark-policy.sh"; fi
   if [[ -f "$VAULT_PATH/scripts/ark-escalations.sh" ]]; then source "$VAULT_PATH/scripts/ark-escalations.sh"; fi
   ```
   Both are guarded — if the file is missing, the script still runs (graceful degradation). `ark-escalations.sh` does not yet exist; absence is non-fatal.

2. **Added helper `_deliver_handle_zero_tasks` just before `run_phase`:** routes through `policy_zero_tasks`, branches on `SKIP_LOGGED` vs `ESCALATE_AMBIGUOUS`, calls `ark_escalate` when available, and updates STATE.md. Always returns 0.

3. **Replaced three warn-and-return zero-task sites in `run_phase` with helper calls:**
   | # | Site                                                | New code                                                                    |
   | - | --------------------------------------------------- | --------------------------------------------------------------------------- |
   | 1 | Phase dir exists but no `*-PLAN.md` files (~L 239)  | `_deliver_handle_zero_tasks "$phase_num" "$phase_dir" 0 ; return 0`         |
   | 2 | `total_tasks -eq 0` across all plans (~L 265)       | `_deliver_handle_zero_tasks "$phase_num" "$phase_dir" "$plan_count" ; return 0` |
   | 3 | Legacy single `PLAN.md` `task_count -eq 0` (~L 275) | `_deliver_handle_zero_tasks "$phase_num" "$phase_dir" "${plan_count:-1}" ; return 0` |

4. **Tagged the loop iterator `while IFS= read -r pf`** with `# AOS: intentional gate` (it reads from a heredoc, not user input — the observer's `manual-gate-hit` pattern matches `read -[pr]` regardless of source, and this tag opts it out).

5. **Sanitized `_plan_count` input inside the helper.** Pre-existing upstream code yields `"0\n0"` for `plan_count` from `grep -c ... || echo 0` on bash 3. The helper extracts the first numeric line and re-formats with `printf '%d'` so the audit log JSON is always valid.

## Done criteria — verified

| Criterion                                                       | Result |
| --------------------------------------------------------------- | ------ |
| `bash -n scripts/ark-deliver.sh`                                | PASS   |
| `grep -E 'read -[pr]' ... \| grep -v 'AOS: intentional'` count  | 0      |
| `grep -c 'policy_zero_tasks' scripts/ark-deliver.sh`            | 3 (≥ 1) |
| `grep -c '_deliver_handle_zero_tasks' scripts/ark-deliver.sh`   | 4 (≥ 4) |
| `grep -c 'auto-skipping' scripts/ark-deliver.sh`                | 0      |
| `grep -c 'ark-policy.sh' scripts/ark-deliver.sh`                | 1      |

## Smoke test

Sourced `ark-deliver.sh --phase 99` against a temp project containing `.planning/phases/99-empty-phase/` (no plans):

- Helper invoked, `policy_zero_tasks` called.
- Audit log entry appended to `observability/policy-decisions.jsonl`:
  ```json
  {"ts":"2026-04-26T12:07:04Z","schema_version":1,"decision_id":"20260426T120704Z-2c14f83acb2dca56","class":"zero_tasks","decision":"SKIP_LOGGED","reason":"phase_has_no_actionable_tasks_plans=0","context":{"phase_dir":"/.../99-empty-phase","plan_count":0},"outcome":null,"correlation_id":null}
  ```
- Validated: parses as JSON, `class=zero_tasks`, `decision=SKIP_LOGGED`, `plan_count=0`.
- Pipeline did **not** halt — exit 0, STATE updated to `complete (no tasks)`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Sanitized `_plan_count` input inside helper**
- **Found during:** smoke test
- **Issue:** Pre-existing upstream code in `run_phase` produces `plan_count="0\n0"` because of `grep -c ... 2>/dev/null || echo 0` chains on bash 3. Without sanitization the audit JSON contained an embedded newline (`"plan_count":0\n0`) and was unparseable.
- **Fix:** Helper now sanitizes its third argument: take first line, strip non-digits, pass through `printf '%d'`. Audit log is now always valid JSON.
- **Scope:** narrow — only inside the new helper. The pre-existing upstream bug (warnings from `[[ $plan_count -eq 0 ]]`) is logged in `deferred-items.md` for follow-up; it doesn't break behavior because both branches of the chained `0\n0` still hit the zero path.

### Deferred (out of scope)

- Pre-existing `0\n0` `plan_count` issue at three integer comparisons in `run_phase` (lines ~154, ~237, ~262). Logged in `.planning/phases/02-autonomy-policy/deferred-items.md`.
- `ark-escalations.sh` does not yet exist; sourcing is guarded so missing-file is non-fatal. When that script is added in a later plan, `ESCALATE_AMBIGUOUS` will route through `ark_escalate` automatically.

## Self-Check: PASSED

- File `scripts/ark-deliver.sh` exists ✓
- `bash -n` passes ✓
- Audit log entry written and parses as JSON ✓
- All numeric grep gates above met ✓
