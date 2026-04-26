# {{PROJECT_NAME}} — Repo Instruction

> Project-specific. Mutable status lives in `.planning/STATE.md`. Universal operating method lives in `~/.claude/CLAUDE.md`. Strategix structural standard lives in `~/vaults/StrategixMSPDocs/project-standard.md`.
>
> **Created:** {{CREATED_DATE}}
> **Type:** {{PROJECT_TYPE}}
> **Customer:** {{CUSTOMER}}

## Project

{{PROJECT_NAME}} — a `{{PROJECT_TYPE}}` platform for `{{CUSTOMER}}`.

## Purpose

[TODO: Define durable purpose — what problem does this solve, for whom, why now. One paragraph. No mutable facts.]

## Current Scope (Phase 1)

[TODO: List core features for Phase 1. Be specific. Name acceptance criteria. Live shipped state — counts, posture, feature closure — lives in `.planning/STATE.md`, not here.]

## Out of Scope

[TODO: Explicit boundaries. What is deferred to a later phase. What is never planned. Mention deferred features by name so they can't be claimed as "working".]

## Current Truth Sources

For "what is currently shipped, what counts, what's open":

1. `.planning/STATE.md` — primary implementation truth (table count, route count, test count, feature closure, control closure, deploy posture).
2. `.planning/ALPHA.md` — gate definition (when is this ready).
3. `.planning/REQUIREMENTS.md` — mandatory requirements with evidence.
4. `.planning/ROADMAP.md` — phase sequencing.
5. `tasks/todo.md` — active backlog.
6. `tasks/lessons.md` — captured corrections (rules, not descriptions).
7. The relevant code/config.

Vault docs (if any) are reference, not live truth. `STATE.md` wins.

## Workflow

Required reading before any non-trivial change. Read in order:

1. `~/.claude/CLAUDE.md` — universal operating method.
2. `~/vaults/StrategixMSPDocs/project-standard.md` — structural standard (only if this is a Strategix project).
3. This file.
4. `.planning/STATE.md` — live truth (highest authority for current shipped state).
5. `.planning/PROJECT.md` — durable purpose and scope.
6. `.planning/ROADMAP.md` — phase sequencing.
7. `.planning/ALPHA.md` — gate definition.
8. `.planning/REQUIREMENTS.md` — mandatory requirements with evidence.
9. `tasks/lessons.md` — captured corrections; required pre-read so past paid-for lessons don't regress.
10. `tasks/todo.md` — active backlog.
11. The relevant code/config.

Plan in `tasks/todo.md` before implementing. Capture every correction in `tasks/lessons.md` as a rule (not a description) before moving to the next task. Update `.planning/STATE.md` in the same change as any code change that affects shipped state.

Ark integration: `.parent-automation/ark-snapshot/` provides cached templates and lessons. Run `ark status` from inside the project for current state.

{{ADDENDUM}}

## Drift Rule

If anything in this file contradicts `.planning/STATE.md`, current config, or current code, this file is wrong and the contradiction is a defect. Fix this file or fix the code; do not leave them disagreeing.

{{CUSTOMER_FOOTER}}
