---
phase: 04-bootstrap-autonomy
plan: 03
subsystem: bootstrap-templates
tags: [bootstrap, claude-md, templates, phase-4-wave-2]
requires: [scripts/ark-create.sh CLAUDE.md heredoc as source-of-truth]
provides:
  - bootstrap/claude-md-template.md (universal base with anchors)
  - bootstrap/claude-md-addendum/service-desk.md
  - bootstrap/claude-md-addendum/revops.md
  - bootstrap/claude-md-addendum/ops-intelligence.md
  - bootstrap/claude-md-addendum/custom.md
affects: [scripts/ark-create.sh — 04-04 will replace inline heredoc with sed-substitution pipeline]
tech-stack:
  added: []
  patterns:
    - "Anchor-on-own-line discipline so sed `r`+`d` can include addendum/footer files cleanly"
    - "Inline anchors ({{PROJECT_NAME}}, {{PROJECT_TYPE}}, {{CUSTOMER}}, {{CREATED_DATE}}) for simple s||g substitution"
    - "Addendum files start with `## Constraints` for visual continuity in assembled output"
    - "Universal sections in base only; type-specific sections in addendums only — no duplication"
key-files:
  created:
    - bootstrap/claude-md-template.md (65 lines — base template)
    - bootstrap/claude-md-addendum/service-desk.md (41 lines)
    - bootstrap/claude-md-addendum/revops.md (41 lines)
    - bootstrap/claude-md-addendum/ops-intelligence.md (40 lines)
    - bootstrap/claude-md-addendum/custom.md (13 lines)
  modified: []
decisions:
  - "Anchors that get file-included (ADDENDUM, CUSTOMER_FOOTER) appear exactly once, alone on a line, no surrounding text — required for sed `/anchor/r file` + `/anchor/d` pattern"
  - "Inline anchors may appear multiple times (e.g., {{PROJECT_NAME}} appears in title, in ## Project section); simple s||g handles that"
  - "Tone & section structure mirrored from ~/code/strategix-servicedesk/CLAUDE.md (the production reference) but stripped of project-specific content; addendums fill in type-specific sections"
  - "custom.md is intentionally minimal (TODO placeholders for Architecture Conventions and Anti-Patterns) — no opinions imposed on a project whose shape isn't yet clear"
  - "Universal Strategix invariants (RBAC central, currency suffix, audit columns, schema-first migrations) named in custom.md as defaults to inherit, not as imposed constraints"
metrics:
  duration: ~6 minutes
  tasks-completed: 2/2
  files-created: 5
  completed-date: 2026-04-26
---

# Phase 4 Plan 04-03: CLAUDE.md base template + project-type addendums Summary

One-liner: Externalised CLAUDE.md generation into a composable base template (`bootstrap/claude-md-template.md`) plus four per-project-type addendums (`bootstrap/claude-md-addendum/<type>.md`), wired for sed-substitution + file-include at scaffold time so 04-04 can swap base + type-specific sections + customer footer atomically.

## Files created

| File | Lines | Role |
|------|------:|------|
| `bootstrap/claude-md-template.md` | 65 | Universal base. Holds Project / Purpose / Current Scope / Out of Scope / Current Truth Sources / Workflow / Drift Rule. Two file-include anchors (`{{ADDENDUM}}`, `{{CUSTOMER_FOOTER}}`), four string anchors (`{{PROJECT_NAME}}`, `{{PROJECT_TYPE}}`, `{{CUSTOMER}}`, `{{CREATED_DATE}}`). |
| `bootstrap/claude-md-addendum/service-desk.md` | 41 | Constraints / Architecture Conventions / RBAC Structure / Anti-Patterns for service-desk. RBAC roles `customer \| staff \| manager \| admin`. Mentions `requireRole`, customer-portal/staff-API split, signature sign-off as evidential. |
| `bootstrap/claude-md-addendum/revops.md` | 41 | Same four sections, tuned for revops. Roles `customer \| sales \| manager \| admin`. Emphasises currency-suffix discipline as load-bearing, approval-workflow first-classness, commission rules in versioned config, no client-side margin gates as authority. |
| `bootstrap/claude-md-addendum/ops-intelligence.md` | 40 | Same four sections, tuned for ops-intel. Roles `viewer \| analyst \| manager \| admin`. Names cron-worker isolation (no upstream API calls from request path), KPI-snapshot read pattern, route/compute split, manual `wrangler d1 migrations apply` step. |
| `bootstrap/claude-md-addendum/custom.md` | 13 | Intentionally minimal. Names universal Strategix invariants as defaults to inherit; leaves Architecture Conventions and Anti-Patterns as explicit `[TODO]` placeholders with discipline (no pre-population of generic anti-patterns; capture them only after a real correction). |

## Acceptance criteria — verified

### Task 1 (base template)
- [x] File exists, 65 lines (≥ 50 required).
- [x] `{{ADDENDUM}}` appears exactly once, alone on a line.
- [x] `{{CUSTOMER_FOOTER}}` appears exactly once, alone on a line.
- [x] `{{PROJECT_NAME}}` (2 occurrences), `{{PROJECT_TYPE}}` (2), `{{CUSTOMER}}` (2), `{{CREATED_DATE}}` (1) — all ≥ 1.
- [x] No leftover bash variables (`grep -nE '\$[A-Z_]+'` → no matches).
- [x] Universal sections present: Project, Purpose, Current Scope (Phase 1), Out of Scope, Current Truth Sources, Workflow, Drift Rule.
- [x] Type-specific sections (Constraints, Architecture Conventions, RBAC, Anti-Patterns) NOT present in base.

### Task 2 (addendums)
- [x] `bootstrap/claude-md-addendum/` directory exists.
- [x] All 4 files present.
- [x] Each file's first non-blank line is `## Constraints`.
- [x] service-desk / revops / ops-intelligence ≥ 15 lines (40-41 each).
- [x] custom ≥ 8 lines (13).
- [x] No addendum contains universal sections (`## Project`, `## Purpose`, `## Workflow`, `## Drift Rule`, etc.) — verified via grep, all 0 hits.
- [x] service-desk.md mentions `requireRole` (5 occurrences).

## Smoke test (end-to-end sed pipeline)

```bash
cd /Users/jongoldberg/vaults/automation-brain
TMP=$(mktemp -d)
sed -e "s|{{PROJECT_NAME}}|test-project|g" \
    -e "s|{{PROJECT_TYPE}}|service-desk|g" \
    -e "s|{{CUSTOMER}}|acme|g" \
    -e "s|{{CREATED_DATE}}|2026-04-26|g" \
    -e "/{{ADDENDUM}}/r bootstrap/claude-md-addendum/service-desk.md" \
    -e "/{{ADDENDUM}}/d" \
    -e "/{{CUSTOMER_FOOTER}}/d" \
    bootstrap/claude-md-template.md > "$TMP/CLAUDE.md"
```

Result:
```
non-empty: OK
name substituted: OK
constraints present: OK
project section present: OK
no leftover anchors: OK
Assembled line count: 104
```

All assertions pass; the assembled CLAUDE.md is valid markdown with no leftover `{{` markers.

## Deviations from Plan

None of substance. The plan's acceptance criteria, file paths, anchor names, and section split were all hit verbatim. Three minor judgement calls worth noting:

1. **Created date in template:** Plan says "Add `Created: {{CREATED_DATE}}` line near top." Placed in the blockquote header alongside Type and Customer for visual coherence, rather than as a standalone bullet line. Anchor still substitutable; section still scannable.
2. **Title line uses `{{PROJECT_NAME}}` directly** (`# {{PROJECT_NAME}} — Repo Instruction`) — matches the existing inline heredoc's pattern and the production strategix-servicedesk CLAUDE.md.
3. **custom.md anti-patterns guidance:** Plan template has `[TODO: Capture anti-patterns as you encounter them in tasks/lessons.md]`. Expanded slightly to name the discipline ("mirror them out of `tasks/lessons.md` as durable rules once a correction has been seen twice") because pre-populating generic anti-patterns in custom-type was the failure mode the plan was guarding against — making the discipline explicit prevents drift.

## Forward links

- **04-04** sources these files via the sed pipeline documented in the plan's `<interfaces>` block. Anchor names are stable; do not rename without updating both the template and 04-04's substitution code.
- **04-05** generates the `{{CUSTOMER_FOOTER}}` content from each customer's `policy.yml` and writes it to a temp file before the final sed call. Until 04-05, the footer is just deleted (its anchor line removed), which yields a CLAUDE.md with no customer footer — graceful degradation.

## Self-Check: PASSED

- FOUND: bootstrap/claude-md-template.md (65 lines)
- FOUND: bootstrap/claude-md-addendum/service-desk.md (41 lines)
- FOUND: bootstrap/claude-md-addendum/revops.md (41 lines)
- FOUND: bootstrap/claude-md-addendum/ops-intelligence.md (40 lines)
- FOUND: bootstrap/claude-md-addendum/custom.md (13 lines)
- Smoke test: pass (assembled 104-line CLAUDE.md, no leftover anchors).
