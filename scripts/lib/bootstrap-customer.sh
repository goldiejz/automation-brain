#!/usr/bin/env bash
# bootstrap-customer.sh — Customer-layer policy resolution (STUB).
#
# 04-01 ships this as a stub library defining the API surface that
# scripts/bootstrap-policy.sh consumes. 04-05 extends every function
# below with the full mkdir-lock + cascading-config integration.
#
# Sourced library — no top-level set -euo pipefail.
# Bash 3 compatible (macOS default).

# STUB — extended in 04-05
# bootstrap_customer_dir <customer> — echoes the customer dir path; does NOT create.
bootstrap_customer_dir() {
  local customer="$1"
  [[ -z "$customer" ]] && return 1
  local vault="${ARK_HOME:-$HOME/vaults/ark}"
  echo "$vault/customers/$customer"
}

# STUB — extended in 04-05
# bootstrap_customer_resolve_policy <customer> <dotted.key> [default]
# Reads <customer-dir>/policy.yml for <dotted.key>; falls back to default.
bootstrap_customer_resolve_policy() {
  local customer="$1" key="$2" default_value="${3:-}"
  [[ -z "$customer" ]] && { echo "$default_value"; return 0; }
  local file
  file="$(bootstrap_customer_dir "$customer")/policy.yml"
  [[ ! -f "$file" ]] && { echo "$default_value"; return 0; }
  local val
  val=$(awk -v k="$key" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      sub(/^[[:space:]]+/, "")
      idx = index($0, ":")
      if (idx == 0) next
      ykey = substr($0, 1, idx-1)
      yval = substr($0, idx+1)
      sub(/^[[:space:]]+/, "", yval)
      sub(/[[:space:]]+$/, "", yval)
      if (ykey == k) { print yval; exit 0 }
    }
  ' "$file")
  [[ -z "$val" ]] && val="$default_value"
  echo "$val"
}

# STUB — extended in 04-05
# bootstrap_customer_init <customer> — idempotent customer dir creation.
bootstrap_customer_init() {
  local customer="$1"
  [[ -z "$customer" ]] && return 1
  local dir
  dir="$(bootstrap_customer_dir "$customer")"
  mkdir -p "$dir"
  return 0
}

# === Self-test (only when run directly) ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" == "test" ]]; then
  echo "🧪 bootstrap-customer.sh self-test (stub)"
  pass=0
  fail=0

  for fn in bootstrap_customer_dir bootstrap_customer_resolve_policy bootstrap_customer_init; do
    if declare -F "$fn" >/dev/null; then
      echo "  ✅ $fn defined"
      pass=$((pass+1))
    else
      echo "  ❌ $fn not defined"
      fail=$((fail+1))
    fi
  done

  out=$(ARK_HOME=/tmp/test-vault bootstrap_customer_dir acme)
  case "$out" in
    */customers/acme)
      echo "  ✅ bootstrap_customer_dir acme echoes path ending in /customers/acme"
      pass=$((pass+1))
      ;;
    *)
      echo "  ❌ unexpected path: $out"
      fail=$((fail+1))
      ;;
  esac

  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL BOOTSTRAP-CUSTOMER STUB TESTS PASSED ($pass/$pass)"
    exit 0
  else
    echo "❌ $fail/$((pass+fail)) tests failed"
    exit 1
  fi
fi
