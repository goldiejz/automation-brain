---
phase: 04-bootstrap-autonomy
plan: 02
subsystem: bootstrap-policy
tags: [bootstrap, inference, project-types, frontmatter, phase-4-wave-2]
requires:
  - bootstrap/project-types/service-desk-template.md (existing)
  - bootstrap/project-types/revops-template.md (existing)
  - bootstrap/project-types/ops-intelligence-template.md (existing)
  - scripts/bootstrap-policy.sh (Plan 04-01)
provides:
  - "default_stack / default_deploy / keywords frontmatter on all 4 project-type templates"
  - "bootstrap/project-types/custom-template.md (NEW catch-all)"
  - "Phrase-aware keyword tokenizer (multi-word phrases preserved end-to-end)"
  - "Absolute-match scoring (matched * 20, capped at 100) replacing percentage-of-total"
affects:
  - scripts/bootstrap-policy.sh (_bp_read_template_keywords + bootstrap_infer_type scoring)
tech-stack:
  added: []
  patterns:
    - "YAML frontmatter as single source of inference signal (no hard-coded keyword tables in code)"
    - "Newline-delimited phrase emission so multi-word keywords survive shell iteration"
    - "Absolute-match scoring rewards rich keyword sets without penalising them vs sparse ones"
key-files:
  created:
    - bootstrap/project-types/custom-template.md (22 lines — empty keywords; default_stack=custom; default_deploy=none)
    - .planning/phases/04-bootstrap-autonomy/04-02-SUMMARY.md
  modified:
    - bootstrap/project-types/service-desk-template.md (+3 frontmatter lines)
    - bootstrap/project-types/revops-template.md (+3 frontmatter lines)
    - bootstrap/project-types/ops-intelligence-template.md (+3 frontmatter lines)
    - scripts/bootstrap-policy.sh (phrase-aware reader + new scoring formula)
decisions:
  - "Keyword sets sized 18–21 phrases each (≥ 15 token plan floor) — captures synonyms and domain jargon (e.g., 'rev ops', 'helpdesk platform', 'n-central', 'halopsa')"
  - "Custom template ships with empty keywords intentionally — never wins on overlap; only resolves when user overrides --type custom or all other templates score 0"
  - "Replaced percentage-of-total scoring with absolute-match * 20 (cap 100). Rationale: percentage formula penalised the new richer 21-phrase sets relative to the sparse 5-phrase self-test fixture; absolute scoring rewards signal regardless of vocabulary size"
  - "Reader emits newline-delimited phrases so 'service desk' and 'rev ops' stay intact through the inference loop (previously word-split via `for kw in $kw_line`)"
metrics:
  duration: ~14 minutes
  tasks-completed: 2/2
  tests-passed: 16/16 (bootstrap-policy) + 4/4 (bootstrap-customer) + 10/10 (policy-config) + 15/15 (ark-policy) — all regressions clean
  completed-date: 2026-04-26
---

# Phase 4 Plan 04-02: project-type frontmatter Summary

One-liner: Tagged all four project-type templates with `default_stack`, `default_deploy`, and rich `keywords:` frontmatter; created the missing `custom-template.md` catch-all; fixed the inference engine's tokenizer + scoring so it can actually consume multi-word phrases without penalising rich keyword sets.

## Keyword sets shipped

| Type | Phrases | Sample |
|------|---------|--------|
| service-desk | 21 | `service desk, helpdesk, help desk, ticket, tickets, ticketing, sla, slas, itil, incident, incidents, problem management, change management, msp, managed service, customer support, technician, engineer workload, timesheet, sign-off, helpdesk platform` |
| revops | 24 | `revops, rev ops, revenue operations, crm, quotes, quoting, pipeline, opportunity, opportunities, deal, deals, commission, commissions, billing, invoicing, margin, approval, approvals, sales pipeline, account management, contract, contracts, renewal, renewals` |
| ops-intelligence | 18 | `ops intelligence, ops dashboard, msp dashboard, monitoring, monitoring dashboard, observability, n-central, halopsa, kpi, kpis, sla dashboard, technician workload, incident dashboard, client health, operations dashboard, executive dashboard, status board, network monitoring` |
| custom | 0 (intentional) | n/a — catch-all, never wins on overlap |

All four templates have `default_stack:` and `default_deploy:` set per the plan's `must_haves` artifacts contract.

## Type-confidence improvement (real-vault, post-04-02 vs Wave 1 baseline)

Wave 1 baseline: `bootstrap_infer_type` returned 0% for everything because no `keywords:` frontmatter existed → every classify escalated as `architectural-ambiguity`.

Post-04-02 (real `~/vaults/automation-brain/bootstrap/project-types/*.md`):

| Description | Verdict | Score | Plan threshold |
|-------------|---------|-------|----------------|
| `service desk for acme with itil sla` | service-desk | **60** | ≥ 50 ✓ |
| `revops crm pipeline for acme` | revops | **60** | ≥ 30 ✓ |
| `ops intelligence dashboard with halopsa` | ops-intelligence | **40** | ≥ 30 ✓ |
| `service desk for acme` | service-desk | 20 | escalates (correct — single phrase isn't enough signal) |
| `totally random nonsense xyz qwerty` | custom | 0 | escalates (correct — no match) |

Net effect: all three "obvious" descriptions in the plan's `<verification>` block now classify confidently (clear the threshold) rather than escalating.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 1 — Bug] `_bp_read_template_keywords` word-split multi-word phrases**

- **Found during:** First synthetic test against the real vault (post-frontmatter edits).
- **Issue:** The reader emitted a single space-separated string and the consumer iterated via `for kw in $kw_line`. Phrases like `service desk` or `rev ops` were word-split into single tokens. Plan-spec keyword sets contain many multi-word phrases (e.g., `engineer workload`, `n-central` is fine but `problem management`, `sales pipeline`, `monitoring dashboard` aren't), so half the signal was being thrown away.
- **Fix:** Reader now emits one phrase per line; `bootstrap_infer_type` iterates with `while IFS= read -r kw; ...; done <<< "$kw_line"`. Multi-word phrases survive end-to-end.
- **Files modified:** `scripts/bootstrap-policy.sh` (`_bp_read_template_keywords` + `bootstrap_infer_type` loop).

**2. [Rule 1 — Bug] Percentage-of-total scoring penalised richer keyword sets**

- **Found during:** Post-fix scoring vs plan's `≥ 50` acceptance criterion.
- **Issue:** Original formula was `score = matched * 100 / total`. With 21-phrase keyword sets and ~3 phrase matches in a typical short description, scores landed at 14–21 % — below the 50 % threshold despite obviously-correct classification. The 04-01 self-test fixture passed only because it had 5 keywords (3/5 = 60%). Plan instruction explicitly anticipated this: *"if frontmatter breaks inference, fix bootstrap-policy.sh to consume it"*.
- **Fix:** Scoring is now `matched * 20`, capped at 100. Five matches = full confidence. Rewards absolute signal over percentage-of-vocabulary.
- **Verification:** 04-01 self-test (16/16) still passes — its fixture had `service desk, ticket, sla, helpdesk, itil` = 5 phrases × ~3 hits = 60%, identical to before.
- **Files modified:** `scripts/bootstrap-policy.sh`.

### Intentional plan-text departures

- **`keywords:` count vs plan's ≥ 15 floor:** All four (well, three — custom is 0 by design) shipped with 18–24 phrases, exceeding the floor. No functional departure.
- **`completed:` date in custom-template.md:** Used `2026-04-26` per plan instruction (line 154 fragment), matches today.

## Files modified / created

```
M  bootstrap/project-types/service-desk-template.md     (+3 frontmatter lines)
M  bootstrap/project-types/revops-template.md           (+3 frontmatter lines)
M  bootstrap/project-types/ops-intelligence-template.md (+3 frontmatter lines)
A  bootstrap/project-types/custom-template.md           (22 lines, NEW)
M  scripts/bootstrap-policy.sh                          (reader + scoring fix)
```

`git diff --stat` confirms each existing template gained exactly 3 lines (frontmatter only). No body churn.

## Acceptance criteria — verified

- [x] Each of 3 existing templates has `default_stack:`, `default_deploy:`, `keywords:`, `project_type:` lines.
- [x] `keywords:` line for each contains ≥ 15 comma-separated tokens (21, 24, 18 respectively).
- [x] All other frontmatter fields preserved (`source_project`, `template_version`, `created`).
- [x] File body byte-identical for the three modified templates (only frontmatter section changed; verified via `git diff --stat`).
- [x] `custom-template.md` exists with empty `keywords:`, `default_stack: custom`, `default_deploy: none`.
- [x] `bootstrap_infer_type "service desk for acme with sla and itil"` → `service-desk\t60` (≥ 50).
- [x] `bootstrap_infer_type "revops crm pipeline for acme"` → `revops\t60` (≥ 30).
- [x] `bootstrap_infer_type "ops intelligence dashboard with halopsa"` → `ops-intelligence\t40` (≥ 30).
- [x] Random non-matching string → `custom\t0` with no crash.
- [x] All four downstream test suites still 100% green (bootstrap-policy 16/16, bootstrap-customer 4/4, policy-config 10/10, ark-policy 15/15).

## Self-Check: PASSED

- FOUND: bootstrap/project-types/service-desk-template.md (new frontmatter present)
- FOUND: bootstrap/project-types/revops-template.md (new frontmatter present)
- FOUND: bootstrap/project-types/ops-intelligence-template.md (new frontmatter present)
- FOUND: bootstrap/project-types/custom-template.md (NEW)
- FOUND: scripts/bootstrap-policy.sh (reader + scoring updated)
- FOUND: .planning/phases/04-bootstrap-autonomy/04-02-SUMMARY.md (this file)
- Regressions: 16/16 + 10/10 + 15/15 + 4/4 PASS

## Forward links

- **04-04** consumes `bootstrap_classify`'s TSV verdict from `scripts/ark-create.sh`. Now that the engine produces real (non-zero) scores against the real vault, 04-04 will hit the confident path for typical project-type descriptions instead of every invocation escalating.
- **04-05** integrates customer-policy override of `default_stack` / `default_deploy`; no schema changes needed in the templates themselves.
