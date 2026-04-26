---
phase: 04-bootstrap-autonomy
plan: 01
subsystem: bootstrap-policy
tags: [bootstrap, inference, audit-log, customer-config, phase-4-wave-1]
requires: [scripts/ark-policy.sh, scripts/lib/policy-config.sh, scripts/lib/policy-db.sh]
provides:
  - bootstrap_classify (orchestrator → TSV verdict + _policy_log emission)
  - bootstrap_infer_type (keyword-overlap heuristic against project-types/*.md)
  - bootstrap_infer_stack (default_stack from template + policy override)
  - bootstrap_infer_deploy (type→target mapping + customer override)
  - bootstrap_infer_customer ("for <name>" parser → sanitized slug or scratch)
  - bootstrap_customer_dir / bootstrap_customer_resolve_policy / bootstrap_customer_init (STUB for 04-05)
affects: []
tech-stack:
  added: []
  patterns:
    - "Single-writer audit log via _policy_log (mirrors Phase 2/3 discipline; never inline INSERT)"
    - "Cascading config consumption via policy_config_get/has (env > project > vault > default)"
    - "Bash 3 sourced-library discipline (no top-level pipefail; tr-based lowercasing; no declare -A)"
    - "Isolated tmp-vault self-test (ARK_HOME + ARK_POLICY_DB redirected; never touches real DB)"
key-files:
  created:
    - scripts/bootstrap-policy.sh (558 lines — inference engine + 16-test self-test)
    - scripts/lib/bootstrap-customer.sh (94 lines — stub library; 04-05 extension points)
  modified: []
decisions:
  - "Mirror policy-config.sh's source-lib discipline: no set -euo pipefail at top level"
  - "Guard ark-policy.sh sourcing with `set --` save/restore so its self-test trigger doesn't fire when bootstrap-policy.sh is invoked with `test`"
  - "Confidence threshold honoured via policy_config_get bootstrap.confidence_threshold_pct (default 50) — overridable per project/vault/env"
  - "Customer slug sanitization: tr -cd 'a-z0-9' + 32-char truncation (deterministic, no surprises)"
  - "ESCALATIONS.md row format matches plan spec verbatim — markdown checkbox under `## Open` heading; created on first escalation"
metrics:
  duration: ~12 minutes
  tasks-completed: 2/2
  tests-passed: 16/16 (bootstrap-policy) + 4/4 (bootstrap-customer stub) + 10/10 (policy-config regression) + 15/15 (ark-policy regression)
  completed-date: 2026-04-26
---

# Phase 4 Plan 04-01: bootstrap-policy.sh — inference engine + customer stub Summary

One-liner: Sourceable Bash-3 inference library that converts a one-line project description into `(type, stack, deploy, customer, confidence_pct)` via keyword-overlap scoring against `bootstrap/project-types/*.md`, with single-writer `_policy_log` audit emission and `architectural-ambiguity` escalation when confidence < 50%.

## API Surface (consumed by 04-04)

```bash
# All emitted on stdout; side effect: exactly one _policy_log call per bootstrap_classify.
bootstrap_infer_type "<description>"          # -> "<type>\t<score_pct>"
bootstrap_infer_stack "<type>"                # -> default_stack (override-aware)
bootstrap_infer_deploy "<type>" [customer]    # -> deploy target
bootstrap_infer_customer "<description>"      # -> sanitized slug | "scratch"
bootstrap_classify "<description>" [customer_override]
  # -> stdout: "<type>\t<stack>\t<deploy>\t<customer>\t<confidence_pct>"
  # -> _policy_log "bootstrap" "CLASSIFY_CONFIDENT" ... when score >= threshold
  # -> _policy_log "escalation" "architectural-ambiguity" + ESCALATIONS.md row otherwise
  # -> return 0 (confident) | 1 (escalated)
```

## Stub library (04-05 extends)

`scripts/lib/bootstrap-customer.sh` ships with three functions marked `# STUB — extended in 04-05`:
- `bootstrap_customer_dir <customer>` — pure path echo, no mkdir.
- `bootstrap_customer_resolve_policy <customer> <key> [default]` — minimal awk YAML grep against `<customer-dir>/policy.yml`.
- `bootstrap_customer_init <customer>` — bare `mkdir -p`; 04-05 adds mkdir-lock semantics.

## Self-test results (isolated tmp vault)

```
🧪 bootstrap-policy.sh self-test
  ✅ infer_type returns service-desk
  ✅ infer_type score >= 50 (got: 66 >= 50)
  ✅ extracts 'acme' after 'for'
  ✅ no 'for' phrase yields 'scratch'
  ✅ service-desk default_stack
  ✅ service-desk → cloudflare-workers
  ✅ custom → none
  ✅ classify confident → returns 0
  ✅ classify TSV first field == service-desk
  ✅ classify TSV has 5 fields
  ✅ _policy_log emitted at least one 'bootstrap' row (baseline=0 now=1)
  ✅ classify low_confidence → returns non-zero (rc=1)
  ✅ escalation row written (baseline=0 now=1)
  ✅ ESCALATIONS.md row appended
  ✅ no Bash 4-only constructs in main code
  ✅ no real read -p invocation
✅ ALL BOOTSTRAP-POLICY TESTS PASSED (16/16)
```

ARK_POLICY_DB redirected to `$TMP_VAULT/observability/policy.db`; `~/vaults/ark/observability/policy.db` (real DB) is never touched.

## Regression checks

- `bash scripts/lib/policy-config.sh test` → 10/10 PASS
- `bash scripts/ark-policy.sh test` → 15/15 PASS
- `bash scripts/lib/bootstrap-customer.sh test` → 4/4 PASS

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 3 — Blocking] Guard against ark-policy.sh self-test trigger**
- **Found during:** Task 1 first self-test run.
- **Issue:** `scripts/ark-policy.sh` ends with `if [[ "${1:-}" == "test" ]]; then …`. When `bootstrap-policy.sh` is invoked with `bash bootstrap-policy.sh test`, sourcing ark-policy.sh inherits `$1="test"`, fires its self-test, and exits before our own self-test runs.
- **Fix:** Wrap the source call with `_BP_SAVED_ARGS=("$@"); set --; source "$_BP_DIR/ark-policy.sh"; set -- "${_BP_SAVED_ARGS[@]}"; unset _BP_SAVED_ARGS`. Restores positional args afterwards so our self-test still sees `$1="test"`.
- **Files modified:** `scripts/bootstrap-policy.sh`.
- **Documented in:** Source comment above the guard explains the rationale for future maintainers.

**2. [Rule 3 — Blocking] Test-10 self-reference (no real read -p)**
- **Found during:** Task 1 second self-test run.
- **Issue:** Plan spec says `grep -E 'read[[:space:]]+-p' "$0"` returns no match. The pattern itself appears inside the assertion, plus in echo strings — guaranteed match.
- **Fix:** Tightened pattern to `^[[:space:]]*read[[:space:]]+-p[[:space:]]` (real invocation only — `read -p` at the start of a statement, with a following space). Strings/comments/grep patterns are not at line start.
- **Files modified:** `scripts/bootstrap-policy.sh`.
- **Spirit of the rule preserved:** The lint still catches any actual `read -p` prompt, which is what the plan was protecting against.

### Intentional plan-text departures

- **SUMMARY filename:** Plan `<output>` block specifies `04-bootstrap-autonomy-01-SUMMARY.md`, but the orchestrator/user prompt and Phase 3 precedent use `04-01-SUMMARY.md`. Used the shorter form to match prior phase-summary naming.
- **Test count:** 16 assertions vs. plan's "10 tests" — the higher number is from splitting Test 7/8 into multiple sub-assertions (return code, TSV field, SQL row count, ESCALATIONS.md presence). All plan-required assertions covered.

## Audit-trail discipline check

- Bootstrap classifier sources `ark-policy.sh`; transitively gets `_policy_log`, `policy_config_get`, `policy_config_has`, `db_init`.
- All emissions go through `_policy_log` (single writer); zero inline `INSERT INTO decisions` statements in the new file (`grep -c 'INSERT INTO' scripts/bootstrap-policy.sh` → 0).
- Confident classifications log class=`bootstrap` decision=`CLASSIFY_CONFIDENT`.
- Escalations log class=`escalation` decision=`architectural-ambiguity` AND append to `ESCALATIONS.md` for human review.

## Acceptance criteria — verified

- [x] File at `scripts/bootstrap-policy.sh`, executable.
- [x] `bash scripts/bootstrap-policy.sh test` exits 0 with PASS line.
- [x] `grep -nE 'declare[[:space:]]+-A' scripts/bootstrap-policy.sh` → only matches a comment, no real `declare -A` use (Bash 3 compat preserved).
- [x] No real `read -p` invocation.
- [x] All 5 public functions defined and source-able.
- [x] Stub library: 3 functions defined; 3 `# STUB — extended in 04-05` markers.
- [x] Self-test creates isolated tmp vault; real DB md5 unchanged.

## Self-Check: PASSED

- FOUND: scripts/bootstrap-policy.sh
- FOUND: scripts/lib/bootstrap-customer.sh
- FOUND: .planning/phases/04-bootstrap-autonomy/04-01-SUMMARY.md
- Regression: policy-config.sh 10/10, ark-policy.sh 15/15 — no breakage.

## Forward links

- **04-02** will populate the `keywords:` and `default_stack` / `default_deploy` frontmatter in the real `bootstrap/project-types/*.md` templates that this engine scores against. Until 04-02 lands, the engine works against the test-only templates created in the self-test.
- **04-04** will source this lib from `scripts/ark-create.sh` and consume `bootstrap_classify`'s TSV verdict.
- **04-05** will replace the three `# STUB — extended in 04-05` functions in `bootstrap-customer.sh` with full mkdir-lock + cascading-config integration.
