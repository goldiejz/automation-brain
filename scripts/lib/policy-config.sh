#!/usr/bin/env bash
# policy-config.sh — Cascading policy configuration resolver for AOS
#
# Sourced by scripts/ark-policy.sh. Resolves policy values with this precedence
# (highest wins):
#
#   1. Env var (ARK_<UPPER_KEY>)
#   2. <project>/.planning/policy.yml      (if PROJECT_DIR is set + file exists)
#   3. ~/vaults/ark/policy.yml             (if exists)
#   4. Built-in default passed by caller
#
# Phase 2 / AOS — used by ark-policy.sh decision functions to honor per-project
# and per-user overrides without code changes.
#
# Usage (from a sourced lib, NOT a caller script):
#   policy_config_get budget.monthly_escalate_pct 95
#   policy_config_has self_heal.max_retries
#   policy_config_dump
#
# YAML parsing is intentionally minimal — `key: value` pairs only (with dotted
# keys like `budget.monthly_escalate_pct`). No nesting, no PyYAML dependency.
# Comments (#) and blank lines are ignored.
#
# Bash 3 compatible (macOS default). No associative arrays, no BASH_REMATCH
# captures, parameter expansion only.
#
# IMPORTANT: This is a sourced library. It must NOT set -euo pipefail at top
# level — that would propagate to and break callers.

# === Convert dotted key to env-var name ===
# budget.monthly_escalate_pct → ARK_BUDGET_MONTHLY_ESCALATE_PCT
_pc_key_to_env() {
  local key="$1"
  local upper
  upper=$(echo "$key" | tr 'a-z.' 'A-Z_')
  echo "ARK_${upper}"
}

# === Legacy env-var compatibility shim ===
# Pre-Phase-2 scripts already use specific env vars. Map them to canonical keys
# so legacy callers continue to work without modification.
_pc_legacy_env() {
  local key="$1"
  case "$key" in
    budget.monthly_escalate_pct)  echo "ARK_MONTHLY_ESCALATE_PCT" ;;
    self_heal.max_retries)        echo "ARK_SELF_HEAL_MAX" ;;
    dispatch.force_quota_codex)   echo "ARK_FORCE_QUOTA_CODEX" ;;
    dispatch.force_quota_gemini)  echo "ARK_FORCE_QUOTA_GEMINI" ;;
    *)                            echo "" ;;
  esac
}

# === Read a key from a YAML-ish file ===
# $1=file, $2=key (dotted). Echoes value or empty.
_pc_read_yaml_key() {
  local file="$1"
  local key="$2"
  [[ ! -f "$file" ]] && return 1

  # Match `key: value` (allow leading whitespace, ignore # comments + blank lines)
  # Use awk for Bash 3 portability — no PCRE.
  awk -v k="$key" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      # Strip leading whitespace
      sub(/^[[:space:]]+/, "")
      # Split on first colon
      idx = index($0, ":")
      if (idx == 0) next
      key = substr($0, 1, idx-1)
      val = substr($0, idx+1)
      # Strip whitespace around val
      sub(/^[[:space:]]+/, "", val)
      sub(/[[:space:]]+$/, "", val)
      # Strip trailing inline comment
      cidx = index(val, "#")
      if (cidx > 0) {
        val = substr(val, 1, cidx-1)
        sub(/[[:space:]]+$/, "", val)
      }
      # Strip surrounding quotes
      if (substr(val, 1, 1) == "\"" && substr(val, length(val), 1) == "\"") {
        val = substr(val, 2, length(val)-2)
      }
      if (substr(val, 1, 1) == "'\''" && substr(val, length(val), 1) == "'\''") {
        val = substr(val, 2, length(val)-2)
      }
      if (key == k) {
        print val
        exit 0
      }
    }
  ' "$file"
}

# === Public: get a config value ===
# Args: <key> <default>
# Echoes the resolved value.
policy_config_get() {
  local key="$1"
  local default_value="$2"
  local val

  # 1. Canonical env var
  local env_name
  env_name=$(_pc_key_to_env "$key")
  val="${!env_name:-}"
  if [[ -n "$val" ]]; then
    echo "$val"
    return 0
  fi

  # 1b. Legacy env var (back-compat)
  local legacy_env
  legacy_env=$(_pc_legacy_env "$key")
  if [[ -n "$legacy_env" ]]; then
    val="${!legacy_env:-}"
    if [[ -n "$val" ]]; then
      echo "$val"
      return 0
    fi
  fi

  # 2. Project-level policy.yml
  if [[ -n "${PROJECT_DIR:-}" ]] && [[ -f "$PROJECT_DIR/.planning/policy.yml" ]]; then
    val=$(_pc_read_yaml_key "$PROJECT_DIR/.planning/policy.yml" "$key")
    if [[ -n "$val" ]]; then
      echo "$val"
      return 0
    fi
  fi

  # 3. Vault-level policy.yml
  local vault_path="${ARK_HOME:-$HOME/vaults/ark}"
  if [[ -f "$vault_path/policy.yml" ]]; then
    val=$(_pc_read_yaml_key "$vault_path/policy.yml" "$key")
    if [[ -n "$val" ]]; then
      echo "$val"
      return 0
    fi
  fi

  # 4. Default
  echo "$default_value"
  return 0
}

# === Public: check if a key is set anywhere ===
# Returns 0 if found in env / project / vault, 1 if only the default would apply.
policy_config_has() {
  local key="$1"

  local env_name
  env_name=$(_pc_key_to_env "$key")
  [[ -n "${!env_name:-}" ]] && return 0

  local legacy_env
  legacy_env=$(_pc_legacy_env "$key")
  if [[ -n "$legacy_env" ]] && [[ -n "${!legacy_env:-}" ]]; then
    return 0
  fi

  if [[ -n "${PROJECT_DIR:-}" ]] && [[ -f "$PROJECT_DIR/.planning/policy.yml" ]]; then
    local val
    val=$(_pc_read_yaml_key "$PROJECT_DIR/.planning/policy.yml" "$key")
    [[ -n "$val" ]] && return 0
  fi

  local vault_path="${ARK_HOME:-$HOME/vaults/ark}"
  if [[ -f "$vault_path/policy.yml" ]]; then
    local val
    val=$(_pc_read_yaml_key "$vault_path/policy.yml" "$key")
    [[ -n "$val" ]] && return 0
  fi

  return 1
}

# === Public: dump effective config (debug) ===
# Echoes "key=value (source)" lines for the well-known keys.
policy_config_dump() {
  local keys=(
    "budget.monthly_escalate_pct"
    "budget.phase_cap_default"
    "budget.monthly_cap_default"
    "self_heal.max_retries"
    "dispatch.force_quota_codex"
    "dispatch.force_quota_gemini"
  )
  local defaults=(
    "95" "50000" "1000000" "3" "false" "false"
  )
  local i=0
  for key in "${keys[@]}"; do
    local val source
    val=$(policy_config_get "$key" "${defaults[$i]}")
    if policy_config_has "$key"; then
      # Determine layer
      local env_name legacy_env
      env_name=$(_pc_key_to_env "$key")
      legacy_env=$(_pc_legacy_env "$key")
      if [[ -n "${!env_name:-}" ]]; then
        source="env:$env_name"
      elif [[ -n "$legacy_env" ]] && [[ -n "${!legacy_env:-}" ]]; then
        source="env:$legacy_env (legacy)"
      elif [[ -n "${PROJECT_DIR:-}" ]] && [[ -f "$PROJECT_DIR/.planning/policy.yml" ]] && [[ -n "$(_pc_read_yaml_key "$PROJECT_DIR/.planning/policy.yml" "$key")" ]]; then
        source="project"
      else
        source="vault"
      fi
    else
      source="default"
    fi
    echo "$key=$val ($source)"
    i=$((i + 1))
  done
}

# === Self-test (only when run directly, never when sourced) ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" == "test" ]]; then
  echo "🧪 policy-config.sh self-test"
  echo ""

  pass=0
  fail=0
  assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  ✅ $label"
      pass=$((pass + 1))
    else
      echo "  ❌ $label  (expected: '$expected', got: '$actual')"
      fail=$((fail + 1))
    fi
  }

  # Setup: tmp vault + project
  TMP_BASE=$(mktemp -d)
  trap 'rm -rf "$TMP_BASE"' EXIT
  TMP_VAULT="$TMP_BASE/vault"
  TMP_PROJ="$TMP_BASE/proj"
  mkdir -p "$TMP_VAULT" "$TMP_PROJ/.planning"

  cat > "$TMP_VAULT/policy.yml" <<'EOF'
# Vault-level policy
budget.monthly_escalate_pct: 90
self_heal.max_retries: 3
EOF

  cat > "$TMP_PROJ/.planning/policy.yml" <<'EOF'
# Project-level overrides
budget.monthly_escalate_pct: 80
EOF

  # Test 1: default fallback (no overrides at all)
  ARK_HOME=/nonexistent PROJECT_DIR="" \
    assert_eq "95" "$(ARK_HOME=/nonexistent PROJECT_DIR='' policy_config_get budget.monthly_escalate_pct 95)" "default fallback when no config"

  # Test 2: vault override
  assert_eq "90" "$(ARK_HOME="$TMP_VAULT" PROJECT_DIR="" policy_config_get budget.monthly_escalate_pct 95)" "vault overrides default"

  # Test 3: project overrides vault
  assert_eq "80" "$(ARK_HOME="$TMP_VAULT" PROJECT_DIR="$TMP_PROJ" policy_config_get budget.monthly_escalate_pct 95)" "project overrides vault"

  # Test 4: env overrides project
  assert_eq "70" "$(ARK_HOME="$TMP_VAULT" PROJECT_DIR="$TMP_PROJ" ARK_BUDGET_MONTHLY_ESCALATE_PCT=70 policy_config_get budget.monthly_escalate_pct 95)" "env (canonical) overrides project"

  # Test 5: legacy env still works
  assert_eq "60" "$(ARK_HOME="$TMP_VAULT" PROJECT_DIR="$TMP_PROJ" ARK_MONTHLY_ESCALATE_PCT=60 policy_config_get budget.monthly_escalate_pct 95)" "legacy env (ARK_MONTHLY_ESCALATE_PCT) overrides project"

  # Test 6: vault default for keys only in vault
  assert_eq "3" "$(ARK_HOME="$TMP_VAULT" PROJECT_DIR="$TMP_PROJ" policy_config_get self_heal.max_retries 99)" "vault used when project has no key"

  # Test 7: has() returns 1 when only default applies
  if ARK_HOME=/nonexistent PROJECT_DIR='' policy_config_has budget.monthly_escalate_pct; then
    fail=$((fail + 1)); echo "  ❌ has() should return 1 when no source has the key"
  else
    pass=$((pass + 1)); echo "  ✅ has() returns 1 when no source has the key"
  fi

  # Test 8: has() returns 0 when env is set
  if ARK_BUDGET_MONTHLY_ESCALATE_PCT=70 policy_config_has budget.monthly_escalate_pct; then
    pass=$((pass + 1)); echo "  ✅ has() returns 0 when env set"
  else
    fail=$((fail + 1)); echo "  ❌ has() should return 0 when env set"
  fi

  # Test 9: dump produces lines with sources
  dump_out=$(ARK_HOME="$TMP_VAULT" PROJECT_DIR="$TMP_PROJ" policy_config_dump)
  if echo "$dump_out" | grep -q "budget.monthly_escalate_pct=80 (project)"; then
    pass=$((pass + 1)); echo "  ✅ dump shows project source for overridden key"
  else
    fail=$((fail + 1)); echo "  ❌ dump should show project source"
    echo "    got: $dump_out"
  fi

  # Test 10: bash 3 compatibility — no associative arrays outside test block
  # Look for the patterns in the first 200 lines (function defs, not self-test)
  if head -200 "$0" | grep -qE '^[[:space:]]*(declare|local)[[:space:]]+-A'; then
    fail=$((fail + 1)); echo "  ❌ uses associative arrays (Bash 4 only)"
  else
    pass=$((pass + 1)); echo "  ✅ no Bash 4-only constructs in main code"
  fi

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL POLICY-CONFIG TESTS PASSED ($pass/$pass)"
    exit 0
  else
    echo "❌ $fail/$((pass+fail)) tests failed"
    exit 1
  fi
fi
