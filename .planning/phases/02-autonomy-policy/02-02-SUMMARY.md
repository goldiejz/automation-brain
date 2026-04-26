---
phase: 02-autonomy-policy
plan: 02
title: ESCALATIONS.md queue + `ark escalations` command
requirements: [REQ-AOS-03]
files_created:
  - scripts/ark-escalations.sh
  - .planning/phases/02-autonomy-policy/02-02-SUMMARY.md
files_modified:
  - scripts/ark
status: implemented
---

# Phase 2 Plan 02-02 — Summary

## Objective (delivered)

Async escalation queue write path. `ark_escalate <class> <title> <body>` appends a structured section to `~/vaults/ark/ESCALATIONS.md` and writes a single `class:escalation` audit-log line via `_policy_log`. User reviews the queue via `ark escalations`. Phase 2 is writer-only; consumption is Phase 7.

## Locked section-header format

```
^## (ESC-[0-9]{8}-[0-9]{6}-[a-z0-9]{6}) — (\S+) — (open|resolved)$
```

- ID: `ESC-YYYYMMDD-HHMMSS-<6char-rand>` — sortable, unique enough; entropy from `head -c 16 /dev/urandom | base64 | tr -dc 'a-z0-9' | cut -c1-6` (macOS-safe, Bash 3 compatible).
- Class is one of the 4 from CONTEXT.md: `monthly-budget | architectural-ambiguity | destructive-op | repeated-failure`. Unknown classes rejected with exit 1.
- Status flips `open` → `resolved` on `--resolve <id>`; resolution timestamp + optional note appended.

## Example ESCALATIONS.md (after one synthetic write)

```markdown
# Ark Escalations Queue

> Async queue of true blockers. User reviews on session start or `ark escalations`.
> Phase 2 writer-only. Phase 7 will consume responses from this file.

## ESC-20260426-120543-zx94u4 — monthly-budget — open
**Created:** 2026-04-26T12:05:43Z
**Class:** monthly-budget
**Title:** Monthly cap reached at 96% — need user decision

The October budget hit 96% of the $X cap. Auto-routing halted.

---

```

After `ark escalations --resolve ESC-20260426-120543-zx94u4 "Bumped cap"`:

```markdown
## ESC-20260426-120543-zx94u4 — monthly-budget — resolved
**Created:** 2026-04-26T12:05:43Z
**Class:** monthly-budget
**Title:** Monthly cap reached at 96% — need user decision

The October budget hit 96% of the $X cap. Auto-routing halted.
**Resolved:** 2026-04-26T12:08:11Z
**Resolution note:** Bumped cap

---
```

## Audit log integration (NEW-B-2)

Every escalation writes a single `_policy_log` entry — never a hand-rolled writer:

```
_policy_log "escalation" "QUEUED" "<class>" "{escalation_id, title}"
```

Schema is the W-6 schema (`schema_version=1`, `decision_id`, `outcome:null`, `correlation_id:null`). If `ark-policy.sh` is not sourced, audit-write is silently skipped (graceful degradation per CONTEXT constraint).

## Idempotency

Same `class + title` within 60s returns the existing escalation id without appending. Implemented inside `ark_escalate` with a Python heredoc (single-quoted, env-passed values via `os.environ` — Bash 3 + macOS safe).

## CLI surface (`ark escalations`)

| Args | Behavior |
|------|----------|
| _(no args)_ / `--list` | Tabular list of OPEN escalations newest-first. Exit 0 even when queue file absent. |
| `--all` | Same listing, includes resolved. |
| `--show <id>` | Prints full body of one escalation. Exit 1 if not found. |
| `--resolve <id> [note]` | Flips `open` → `resolved`, appends `**Resolved:** <ts>` and optional note. Exit 1 if already resolved or not found. |
| `--help` | Usage. |

CLI is non-interactive (no `read -p`).

## Dispatcher wiring

`scripts/ark` gained one case branch and one help entry:

```bash
escalations) shift; bash "$VAULT_PATH/scripts/ark-escalations.sh" "$@" ;;
```

Pattern mirrors `budget`/`secrets`/`lifecycle` — pure dispatch, no interactive logic, follows `$VAULT_PATH = $ARK_HOME` convention.

## Wave 2/3 callers (forward references)

| Plan | Calls `ark_escalate` with class | Trigger |
|------|--------------------------------|---------|
| 02-03 | `monthly-budget` | `policy_budget_decision` returns `ESCALATE_MONTHLY_CAP` (>=95% monthly use) |
| 02-06 | `repeated-failure` | Post-loop rejection block in `ark-team.sh` after 4-dispatch-fail (NEW-B-1) |

`destructive-op` and `architectural-ambiguity` classes are reserved for Phase 4+ wiring (bootstrap, portfolio).

## Verification

Round-trip test (run during Task 1) covered:

1. `ark_escalate monthly-budget "Test" "body"` → writes section, regex matches.
2. Invalid class `bogus-class` → rejected with exit 1.
3. Same `class + title` within 60s → same id returned (no append).
4. Different title → new id.
5. `--list` → tabular output, newest-first.
6. `--show <id>` → full section printed.
7. `--resolve <id> "Fixed by user"` → header flips to `resolved`, resolution metadata appended.
8. `--list` after resolve → resolved hidden.
9. `--all` → both shown.
10. `~/vaults/ark/observability/policy-decisions.jsonl` → 2 `class:escalation` lines (one per `ark_escalate` call) with full schema (decision_id, outcome:null, correlation_id:null).

Live `ark escalations --list` against the real vault returns `No escalations queue yet.` and exits 0 — confirming the file is created lazily on first `ark_escalate`, not at install/source/list time.

## Constraints honored

- ESCALATIONS.md created on first write, never preemptively.
- Bash 3 compat (no associative arrays, single-quoted heredocs for embedded Python with `os.environ` plumbing).
- Single audit-log writer (`_policy_log`) — no rolled-own helper. NEW-B-2 lesson respected.
- Non-interactive CLI; no `read -p`.

## Deviations

None. Plan executed as written.

## Notes for downstream plans

- The vault directory `~/vaults/ark/scripts/` is the same inode as `automation-brain/scripts/` (hard-linked). Edits in either path appear in both. This is why no separate `cp` step was needed for the dispatcher to find `ark-escalations.sh`.
- Idempotency window is 60 seconds (hard-coded). If 02-06 (`repeated-failure`) hits the rejection sentinel multiple times within 60s for the same task, only one queue entry will be written — by design.
