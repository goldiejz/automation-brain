---
phase: 02-autonomy-policy
plan: 06b
type: execute
wave: 2
depends_on: [02-01, 02-02]
files_modified:
  - scripts/self-heal.sh
autonomous: true
requirements: [REQ-AOS-01, REQ-AOS-02]
must_haves:
  truths:
    - "self-heal.sh tracks retry_count per task in <phase_dir>/self-heal-retries-<task_id>.txt and reads it on entry"
    - "Retry 1 (count==0): enriched-prompt path — appends lessons.md tail + last error blob to the prompt before re-dispatching to the same dispatcher"
    - "Retry 2 (count==1): model-escalate path — calls policy_dispatcher_route to pick the NEXT-tier dispatcher (codex→gemini→haiku-api→claude-session) and re-dispatches with the original prompt"
    - "Retry 3 (count==2): escalate-to-queue path — invokes ark_escalate repeated-failure with the diagnosis blob; self-heal exits with code 2 (caller treats as escalated)"
    - "self-heal.sh has zero `read -[pr]` calls (no interactive prompts)"
    - "Backward compat: when invoked WITHOUT a task_id arg (legacy callers), self-heal still produces a proposal file as today; layered-retry path is opt-in via the new arg"
    - "All audit-log writes go through `_policy_log` from sourced ark-policy.sh — single writer, single schema (NEW-B-2 fix). No inline shorter-schema writer exists. Self-heal lines emit decision_id, outcome:null, correlation_id like every other class."
  artifacts:
    - path: "scripts/self-heal.sh"
      provides: "Layered self-heal: enriched → model-escalate → queue. Audit logging via _policy_log."
      contains: "self_heal_retry_layer"
  key_links:
    - from: "scripts/self-heal.sh"
      to: "scripts/ark-policy.sh"
      via: "source + policy_dispatcher_route on retry 2 + _policy_log for all class:self_heal lines"
      pattern: "_policy_log"
    - from: "scripts/self-heal.sh"
      to: "scripts/ark-escalations.sh"
      via: "ark_escalate repeated-failure on retry 3"
      pattern: "ark_escalate.*repeated-failure"
---

<objective>
Refactor `scripts/self-heal.sh` from a single-shot diagnosis-proposal generator into the **layered retry contract** locked in CONTEXT.md decision #4. This is the load-bearing self-heal mechanism that downstream scripts (execute-phase.sh, ark-team.sh via 02-06 Task 2) lean on for autonomous failure recovery.

Today self-heal.sh:
1. Reads error log
2. Cascades through codex → gemini → haiku-api for diagnosis
3. Writes a proposal markdown file (no actual retry)
4. Exits 0

After this plan, self-heal.sh ALSO supports the layered retry contract when invoked with a `<task_id> <prompt_file> <output_file>` triplet:

| Retry # | count_file value | Behavior |
|---------|-----------------|----------|
| 1       | 0 → 1           | Enriched prompt: append `lessons.md` tail + last error blob to prompt, re-dispatch same dispatcher |
| 2       | 1 → 2           | Model escalate: ask `policy_dispatcher_route` for next-tier dispatcher, re-dispatch with original prompt |
| 3       | 2 → 3           | Queue escalation: `ark_escalate repeated-failure`, exit 2 |

Purpose: this is the file 02-06 (`ark-team.sh`) and 02-04 (`execute-phase.sh`) would otherwise have to reimplement individually. Centralising it here means one contract, one audit-log surface, one place for Phase 3's observer-learner to read outcomes.

**NEW-B-2 fix:** The previous draft introduced an inline `_self_heal_log` helper that wrote a SHORTER schema (no decision_id, outcome, correlation_id) — incompatible with 02-01's locked schema_version=1 contract. Phase 3 reads the audit log expecting `decision_id` on every line (used as patch key); self-heal lines without it would be unpatchable. Fix: delete `_self_heal_log` entirely; route ALL class:self_heal writes through `_policy_log` exported from the already-sourced `ark-policy.sh`. Single writer, single schema enforcement.

Output: refactored `scripts/self-heal.sh` with both legacy mode (single-arg) and layered-retry mode (4-arg) preserved, and audit logging delegated to `_policy_log`.
</objective>

<execution_context>
- Bash 3 compatibility (macOS): no associative arrays
- Single-quoted heredocs MUST use the env-passing pattern (`VAR="$VAR" python3 - <<'PY'` + `os.environ['VAR']`)
- Read-before-edit; `bash -n` after every edit
- self-heal.sh is sourced from execute-phase.sh and ark-deliver.sh — must remain backward-compatible
- Disambiguation vs 02-06: ark-team.sh's `dispatch_role` retry loop is **per-role within a single ark-team invocation** (in-process counter). self-heal.sh's layered retry is **per-task across invocations** (file-backed counter).
</execution_context>

<context>
@/Users/jongoldberg/.claude/CLAUDE.md
@/Users/jongoldberg/vaults/automation-brain/.planning/STATE.md
@/Users/jongoldberg/vaults/automation-brain/.planning/phases/02-autonomy-policy/CONTEXT.md
@/Users/jongoldberg/vaults/automation-brain/.planning/phases/02-autonomy-policy/02-01-PLAN.md
@/Users/jongoldberg/vaults/automation-brain/.planning/phases/02-autonomy-policy/02-02-PLAN.md
@/Users/jongoldberg/vaults/automation-brain/scripts/self-heal.sh
@/Users/jongoldberg/vaults/automation-brain/scripts/ark-policy.sh

<interfaces>
Pre-state of `scripts/self-heal.sh` (162 lines, captured before this plan executes):

```bash
# Usage today: self-heal.sh <error_log_path> [context]
# - Reads error log (head -100, head -c 8000)
# - Builds a diagnosis prompt
# - Cascades dispatch: codex → gemini → haiku-api
# - Writes proposal to $VAULT_PATH/self-healing/proposed/heal-<ts>.md
# - Auto-applies if "Auto-Apply: YES" in diagnosis
# - Auto-commits to vault git
# - exit 0 (always, unless no AI available → exit 1)
```

Post-state contract (this plan):

```bash
# Mode A — legacy (single-arg or two-arg): UNCHANGED behavior
self-heal.sh <error_log_path> [context]

# Mode B — layered retry (NEW, 4-arg):
self-heal.sh --retry <task_id> <prompt_file> <output_file>
#   Effects:
#     - Reads/increments <phase_dir>/self-heal-retries-<task_id>.txt
#     - Picks layer (1=enriched, 2=model-escalate, 3=queue)
#     - On layer 1: appends lessons.md + last error blob to a temp prompt copy, dispatches via current dispatcher
#     - On layer 2: calls policy_dispatcher_route, dispatches via the returned next-tier dispatcher
#     - On layer 3: calls ark_escalate repeated-failure, exits 2
#   Phase dir: derived from $PROJECT_DIR/.planning/phases/<active>/ (best-effort: argv[3]'s parent if /phases/ in path; else $PROJECT_DIR/.planning/)
#   Exit codes:
#     0 = retry succeeded (output_file populated)
#     1 = retry attempted but dispatch failed (caller decides what to do; retry counter incremented)
#     2 = layer 3 escalation written; caller MUST stop retrying
```

ark-policy.sh exports (per 02-01):
- `policy_dispatcher_route <complexity> [tier]` → codex|gemini|haiku-api|claude-session|regex-fallback
- `_policy_log <class> <decision> <reason> [context_json] [correlation_id]` — single audit-log writer enforcing schema_version=1 (decision_id, outcome:null, correlation_id auto-emitted)

ark-escalations.sh exports (per 02-02):
- `ark_escalate <class> <title> <body>` — class for layer 3: `repeated-failure`
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Capture pre-state and add legacy/retry-mode dispatcher to self-heal.sh</name>
  <files>scripts/self-heal.sh</files>
  <read_first>
    - scripts/self-heal.sh (full — 162 lines, full content already captured in this plan's interfaces block)
    - scripts/ark-policy.sh (policy_dispatcher_route + _policy_log signatures)
    - scripts/ark-escalations.sh (ark_escalate signature; idempotency contract)
    - .planning/phases/02-autonomy-policy/CONTEXT.md (decision #4 — layered self-heal)
  </read_first>
  <action>
    Step 1. Capture pre-state by writing `.planning/phases/02-autonomy-policy/02-06b-PRESTATE.md` containing:
    - Full content of current self-heal.sh
    - Listing of every caller that invokes self-heal.sh (grep `-rn 'self-heal.sh' /Users/jongoldberg/vaults/automation-brain/scripts/`)
    - Note which call sites pass 1 arg, 2 args, or any other shape

    Step 2. At the top of self-heal.sh (after `set -uo pipefail`), source the policy + escalations libs (graceful):

    ```bash
    if [[ -f "$VAULT_PATH/scripts/ark-policy.sh" ]]; then
      # shellcheck disable=SC1091
      source "$VAULT_PATH/scripts/ark-policy.sh"
    fi
    if [[ -f "$VAULT_PATH/scripts/ark-escalations.sh" ]]; then
      # shellcheck disable=SC1091
      source "$VAULT_PATH/scripts/ark-escalations.sh"
    fi
    ```

    (Note: existing `VAULT_PATH=` line is at line 20 — source AFTER it.)

    Crucially, sourcing ark-policy.sh exposes `_policy_log` — that is the ONLY audit-log writer used by this script. NO inline `_self_heal_log` helper is defined.

    Step 3. Add a mode dispatcher near the top of the runtime section. Before the existing `ERROR_LOG="${1:?...}"` line, branch:

    ```bash
    # Mode B — layered retry (new path, opt-in via --retry sentinel)
    if [[ "${1:-}" == "--retry" ]]; then
      shift
      self_heal_retry_layer "$@"
      exit $?
    fi
    # Mode A — legacy (existing behavior continues unchanged below)
    ```

    Step 4. Define `self_heal_retry_layer()` ABOVE the mode dispatcher. Skeleton:

    ```bash
    self_heal_retry_layer() {
      local task_id="${1:?task_id required}"
      local prompt_file="${2:?prompt_file required}"
      local output_file="${3:?output_file required}"

      # Resolve phase_dir
      local phase_dir
      if [[ "$prompt_file" == */phases/* ]]; then
        phase_dir="${prompt_file%/*}"
      else
        phase_dir="${PROJECT_DIR:-$PWD}/.planning"
      fi
      mkdir -p "$phase_dir"

      local count_file="$phase_dir/self-heal-retries-${task_id}.txt"
      local retry_count
      retry_count=$(cat "$count_file" 2>/dev/null || echo 0)

      case "$retry_count" in
        0)  _self_heal_layer_enriched "$task_id" "$prompt_file" "$output_file" "$count_file" ;;
        1)  _self_heal_layer_escalate_model "$task_id" "$prompt_file" "$output_file" "$count_file" ;;
        *)  _self_heal_layer_escalate_queue "$task_id" "$prompt_file" "$output_file" "$count_file" ;;
      esac
    }
    ```

    Step 5. `bash -n` MUST pass; existing legacy mode MUST be untouched (run a smoke test invoking self-heal.sh with one arg pointing at a fixture error log; assert proposal file is still produced).

    Commit message: `refactor(self-heal): add mode dispatcher + retry-layer skeleton (layered self-heal contract)`.
  </action>
  <verify>
    <automated>bash -n /Users/jongoldberg/vaults/automation-brain/scripts/self-heal.sh && grep -c 'self_heal_retry_layer' /Users/jongoldberg/vaults/automation-brain/scripts/self-heal.sh | grep -qE '^[2-9]' && echo OK</automated>
  </verify>
  <done>
    - `bash -n` passes
    - PRESTATE.md exists with current self-heal.sh content + caller list
    - Mode dispatcher present (`--retry` sentinel branch)
    - `self_heal_retry_layer` declared (skeleton OK; layer impls in Task 2)
    - ark-policy.sh sourced (so `_policy_log` is in scope for Task 2)
    - NO `_self_heal_log` helper defined anywhere in self-heal.sh
    - Legacy mode (single-arg invocation) still produces a proposal file (smoke test)
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Implement the three retry layers (enriched, model-escalate, queue) — audit via _policy_log only</name>
  <files>scripts/self-heal.sh</files>
  <behavior>
    - `_self_heal_layer_enriched`: increments count_file (0 → 1); reads `~/vaults/ark/lessons.md` (tail -200) and the last error blob (best-effort: `${prompt_file%.md}.error.log` if it exists, else empty); writes `${prompt_file%.md}-enriched.md` with original prompt + ENRICHMENT block + ERROR block; dispatches via the *current* primary dispatcher (codex → gemini → haiku-api fallback); writes result to output_file; returns 0 if output non-empty, 1 otherwise
    - `_self_heal_layer_escalate_model`: increments count_file (1 → 2); calls `policy_dispatcher_route deep` (deep complexity to force escalation); dispatches via the chosen dispatcher with the ORIGINAL prompt_file (not the enriched one); writes result to output_file; returns 0 on success, 1 on failure
    - `_self_heal_layer_escalate_queue`: increments count_file (2 → 3); calls `ark_escalate repeated-failure "self-heal exhausted: $task_id" "$body"` where body includes task_id, retry_count, last error blob (head -50 lines); writes a sentinel `verdict: ESCALATED` line to output_file; returns 2
    - **All three layers write audit lines via `_policy_log` (the single writer from ark-policy.sh).** Call shape: `_policy_log self_heal "$DECISION" "$task_id" "{\"task_id\":\"$task_id\",\"layer\":<1|2|3>}"` where DECISION is `RETRY_1_ENRICHED` / `RETRY_2_MODEL_ESCALATE` / `RETRY_3_ESCALATE_QUEUE`. This guarantees every self_heal line includes decision_id, outcome:null, correlation_id (NEW-B-2 fix).
    - **NO `_self_heal_log` helper exists.** Inline JSON `printf` to policy-decisions.jsonl is FORBIDDEN — schema enforcement requires the central writer.
    - Zero `read -[pr]` calls; bash -n passes; legacy mode still works
  </behavior>
  <read_first>
    - scripts/self-heal.sh (after Task 1 changes — verify mode dispatcher in place, ark-policy.sh sourced)
    - scripts/ark-policy.sh (_policy_log signature: `_policy_log <class> <decision> <reason> [context_json] [correlation_id]`)
    - scripts/ark-escalations.sh (ark_escalate signature)
  </read_first>
  <action>
    Implement the three helpers above the `self_heal_retry_layer` dispatcher (so they're defined when called).

    **CRITICAL (NEW-B-2):** Audit-log writes use `_policy_log` from sourced ark-policy.sh. Do NOT define a helper named `_self_heal_log`. Do NOT inline a `printf '{"ts":...}' >> log_file` in this file. Single writer, single schema.

    Skeleton for layer 1 (enriched):

    ```bash
    _self_heal_layer_enriched() {
      local task_id="$1" prompt_file="$2" output_file="$3" count_file="$4"
      echo 1 > "$count_file"

      local lessons_blob="" error_blob="" enriched_prompt
      [[ -f "$VAULT_PATH/lessons.md" ]] && lessons_blob=$(tail -200 "$VAULT_PATH/lessons.md")
      [[ -f "${prompt_file%.md}.error.log" ]] && error_blob=$(cat "${prompt_file%.md}.error.log")

      enriched_prompt="${prompt_file%.md}-enriched.md"
      {
        cat "$prompt_file"
        echo ""
        echo "## RETRY 1 ENRICHMENT — lessons context"
        echo "$lessons_blob"
        echo ""
        echo "## RETRY 1 ENRICHMENT — last error"
        echo "$error_blob"
      } > "$enriched_prompt"

      # Dispatch via current primary (codex→gemini→haiku fallback)
      local out=""
      if command -v codex >/dev/null 2>&1; then
        out=$(codex exec - < "$enriched_prompt" 2>&1 || echo "")
      fi
      if [[ -z "$out" ]] && command -v gemini >/dev/null 2>&1; then
        out=$(gemini -p - < "$enriched_prompt" 2>&1 || echo "")
      fi
      # (haiku-api fallback elided here — copy from existing legacy block lines 80-99)

      # Audit via central _policy_log writer (NEW-B-2: single schema enforcement)
      local _ctx
      _ctx=$(printf '{"task_id":"%s","layer":1}' "$task_id")
      if [[ -n "$out" ]]; then
        echo "$out" > "$output_file"
        type _policy_log >/dev/null 2>&1 && _policy_log self_heal "RETRY_1_ENRICHED" "ok" "$_ctx" >/dev/null
        return 0
      fi
      type _policy_log >/dev/null 2>&1 && _policy_log self_heal "RETRY_1_ENRICHED" "empty_output" "$_ctx" >/dev/null
      return 1
    }
    ```

    Layer 2 (model-escalate): identical skeleton, but `chosen=$(policy_dispatcher_route deep)` and use original `prompt_file` (not enriched). Audit via `_policy_log self_heal "RETRY_2_MODEL_ESCALATE" "$reason" "$_ctx"` with layer=2 in context.

    Layer 3 (queue):

    ```bash
    _self_heal_layer_escalate_queue() {
      local task_id="$1" prompt_file="$2" output_file="$3" count_file="$4"
      echo 3 > "$count_file"

      local error_blob=""
      [[ -f "${prompt_file%.md}.error.log" ]] && error_blob=$(head -50 "${prompt_file%.md}.error.log")

      local body
      body=$(printf "Self-heal exhausted after 3 retries.\n\ntask_id: %s\nprompt_file: %s\nlast_error:\n%s" \
        "$task_id" "$prompt_file" "$error_blob")

      if type ark_escalate >/dev/null 2>&1; then
        ark_escalate repeated-failure "self-heal exhausted: $task_id" "$body" >/dev/null
      fi

      echo "verdict: ESCALATED" > "$output_file"
      echo "summary: self-heal exhausted ($task_id, 3 retries)" >> "$output_file"

      # Audit via central _policy_log writer (NEW-B-2: single schema enforcement)
      local _ctx
      _ctx=$(printf '{"task_id":"%s","layer":3}' "$task_id")
      type _policy_log >/dev/null 2>&1 && _policy_log self_heal "RETRY_3_ESCALATE_QUEUE" "queued" "$_ctx" >/dev/null

      return 2
    }
    ```

    **DO NOT** define any helper named `_self_heal_log`. **DO NOT** write inline `printf '{"ts":..."schema_version":1,...}' >> $log_file` from any helper in this file. The policy library is the only audit writer.

    Synthetic test (run inline at end of plan, NOT committed): create a fake task_id + prompt_file in /tmp, invoke `self-heal.sh --retry tid /tmp/p.md /tmp/o.md` three times in succession, assert:
    - count_file goes 0→1→2→3
    - on third call output_file contains `verdict: ESCALATED` AND ESCALATIONS.md gained one new ESC- entry of class repeated-failure
    - For all three calls, the lines added to policy-decisions.jsonl have `"class":"self_heal"` AND contain `decision_id` AND `outcome":null` AND `correlation_id` (verifies _policy_log was used, not an inline shorter-schema writer)
  </action>
  <verify>
    <automated>bash -n /Users/jongoldberg/vaults/automation-brain/scripts/self-heal.sh && layers=$(grep -c '_self_heal_layer_enriched\|_self_heal_layer_escalate_model\|_self_heal_layer_escalate_queue' /Users/jongoldberg/vaults/automation-brain/scripts/self-heal.sh); banned=$(grep -c '_self_heal_log\|"schema_version":1' /Users/jongoldberg/vaults/automation-brain/scripts/self-heal.sh); plog=$(grep -c '_policy_log self_heal' /Users/jongoldberg/vaults/automation-brain/scripts/self-heal.sh); [[ $layers -ge 3 && $banned -eq 0 && $plog -ge 3 ]] && echo OK</automated>
  </verify>
  <done>
    - `bash -n` passes
    - All three layer helpers defined; NO `_self_heal_log` helper exists
    - `grep -c '_self_heal_log' scripts/self-heal.sh` returns 0
    - `grep -c '"schema_version":1' scripts/self-heal.sh` returns 0 (no inline JSON; only ark-policy.sh emits that literal)
    - `grep -c '_policy_log self_heal' scripts/self-heal.sh` ≥ 3 (one per layer)
    - Synthetic 3-call test passes (count file progression + ESCALATIONS.md entry on call 3)
    - Legacy single-arg mode still produces proposal file (regression check)
    - `grep -cE 'read -[pr]' scripts/self-heal.sh` returns 0
    - Lines written by self-heal to policy-decisions.jsonl ALL contain `decision_id`, `outcome":null`, `correlation_id` (validate by parsing test-window lines as JSON)
  </done>
</task>

</tasks>

<verification>
- self-heal.sh implements layered retry contract per CONTEXT.md decision #4
- Layer 1 writes enriched-prompt file BEFORE re-dispatch (distinct from layer 2 which uses original prompt)
- Layer 3 writes ark_escalate(repeated-failure) and exits 2
- ALL audit-log writes go through `_policy_log` — single writer, single schema (NEW-B-2)
- No inline `_self_heal_log` helper anywhere
- Pre-state captured in 02-06b-PRESTATE.md for traceability
</verification>

<success_criteria>
- `self-heal.sh --retry <task_id> <prompt> <output>` is the canonical layered-retry entry point
- 02-04 (execute-phase.sh) and 02-06 (ark-team.sh — Task 2) can invoke this rather than reimplementing layered retry
- Phase 3's observer-learner has a clean `class: self_heal` audit-log surface to consume — every line patchable by decision_id
- Legacy proposal-file mode unchanged (no caller breakage)
</success_criteria>

<output>
`.planning/phases/02-autonomy-policy/02-06b-SUMMARY.md` recording:
- Pre-state hash + post-state diff summary
- Synthetic 3-call test trace
- ESCALATIONS.md entry produced on layer 3
- Legacy-mode regression test result
- Caller list (which scripts invoke self-heal.sh and which mode they use today)
- Confirmation that `_policy_log` is the single audit writer + sample line proving schema fields present
</output>
</content>
