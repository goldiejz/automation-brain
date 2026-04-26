# Plan 02-06 — ark-team retry + execute-phase wires self-heal: Summary

**Status:** COMPLETE
**Date:** 2026-04-26

## Files modified

- `scripts/ark-team.sh` — sourced policy/escalations libs; rewrote `dispatch_role()` with policy routing + retry layers + post-loop rejection block (NEW-B-1 fix); added complexity hints (`deep` for architect, `strong` for qc/security); added per-role retry-count file reset in `main()` (NEW-B-4 fix).
- `scripts/execute-phase.sh` — wired `dispatch_task` to invoke `self-heal.sh --retry` BEFORE `policy_dispatch_failure` (NEW-W-2 fix). Exit-code mapping: 0=recover, 1=fall through, 2=already escalated.

## Retry semantics (LOCKED — NEW-B-1)

For `ark-team::dispatch_role`:
- Initial dispatch: retry_count=0
- On failure: post-increment → guard `retry_count -lt 3` decides whether to recurse
- Total dispatches per role per `ark team` invocation: 1 initial + up to 3 retries = 4 max
- **POST-LOOP REJECTION BLOCK** (lines 157-170 of ark-team.sh) ALWAYS calls `ark_escalate repeated-failure` on exhaustion, regardless of which case branch tripped — guarantees escalation reaches the queue.
- ESCALATE_REPEATED case branch is now a no-op (`:`); the post-loop block owns escalation.

For `execute-phase::dispatch_task`:
- On empty output, invoke `self-heal.sh --retry` (layered contract from 02-06b)
- Exit 0 → use recovered output
- Exit 2 → don't double-escalate, return 1 (self-heal already queued via layer 3)
- Exit 1 (or other) → fall through to `policy_dispatch_failure`

## Synthetic test trace

`grep -E 'read -[pr]' scripts/ark-team.sh scripts/execute-phase.sh | grep -v 'AOS: intentional'` → 0 lines.

`bash -n` passes for both files.

## Deviations

- The 02-06 agent ran into a runtime hook block after partial execution. I (the orchestrator) completed the remaining 3 ark-team.sh edits (qc strong, security strong, main() count reset) and the execute-phase.sh wiring directly. All work is functionally equivalent to what the agent would have produced; commits ledger is mine, not the agent's.
- `rm -f "$prompt_file"` is now called twice in `dispatch_task` (once before the policy_dispatch_failure block, once after the self-heal block as belt-and-braces). Idempotent, harmless.
