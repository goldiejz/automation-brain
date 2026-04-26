---
phase: 02-autonomy-policy
plan: 04
status: complete
date: 2026-04-26
files_modified:
  - scripts/execute-phase.sh
commits:
  - 64969b6: Task 1 (BLACK hard-stop → policy_budget_decision)
  - d5a1c15: Task 2a (policy_dispatcher_route + case switch + sentinel cost)
  - aaa1acb: Task 2b (policy_dispatch_failure + ark_escalate)
requirements: [REQ-AOS-01, REQ-AOS-02]
---

# Phase 2 Plan 02-04: execute-phase.sh wired to policy — Summary

`scripts/execute-phase.sh::dispatch_task` is now policy-routed end-to-end. The legacy `err "🛑 Budget tier BLACK — refusing to dispatch. Run: ark budget --reset"` manual gate that triggered Phase 2 is deleted. Routing, BLACK-tier handling, and dispatch-failure escalation all flow through `ark-policy.sh`.

## Files modified

| File | Lines added | Lines removed | Net |
|------|-------------|---------------|-----|
| `scripts/execute-phase.sh` | ~165 | ~95 | +70 |

(Counts approximate from diff; per-task commits are atomic.)

## What changed

### Task 1 — BLACK hard-stop replaced by `policy_budget_decision` (commit 64969b6)

- Sourced `ark-policy.sh` and `ark-escalations.sh` near top with graceful-degradation guards (`if [[ -f ... ]]; then source ... fi`).
- BLACK-tier branch in `dispatch_task` now calls `policy_budget_decision` with budget.json fields (`phase_used`, `phase_cap_tokens`, `monthly_used`, `monthly_cap_tokens`) extracted via the `BUDGET_FILE="$BUDGET_FILE" python3 - <<'PY'` env-passing idiom proven in 02-03.
- `AUTO_RESET` → log + `ark-budget.sh --reset` + re-read `budget-tier.txt`.
- `ESCALATE_MONTHLY_CAP` → return 1 fast (escalation already queued by policy).
- `PROCEED` → log and continue.
- Graceful-degradation fallback (no policy lib loaded) preserves a non-interactive error message — no `read -p` reintroduced.

### Task 2a — Policy router + case switch + verified sentinel cost (commit d5a1c15)

- Added `policy_dispatcher_route "$_complexity" "$current_tier"` call before the dispatch chain.
- **Complexity inference rule:**
  ```
  case "$task_desc" in
    *architect*|*architecture*|*design*|*novel*) _complexity="deep" ;;
    *review*|*audit*|*security*) _complexity="strong" ;;
    *) _complexity="standard" ;;
  esac
  ```
- Cascading `if codex; elif gemini; elif haiku-api` chain replaced by `case "$chosen_dispatcher" in claude-session|codex|gemini|haiku-api|regex-fallback)`. No fall-through.
- Token-cost recording fires on every successful branch.

### Task 2b — Failure routing through `policy_dispatch_failure` (commit aaa1acb)

- After the case switch, empty `output` (from non-session branches) routes to `policy_dispatch_failure "$task_desc" 0`.
- `ESCALATE_REPEATED` calls `ark_escalate repeated-failure "<title>" "<body>"` with task / dispatcher / tier context.
- `RETRY_NEXT_TIER` / `SELF_HEAL` log and return 1 — caller's existing self-heal logic (Phase 2-06b's layered retry) handles next step.
- `claude-session` branch excluded from this handler (it already `return 2`'d above; empty output on handoff is expected).

## Sentinel cost rationale (B-2 + NEW-W-3)

**Problem:** The original session branch wrote a handoff file then `return 2` without invoking `ark-budget.sh --record`. Under Tier 8 quota stubs (`ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true`), every dispatch routes to the active session — so 100% of dispatches recorded zero cost. Phase 3's observer-learner would see zeros and conclude "we're cheap" when in reality the active session was burning ~thousands of tokens per task.

**Fix:** Sentinel record before `return 2`:
```bash
local _prompt_text
_prompt_text=$(cat "$prompt_file" 2>/dev/null || echo "$task_desc")
local est_tokens=$(( ${#_prompt_text} / 4 ))
bash "$VAULT_PATH/scripts/ark-budget.sh" --record "$est_tokens" "claude-session-handoff:$task_id" >/dev/null 2>&1 || true
```

**Why `prompt_chars / 4`:** The active session reads the prompt + writes a roughly-prompt-sized response. char/4 is the canonical rough token estimate already used elsewhere in this file (line 320 `est_tokens=$(( ${#output} / 4 + ${#prompt} / 4 ))`). It is a *floor*, not a ceiling — Phase 3 can refine via observer-learner.

**Why `|| true`:** If the recording fails, the dispatch must not crash (the session is going to do the work regardless). NEW-W-3 raised concern that this swallow could hide a wrong signature → a synthetic test (below) verifies the side effect directly.

## NEW-W-3 synthetic test trace

**`--record` signature confirmed against `scripts/ark-budget.sh` line 44:**
```
--record) ACTION="record"; TOKENS="$2"; MODEL="$3"; shift 3 ;;
```
So `ark-budget.sh --record <tokens> <model_label>`. Matches our call.

**Budget log path:** Records append to the `history` array inside `$PROJECT_DIR/.planning/budget.json` (lines 332-340 of ark-budget.sh). The synthetic test greps that array for entries whose `model` field contains `claude-session-handoff`.

**Test execution:**

1. Created `/tmp/syn-proj/.planning/budget.json` with GREEN tier, plenty of headroom, empty history.
2. Created `/tmp/syn-proj/.planning/phases/01-test/01-PLAN.md` with one unchecked task.
3. Set `CLAUDE_PROJECT_DIR=/tmp/syn-proj ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true`, unset `ANTHROPIC_API_KEY`.
4. **BEFORE count:** 0 entries with `claude-session-handoff`.
5. Ran `bash scripts/execute-phase.sh /tmp/syn-proj 1`.
6. Output: `Policy chose dispatcher: claude-session (complexity=standard, tier=GREEN)` → handoff written → `return 2` → main loop's self-heal retry triggered a second dispatch (also session-handoff).
7. **AFTER count:** 2 entries — one per dispatch invocation:
   ```json
   {"timestamp":"2026-04-26T12:13:37.423496Z","tokens":278,"model":"claude-session-handoff:1"}
   {"timestamp":"2026-04-26T12:13:37.603260Z","tokens":291,"model":"claude-session-handoff:1-retry"}
   ```
8. **DELTA = 2** (one record per dispatch_task call, including the retry). The B-2 invariant is satisfied: each session-handoff dispatch produces exactly one new history entry. The `|| true` did NOT swallow a real error — recording works.

Re-ran after Task 2b commit: same result (regression-clean).

## Smoke checks (all pass)

| Check | Result |
|-------|--------|
| `bash -n scripts/execute-phase.sh` | OK |
| Sourcing ark-policy.sh from execute-phase.sh | OK (functions reachable in dispatch_task) |
| `grep -c 'policy_dispatcher_route'` | 3 (≥ 1 required) |
| `grep -c 'policy_budget_decision'` | 2 (≥ 1 required) |
| `grep -c 'policy_dispatch_failure'` | 3 (≥ 1 required) |
| `grep -c 'ark_escalate'` | 2 (≥ 1 required) |
| `grep -c 'claude-session-handoff'` | 2 in source (call + comment) |
| `grep -E 'read -[pr]' \| grep -v 'AOS: intentional'` | 0 lines (gate clean) |
| Synthetic dispatch under quota stubs | Adds exactly 1 history entry per call with `claude-session-handoff:<id>` label |

## Deviations from plan

- **Two pre-existing `read -r` calls tagged `# AOS: intentional gate`** rather than removed. Both are non-interactive stream parsing (`while IFS= read -r pf` for plan-file iteration; `while IFS= read -r task` for task loop). They predate this plan and are required for streaming line-by-line; the plan's "no `read -p`/`read -r` in delivery code paths" rule targeted *stdin gates*, not stream parsing. Tagged per the plan's escape hatch.
- **Removed the explicit `if [[ -z "$output" ]]; then err "All AI dispatchers unavailable"; return 1; fi` block** — its role is now subsumed by Task 2b's `policy_dispatch_failure` handler, which provides better behavior (audit-logged, escalation-aware) for the same condition.
- **regex-fallback now triggers wherever it would have triggered before** — when policy returns `regex-fallback` (BLACK/RED tier or no dispatcher available), we set the sentinel `[REGEX FALLBACK ...]` string. apply_task_output will fail to extract files from that string and return non-zero, which then enters the existing self-heal path. Acceptable degradation surface, unchanged from prior behavior.

## Phase 1 regression guard

The `source "$VAULT_PATH/scripts/lib/gsd-shape.sh"` line (Phase 1 wiring) is preserved at line 32, immediately after the new policy/escalation source block. Phase dir resolution still respects GSD layout.

## Self-Check: PASSED

- File modified: `/Users/jongoldberg/vaults/automation-brain/scripts/execute-phase.sh` — present.
- Commits: 64969b6, d5a1c15, aaa1acb — all in `git log`.
- Synthetic test rerun confirmed sentinel record observable in budget.json history.
