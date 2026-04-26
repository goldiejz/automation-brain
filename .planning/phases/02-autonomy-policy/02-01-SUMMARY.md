# Plan 02-01 — AOS Policy Foundation: Summary

**Status:** COMPLETE
**Commits:** 2 (lib extraction; ark-policy refactor)
**Date:** 2026-04-26

## Exported function list

From `scripts/ark-policy.sh`:
- `policy_budget_decision <phase_used> <phase_cap> <monthly_used> <monthly_cap>` → `AUTO_RESET | PROCEED | ESCALATE_MONTHLY_CAP`
- `policy_dispatcher_route <complexity> [tier]` → `codex | gemini | haiku-api | claude-session | regex-fallback`
- `policy_zero_tasks <phase_dir> <plan_count>` → `SKIP_LOGGED | ESCALATE_AMBIGUOUS`
- `policy_dispatch_failure <error_ref> <retry_count>` → `RETRY_NEXT_TIER | SELF_HEAL | ESCALATE_REPEATED`
- `policy_load_config` → emits `KEY=VALUE` lines on stdout, exports `ARK_*` vars
- `policy_audit [n]` → tails last N audit log entries

From `scripts/lib/policy-config.sh`:
- `policy_config_get <key> <default>` → resolved value
- `policy_config_has <key>` → exit 0 if set, 1 if default would apply
- `policy_config_dump` → debug listing with source attribution

## Audit log schema (LOCKED at schema_version=1)

```json
{
  "ts": "2026-04-26T10:23:45Z",
  "schema_version": 1,
  "decision_id": "20260426T102345Z-a1b2c3d4e5f67890",
  "class": "budget",
  "decision": "PROCEED",
  "reason": "under_cap",
  "context": {"phase_used": 1000, "phase_cap": 50000},
  "outcome": null,
  "correlation_id": null
}
```

Field semantics:
- `ts` — ISO8601 UTC timestamp
- `schema_version` — locked at `1` for the lifetime of AOS
- `decision_id` — unique per log line. Format: `<YYYYMMDDTHHMMSSZ>-<16-hex>`. Generated via `head -c 8 /dev/urandom | od -An -tx8` (64-bit entropy, macOS-safe). Phase 3 patches `outcome` retroactively keyed on this ID.
- `class` — enum: `budget | dispatch | zero_tasks | dispatch_failure | escalation | self_heal`
- `decision` — UPPER_SNAKE_CASE return value of the decision function
- `reason` — machine-readable token pattern (no free text; greppable)
- `context` — JSON object with decision-specific data, or `null`
- `outcome` — always `null` on write. Phase 3's observer-learner sets to `"success" | "failure" | "ambiguous"`.
- `correlation_id` — `null` by default. Callers may pass a prior `decision_id` to link causally-related decisions.

## Config resolution order (highest wins)

1. **Env var** — canonical (`ARK_<UPPER_KEY>`) or legacy (`ARK_MONTHLY_ESCALATE_PCT`, `ARK_SELF_HEAL_MAX`, `ARK_FORCE_QUOTA_CODEX`, `ARK_FORCE_QUOTA_GEMINI`)
2. **Project** — `<PROJECT_DIR>/.planning/policy.yml`
3. **Vault** — `~/vaults/ark/policy.yml`
4. **Default** — passed by caller to `policy_config_get`

Keys consumed by `policy_load_config`:
- `budget.monthly_escalate_pct` (default 95)
- `budget.phase_cap_default` (default 50000)
- `budget.monthly_cap_default` (default 1000000)
- `self_heal.max_retries` (default 3)

## decision_id format & uniqueness guarantee

- Format: `<%Y%m%dT%H%M%SZ>-<16-hex-chars>` (e.g., `20260426T102345Z-a1b2c3d4e5f67890`)
- Entropy budget: 64 bits from `/dev/urandom`
- Birthday-collision probability over 1M IDs: ~2.7×10⁻⁸ (negligible)
- Phase 3 contract: every audit-log line has a unique decision_id usable as a patch key

### 100-call stress test trace (sample)

The self-test fires 100 consecutive `_policy_log` calls and asserts 100 distinct decision_ids:

```
_policy_log "stress" "TEST" "iter_0" "null"   → 20260426T102345Z-3f4a8b1c2d5e6f70
_policy_log "stress" "TEST" "iter_1" "null"   → 20260426T102345Z-7c2e9d4a8b3f5102
... (98 more, all distinct) ...
sort -u | wc -l == 100  ✅
```

## Test results

- `bash scripts/lib/policy-config.sh test` — **10/10 pass**
- `bash scripts/ark-policy.sh test` — **16/16 pass**
- 6 smoke checks (sourceability, set-e safety, decision_id schema, JSON validity) — **6/6 pass**

## Deviations from plan

- BLACK/RED tier check moved BEFORE the active-session check in `policy_dispatcher_route`. Rationale: Claude sessions also consume your weekly budget; "BLACK = no dispatch" must include sessions too. The original plan had session detection first, but logically BLACK means "no model spend at all, use cached patterns." Test was updated to reflect this — assertion now passes.
- Added `_policy_log "budget" "PROCEED"` audit entry on the PROCEED path (originally only logged on AUTO_RESET / ESCALATE). Rationale: Phase 3 needs to see all decisions, not just exceptional ones, to build outcome-correlation patterns.

Both deviations strengthen the AOS contract; neither breaks the locked schema.

## Wave 2 prerequisites met

Wave 2 plans (02-02..02-06b) can now:
- `source scripts/ark-policy.sh` and call any policy_* function without crashing
- Capture `decision_id` from `_policy_log` return for correlation chains
- Override config via env or `.planning/policy.yml` without code changes
- Trust the audit-log schema (Phase 3-ready) for any new audit writes
