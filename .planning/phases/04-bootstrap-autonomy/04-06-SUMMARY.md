---
phase: 04-bootstrap-autonomy
plan: 06
status: complete
date: 2026-04-26
requirements:
  - REQ-AOS-16
  - REQ-AOS-20
files_modified:
  - scripts/ark
---

# Plan 04-06 — `ark create` dispatcher: description-mode passthrough + help text refresh

**One-liner:** Extracted dispatcher's `create` branch into a `cmd_create()` function that pass-through-execs `ark-create.sh`, refreshed top-level help to document description-mode + flag-mode + the `ARK_CREATE_GITHUB` production-side-effect gate. No `read -p` introduced. Backward-compatible with all existing flag-mode invocations.

## Files modified

- `scripts/ark`
  - Added `cmd_create()` function (uses `exec bash $VAULT_PATH/scripts/ark-create.sh "$@"` — full transparent passthrough of positional + flag args).
  - Routed `create)` case branch through `cmd_create "$@"` instead of inline call (mirrors `cmd_sync`/`cmd_status`/`cmd_align` convention).
  - Updated `cmd_help` to document both invocation modes for `create` and document the `ARK_CREATE_GITHUB` env gate.

## Acceptance — all green

- `bash -n scripts/ark` clean.
- `cmd_create` function present (line 237).
- Dispatch case routes via `cmd_create "$@"` (line 262).
- `grep -E 'read[[:space:]]+-p' scripts/ark` returns 0 lines.
- `bash scripts/ark create --help` prints description-mode usage (delegates to ark-create.sh's already-updated help block from 04-04).
- `bash scripts/ark help` prints the new `ARK_CREATE_GITHUB` env doc line.

## Smoke test (Task 2 — isolated tmp vault, dispatcher path)

Ran the prescribed isolated smoke test against an `ARK_HOME=$TMP_VAULT` copy of the vault, with `ARK_CREATE_GITHUB` UNSET:

```
bash scripts/ark create "service desk for acme with sla and itil" \
  --customer acme --path "$TMP_PROJECTS"
```

Result: `EXIT=0`. Output included:
- `✅ CLAUDE.md assembled (service-desk addendum)`
- `✅ .planning/policy.yml generated (type=service-desk stack=vite-react-hono deploy=cloudflare-workers)`
- **`Skipping GitHub repo creation (set ARK_CREATE_GITHUB=true to enable).`** ← gate honored
- No `github.com` URL in output, no real repo created.

Assertions:
- `acme-sd/CLAUDE.md` exists (no leftover `{{...}}` anchors).
- `acme-sd/.planning/policy.yml` contains `bootstrap.project_type: service-desk`.
- Real `~/vaults/automation-brain/observability/policy.db` md5 unchanged before/after (isolation verified).

## Production safety

- `ARK_CREATE_GITHUB` left UNSET throughout — no GitHub side-effects.
- Smoke test ran in `mktemp -d` directories; cleaned up by `trap`.
- Real vault `policy.db` md5 unchanged.

## Deviations from plan

None. Executed exactly as written. The dispatcher's `create)` branch was already a passthrough to `ark-create.sh`; the plan's intent was to formalize it as a `cmd_create()` function and refresh help text, both done.

## Self-Check: PASSED

- File `scripts/ark` modified — verified via `grep -n cmd_create` (lines 237, 262).
- Smoke test exit 0 with `OK: dispatcher path passes`.
- Real `policy.db` md5 unchanged.
- No `read -p` anywhere in `scripts/ark`.
