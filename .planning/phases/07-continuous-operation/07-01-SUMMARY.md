---
phase: 07-continuous-operation
plan: 01
subsystem: continuous-operation
tags: [inbox-parser, dispatch-table, sourceable-lib, bash3, foundation]
requires: []
provides:
  - "scripts/lib/inbox-parser.sh — INBOX frontmatter parser + intent dispatcher"
  - "inbox_parse_frontmatter / inbox_validate_intent / inbox_dispatch_intent / inbox_self_test"
affects: ["07-02 daemon (sources this lib)"]
tech-stack:
  added: []
  patterns:
    - "sourceable-bash3-lib with state-machine awk frontmatter parser"
    - "printf %q for shell-safe arg quoting"
    - "trap RETURN for fixture cleanup"
    - "graceful-degradation lib pattern (mirrors policy-config.sh)"
key-files:
  created:
    - scripts/lib/inbox-parser.sh
  modified: []
decisions:
  - "awk state machine for frontmatter (vs sed): single-pass, handles delimiter detection + body extraction in one tool, matches policy-config.sh _pc_read_yaml_key pattern"
  - "printf %q for description quoting: ensures shell-eval safety for free-form text with $, backticks, quotes — daemon (07-02) can `eval` the dispatch string"
  - "RAW_KEY=value sentinel format from awk: avoids ambiguity when frontmatter values contain `=`; outer shell parses on first `=` only"
  - "Pure parser/dispatcher — no _policy_log calls: 07-02 owns all audit writes per CONTEXT.md D-CONT-AUDIT-CLASS"
  - "Defaults applied in parser (customer=scratch, priority=medium): per D-CONT-INBOX-FORMAT, prevents downstream null-handling"
metrics:
  duration_minutes: 8
  completed: 2026-04-26
  tests_passed: 31
  tests_total: 31
---

# Phase 7 Plan 07-01: INBOX Parser + Intent Dispatcher Summary

INBOX frontmatter parser and intent dispatcher implemented as a sourceable bash 3 library with 31/31 self-test assertions covering the full D-CONT-INBOX-FORMAT and D-CONT-INTENTS contracts.

## What was built

`scripts/lib/inbox-parser.sh` — a pure, sourceable library exposing four functions and a CLI guard for `--self-test` invocation. The library sources cleanly with zero side effects, contains no `read -p`, and uses no Bash 4-only constructs (no `declare -A`, no `mapfile`, no `${var,,}` in code).

## Function signatures

```bash
inbox_parse_frontmatter <file>
  # Echoes KEY=value lines for INTENT, CUSTOMER, PRIORITY, DESC
  # (and PROJECT/PHASE when present in frontmatter).
  # Defaults applied per D-CONT-INBOX-FORMAT: customer=scratch, priority=medium.
  # Returns 2 if no `---` delimiters found OR no `intent:` key (with reason on stderr).
  # Returns 0 on success.

inbox_validate_intent <intent>
  # Validates against {new-project, new-phase, resume, promote-lessons}
  # Returns 0 if valid, 1 if unknown/empty (with reason on stderr).

inbox_dispatch_intent <intent> <customer> <priority> <description> [extra]
  # Echoes the command-string the 07-02 daemon will eval:
  #   new-project     → ark create "<desc>" --customer "<cust>"   (printf %q quoted)
  #   new-phase       → ark deliver --phase <extra>
  #   resume          → ark deliver
  #   promote-lessons → ark promote-lessons
  # Returns 0 on known intent, 1 on unknown.

inbox_self_test
  # 31 assertions in mktemp -d fixture; trap RETURN cleans up.
  # Echoes "RESULT: N/total pass"; returns 0 only if all pass.
```

## Sample dispatch outputs (verified)

```
new-project     → ark create service\ desk\ for\ acme --customer acme-corp
new-phase       → ark deliver --phase 2
resume          → ark deliver
promote-lessons → ark promote-lessons
```

`printf %q` produces backslash-escaped output that round-trips safely through `eval` — the daemon (07-02) will use `eval "$dispatch"` to execute. Special characters in descriptions (quotes, `$`, backticks) are quoted correctly.

## Self-test result

```
RESULT: 31/31 pass
✅ ALL INBOX-PARSER TESTS PASSED
```

Coverage:
- 4 frontmatter-parsing tests (valid, missing intent, no FM, intent extraction)
- 2 intent-validation tests (unknown rejected; all 4 valid intents accepted)
- 4 dispatch-table tests (one per D-CONT-INTENTS row)
- 5 field-extraction tests (priority, project, phase, default customer, default priority)
- 4 whitespace/body-extraction tests (trimming, blank-line skipping, leading `# ` strip)
- 2 hygiene tests (zero-output sourcing, fixture lifecycle)
- 4 bonus tests (special-char quoting round-trip, customer pass-through, no `read -p`, bash 3 compat)

## Design decisions

**awk over sed for frontmatter parsing.** A single awk state-machine pass handles delimiter detection (`---` opening/closing), key:value splitting, comment skipping, body-line capture, and leading-`# ` strip. sed would have required multi-pass piping. Mirrors the pattern already used in `scripts/lib/policy-config.sh::_pc_read_yaml_key`.

**printf %q for description quoting.** The daemon (07-02) will `eval` the dispatch string, so the description must survive shell-tokenisation losslessly. `printf %q` produces `bash`-readable output that handles every shell metacharacter. Alternative (manual `\"`-wrapping) would break on embedded quotes/backticks/dollar-expansion.

**RAW_KEY=value sentinel from awk to shell.** Frontmatter values can legitimately contain `=`. Awk emits `RAW_INTENT=...`, `RAW_DESC=...` etc., and the shell parses on the first `=` only via parameter expansion (`${line%%=*}` / `${line#*=}`). This avoids splitting in the middle of a value.

**No `_policy_log` calls in this lib.** Per CONTEXT.md D-CONT-AUDIT-CLASS, all `continuous`-class audit entries flow through `_policy_log` from `ark-policy.sh`. 07-02 (daemon) owns those writes — `INBOX_PROCESSED`, `INBOX_FAILED`, `INBOX_MALFORMED`. The parser stays pure: no DB writes, no JSONL appends, no file mutations.

**Defaults applied in parser, not caller.** D-CONT-INBOX-FORMAT specifies `customer=scratch`, `priority=medium` when fields absent. Applying these in `inbox_parse_frontmatter` means downstream callers (07-02) never see empty values; simplifies dispatch logic.

**Bash 3 compat.** macOS ships bash 3.2. No `declare -A` (used named-string variables instead), no `mapfile` (used `while IFS= read` from heredoc), no `${var,,}` lowercase expansion (used `tolower()` inside awk). The self-test asserts these as static checks against the lib file.

## Constraints honored

- ✅ Sourceable lib with zero side effects on source (Test 15)
- ✅ No `read -p` anywhere in the lib (Bonus 3)
- ✅ Bash 3 compat verified (Bonus 4)
- ✅ Self-test runs in `mktemp -d` fixture; trap RETURN cleans up (Test 16)
- ✅ All 4 D-CONT-INTENTS dispatch correctly (Tests 6-9)
- ✅ Defaults per D-CONT-INBOX-FORMAT (Tests 11, 12)
- ✅ printf %q quoting handles special chars (Bonus 1)

## Deviations from plan

None — plan executed as written. All 16 plan-specified tests pass plus 15 additional sub-assertions (multi-key extraction, whitespace, hygiene, bonus quoting checks).

## Self-Check: PASSED

- [x] `scripts/lib/inbox-parser.sh` exists (verified: `[ -f ... ]` → FOUND)
- [x] Self-test passes 31/31 (verified by re-run)
- [x] No `read -p` in code (verified by grep)
- [x] No bash 4 constructs in code (verified by grep, comment-line matches only)
- [x] Sourcing produces zero output (verified inside self-test Test 15)
