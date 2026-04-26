#!/usr/bin/env bash
# ark-policy.sh — Autonomous Operating System decision module
#
# All routine resource decisions route through here. Scripts call policy_*
# functions; the module decides without prompting the user. Decisions are
# audit-logged to observability/policy-decisions.jsonl.
#
# Escalation (user IS prompted) ONLY for these 4 classes:
#   1. Monthly budget exceeded (real cost ceiling)
#   2. Architectural ambiguity (multiple valid approaches, no policy preference)
#   3. Destructive ops (force-push, drop data, prod deploy)
#   4. Repeated self-heal failure (>=3 retries on same task)
#
# Every other "what should I do?" question is answered here, autonomously.
#
# Audit log schema (LOCKED at schema_version=1 — Phase 3 reads this):
#   {ts, schema_version, decision_id, class, decision, reason, context, outcome, correlation_id}
#
# decision_id format: <YYYYMMDDTHHMMSSZ>-<16-hex-chars>  (64-bit entropy from /dev/urandom)
# outcome:           always null on write; Phase 3's observer-learner patches via decision_id
# correlation_id:    null by default; callers pass a prior decision_id to chain related decisions

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
POLICY_LOG="$VAULT_PATH/observability/policy-decisions.jsonl"
mkdir -p "$(dirname "$POLICY_LOG")" 2>/dev/null

# === Source cascading config lib (graceful degradation if missing) ===
_POLICY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib"
# shellcheck disable=SC1091
if [[ -f "$_POLICY_LIB_DIR/policy-config.sh" ]]; then
  source "$_POLICY_LIB_DIR/policy-config.sh"
else
  # Stub: no cascading config available, just return the default
  policy_config_get() { echo "$2"; }
  policy_config_has() { return 1; }
  policy_config_dump() { echo "policy-config.sh not available"; }
fi

# === Load thresholds via cascading config (env > project > vault > defaults) ===
# Honors legacy env vars (ARK_MONTHLY_ESCALATE_PCT, ARK_SELF_HEAL_MAX) via the lib.
policy_load_config() {
  ARK_MONTHLY_ESCALATE_PCT=$(policy_config_get budget.monthly_escalate_pct 95)
  ARK_SELF_HEAL_MAX=$(policy_config_get self_heal.max_retries 3)
  ARK_PHASE_CAP_DEFAULT=$(policy_config_get budget.phase_cap_default 50000)
  ARK_MONTHLY_CAP_DEFAULT=$(policy_config_get budget.monthly_cap_default 1000000)
  export ARK_MONTHLY_ESCALATE_PCT ARK_SELF_HEAL_MAX ARK_PHASE_CAP_DEFAULT ARK_MONTHLY_CAP_DEFAULT
  echo "MONTHLY_ESCALATE_PCT=$ARK_MONTHLY_ESCALATE_PCT"
  echo "SELF_HEAL_MAX=$ARK_SELF_HEAL_MAX"
  echo "PHASE_CAP_DEFAULT=$ARK_PHASE_CAP_DEFAULT"
  echo "MONTHLY_CAP_DEFAULT=$ARK_MONTHLY_CAP_DEFAULT"
}

# Initialise on source so existing decision functions see the values.
policy_load_config >/dev/null

# === Audit log writer (W-6 schema, NEW-W-4 high-entropy decision_id) ===
# _policy_log <class> <decision> <reason> [context_json] [correlation_id]
# Echoes the generated decision_id on stdout so callers can capture it for chains.
_policy_log() {
  local class="$1"
  local decision="$2"
  local reason="$3"
  local context="${4:-null}"
  local correlation_id="${5:-null}"

  local ts ts_compact rand decision_id
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ts_compact="$(date -u +%Y%m%dT%H%M%SZ)"

  # NEW-W-4: 64-bit entropy from /dev/urandom (macOS-safe; no xxd, no openssl).
  # 8 bytes -> 16 hex chars via od -An -tx8.
  rand="$(head -c 8 /dev/urandom 2>/dev/null | od -An -tx8 | tr -d ' \n')"
  # Belt-and-braces fallback if /dev/urandom unavailable (extremely rare):
  if [[ -z "$rand" ]] || [[ "${#rand}" -ne 16 ]]; then
    rand=$(printf '%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM")
  fi
  decision_id="${ts_compact}-${rand}"

  # correlation_id: bare null literal vs quoted string
  local corr_field
  if [[ "$correlation_id" == "null" ]]; then
    corr_field="null"
  else
    corr_field="\"$correlation_id\""
  fi

  printf '{"ts":"%s","schema_version":1,"decision_id":"%s","class":"%s","decision":"%s","reason":"%s","context":%s,"outcome":null,"correlation_id":%s}\n' \
    "$ts" "$decision_id" "$class" "$decision" "$reason" "$context" "$corr_field" >> "$POLICY_LOG"

  echo "$decision_id"
}

# === Budget decision ===
# Args: phase_used phase_cap monthly_used monthly_cap
# Emits to stdout: AUTO_RESET | PROCEED | ESCALATE_MONTHLY_CAP
policy_budget_decision() {
  local phase_used="${1:-0}"
  local phase_cap="${2:-50000}"
  local monthly_used="${3:-0}"
  local monthly_cap="${4:-1000000}"

  # Monthly use percentage (integer math)
  local monthly_pct=0
  if [[ "$monthly_cap" -gt 0 ]]; then
    monthly_pct=$(( monthly_used * 100 / monthly_cap ))
  fi

  # Real cost ceiling — escalate
  if [[ "$monthly_pct" -ge "$ARK_MONTHLY_ESCALATE_PCT" ]]; then
    _policy_log "budget" "ESCALATE_MONTHLY_CAP" \
      "monthly_use_${monthly_pct}pct_>=_${ARK_MONTHLY_ESCALATE_PCT}pct" \
      "{\"phase_used\":$phase_used,\"phase_cap\":$phase_cap,\"monthly_used\":$monthly_used,\"monthly_cap\":$monthly_cap}" \
      >/dev/null
    echo "ESCALATE_MONTHLY_CAP"
    return 2
  fi

  # Phase cap exceeded but monthly headroom — auto-reset phase counter
  if [[ "$phase_used" -ge "$phase_cap" ]]; then
    _policy_log "budget" "AUTO_RESET" \
      "phase_cap_hit_monthly_headroom_${monthly_pct}pct" \
      "{\"phase_used\":$phase_used,\"phase_cap\":$phase_cap,\"monthly_used\":$monthly_used,\"monthly_cap\":$monthly_cap}" \
      >/dev/null
    echo "AUTO_RESET"
    return 0
  fi

  _policy_log "budget" "PROCEED" "under_cap" \
    "{\"phase_used\":$phase_used,\"phase_cap\":$phase_cap,\"monthly_used\":$monthly_used,\"monthly_cap\":$monthly_cap}" \
    >/dev/null
  echo "PROCEED"
  return 0
}

# === Dispatcher routing ===
# Args: task_complexity (lean|standard|strong|deep) [budget_tier]
# Honors env stubs: ARK_FORCE_QUOTA_CODEX, ARK_FORCE_QUOTA_GEMINI (used in tests)
# Emits: codex | gemini | haiku-api | claude-session | regex-fallback
policy_dispatcher_route() {
  local complexity="${1:-standard}"
  local tier="${2:-GREEN}"

  # BLACK/RED tier — no dispatch at all (sessions also consume weekly budget)
  if [[ "$tier" == "RED" || "$tier" == "BLACK" ]]; then
    _policy_log "dispatch" "regex-fallback" "tier_${tier}_no_dispatch" \
      "{\"complexity\":\"$complexity\",\"tier\":\"$tier\"}" >/dev/null
    echo "regex-fallback"
    return 0
  fi

  # Detect runtime context (active session > codex > gemini)
  local primary
  if [[ -x "$VAULT_PATH/scripts/ark-context.sh" ]]; then
    primary=$(bash "$VAULT_PATH/scripts/ark-context.sh" --primary 2>/dev/null || echo "regex-fallback")
  else
    primary="regex-fallback"
  fi

  # Active Claude session wins for non-BLACK tiers — most reliable dispatcher
  if [[ "$primary" == "claude-code-session" ]]; then
    _policy_log "dispatch" "claude-session" "active_session_detected" \
      "{\"complexity\":\"$complexity\",\"tier\":\"$tier\"}" >/dev/null
    echo "claude-session"
    return 0
  fi

  # External CLI availability — honor force-quota stubs for tests
  local codex_available=false
  local gemini_available=false
  if [[ "${ARK_FORCE_QUOTA_CODEX:-false}" != "true" ]] && command -v codex >/dev/null 2>&1; then
    codex_available=true
  fi
  if [[ "${ARK_FORCE_QUOTA_GEMINI:-false}" != "true" ]] && command -v gemini >/dev/null 2>&1; then
    gemini_available=true
  fi

  # Route by complexity preference, fall through to any available
  case "$complexity" in
    lean|standard)
      if $codex_available; then
        _policy_log "dispatch" "codex" "preferred_for_$complexity" "null" >/dev/null
        echo "codex"
        return 0
      fi
      if $gemini_available; then
        _policy_log "dispatch" "gemini" "codex_unavailable" "null" >/dev/null
        echo "gemini"
        return 0
      fi
      ;;
    strong|deep)
      if $gemini_available; then
        _policy_log "dispatch" "gemini" "preferred_for_$complexity" "null" >/dev/null
        echo "gemini"
        return 0
      fi
      if $codex_available; then
        _policy_log "dispatch" "codex" "gemini_unavailable" "null" >/dev/null
        echo "codex"
        return 0
      fi
      ;;
  esac

  # API fallback if key present
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    _policy_log "dispatch" "haiku-api" "all_clis_unavailable_api_key_present" "null" >/dev/null
    echo "haiku-api"
    return 0
  fi

  # Last resort — regex fallback (no dispatch, cached patterns only)
  _policy_log "dispatch" "regex-fallback" "no_dispatcher_available" "null" >/dev/null
  echo "regex-fallback"
  return 0
}

# === Zero-task phase decision ===
# Args: phase_dir plan_count
# Emits: SKIP_LOGGED | ESCALATE_AMBIGUOUS
policy_zero_tasks() {
  local phase_dir="$1"
  local plan_count="${2:-0}"

  _policy_log "zero_tasks" "SKIP_LOGGED" "phase_has_no_actionable_tasks_plans=$plan_count" \
    "{\"phase_dir\":\"$phase_dir\",\"plan_count\":$plan_count}" >/dev/null
  echo "SKIP_LOGGED"
  return 0
}

# === Dispatch failure decision ===
# Args: error_blob_or_path retry_count
# Emits: RETRY_NEXT_TIER | SELF_HEAL | ESCALATE_REPEATED
policy_dispatch_failure() {
  local error_ref="${1:-unknown}"
  local retry_count="${2:-0}"

  if [[ "$retry_count" -ge "$ARK_SELF_HEAL_MAX" ]]; then
    _policy_log "dispatch_failure" "ESCALATE_REPEATED" \
      "retries_${retry_count}_exhausted_max_${ARK_SELF_HEAL_MAX}" \
      "{\"error_ref\":\"$error_ref\"}" >/dev/null
    echo "ESCALATE_REPEATED"
    return 2
  fi

  if [[ "$retry_count" -eq 0 ]]; then
    _policy_log "dispatch_failure" "RETRY_NEXT_TIER" "first_failure_try_next_dispatcher" \
      "{\"error_ref\":\"$error_ref\"}" >/dev/null
    echo "RETRY_NEXT_TIER"
    return 0
  fi

  _policy_log "dispatch_failure" "SELF_HEAL" "retry_${retry_count}_attempt_self_heal" \
    "{\"error_ref\":\"$error_ref\"}" >/dev/null
  echo "SELF_HEAL"
  return 0
}

# === Audit helper (public): show recent decisions ===
policy_audit() {
  local n="${1:-20}"
  if [[ ! -f "$POLICY_LOG" ]]; then
    echo "No policy decisions logged yet."
    return
  fi
  tail -n "$n" "$POLICY_LOG"
}

# === Self-test (only runs when sourced with $1=test) ===
if [[ "${1:-}" == "test" ]]; then
  echo "🧪 ark-policy.sh self-test"
  echo ""

  # Isolated log so test doesn't pollute prod
  TEST_LOG="/tmp/ark-policy-test-$$.jsonl"
  POLICY_LOG="$TEST_LOG"
  : > "$TEST_LOG"

  pass=0
  fail=0

  assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  ✅ $label"
      pass=$((pass+1))
    else
      echo "  ❌ $label  (expected: $expected, got: $actual)"
      fail=$((fail+1))
    fi
  }

  assert_match() {
    local pattern="$1" actual="$2" label="$3"
    if echo "$actual" | grep -qE "$pattern"; then
      echo "  ✅ $label"
      pass=$((pass+1))
    else
      echo "  ❌ $label  (pattern: $pattern, got: $actual)"
      fail=$((fail+1))
    fi
  }

  echo "Budget decisions:"
  assert_eq "PROCEED"               "$(policy_budget_decision 1000 50000 10000 1000000)"   "under cap"
  assert_eq "AUTO_RESET"            "$(policy_budget_decision 60000 50000 60000 1000000)"  "phase cap hit, monthly OK"
  assert_eq "ESCALATE_MONTHLY_CAP"  "$(policy_budget_decision 60000 50000 960000 1000000)" "monthly >=95%"

  echo ""
  echo "Dispatcher routing:"
  assert_eq "regex-fallback" "$(ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true policy_dispatcher_route standard BLACK)" "BLACK tier → fallback"

  echo ""
  echo "Zero-task decision:"
  assert_eq "SKIP_LOGGED" "$(policy_zero_tasks /tmp/fake-phase 0)" "phase with no tasks → skip"

  echo ""
  echo "Dispatch failure:"
  assert_eq "RETRY_NEXT_TIER"     "$(policy_dispatch_failure /tmp/err 0)" "first failure"
  assert_eq "SELF_HEAL"           "$(policy_dispatch_failure /tmp/err 1)" "retry 1"
  assert_eq "ESCALATE_REPEATED"   "$(policy_dispatch_failure /tmp/err 3)" "retry 3 = exhausted"

  echo ""
  echo "Cascading config:"
  cfg_lines=$(policy_load_config | wc -l | tr -d ' ')
  assert_eq "4" "$cfg_lines" "policy_load_config emits 4 KEY=VALUE lines"
  override_val=$(ARK_MONTHLY_ESCALATE_PCT=80 policy_load_config | grep '^MONTHLY_ESCALATE_PCT' | cut -d= -f2)
  assert_eq "80" "$override_val" "ARK_MONTHLY_ESCALATE_PCT=80 override honored"

  echo ""
  echo "Audit log schema (W-6 + NEW-W-4):"
  last_line=$(tail -1 "$TEST_LOG")
  assert_match '"schema_version":1' "$last_line" "schema_version=1 present"
  assert_match '"decision_id":"[0-9]{8}T[0-9]{6}Z-[0-9a-f]{16}"' "$last_line" "decision_id matches ts-16hex format"
  assert_match '"outcome":null' "$last_line" "outcome:null present"
  assert_match '"correlation_id":null' "$last_line" "correlation_id:null present"

  # Validate every line is parseable JSON
  json_ok=$(python3 -c "
import json, sys
with open('$TEST_LOG') as f:
    for i, l in enumerate(f, 1):
        json.loads(l)
print('OK')
" 2>&1)
  assert_eq "OK" "$json_ok" "every audit line is valid JSON"

  echo ""
  echo "Decision-ID stress (NEW-W-4 — 100 calls → 100 distinct IDs):"
  # Capture 100 IDs (each _policy_log call echoes its decision_id)
  STRESS_LOG="/tmp/ark-policy-stress-$$.jsonl"
  POLICY_LOG="$STRESS_LOG"
  : > "$STRESS_LOG"
  ids=()
  i=0
  while [[ $i -lt 100 ]]; do
    id=$(_policy_log "stress" "TEST" "iter_$i" "null")
    ids+=("$id")
    i=$((i+1))
  done
  unique_count=$(printf '%s\n' "${ids[@]}" | sort -u | wc -l | tr -d ' ')
  assert_eq "100" "$unique_count" "100 _policy_log calls produced 100 distinct decision_ids"
  rm -f "$STRESS_LOG"
  POLICY_LOG="$TEST_LOG"

  echo ""
  echo "Audit log entries: $(wc -l < "$TEST_LOG" | tr -d ' ')"

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL POLICY TESTS PASSED ($pass/$pass)"
    rm -f "$TEST_LOG"
    exit 0
  else
    echo "❌ $fail/$((pass+fail)) tests failed"
    echo "Test log preserved at: $TEST_LOG"
    exit 1
  fi
fi
