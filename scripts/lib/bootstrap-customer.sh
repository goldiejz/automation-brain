#!/usr/bin/env bash
# bootstrap-customer.sh — Customer-layer policy resolution.
#
# Hardened in 04-05: mkdir-lock pattern + idempotent seed of <customer>/policy.yml.
# Cascading order: env > project > THIS LAYER > vault > default.
#
# Sourced library — no top-level set -euo pipefail.
# Bash 3 compatible (macOS default).

# bootstrap_customer_dir <customer> — echoes the customer dir path; does NOT create.
bootstrap_customer_dir() {
  local customer="$1"
  [[ -z "$customer" ]] && return 1
  local vault="${ARK_HOME:-$HOME/vaults/ark}"
  echo "$vault/customers/$customer"
}

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

# === mkdir-lock helpers (Phase 3 pattern, mirrored) ===
_bc_acquire_lock() {
  local lockdir="$1"
  local timeout="${2:-5}"
  local elapsed=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    [[ "$elapsed" -ge "$timeout" ]] && return 1
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 0
}
_bc_release_lock() { rmdir "$1" 2>/dev/null || true; }

# bootstrap_customer_init <customer> — idempotent, mkdir-lock-safe customer-dir
# creation. Seeds <customer>/policy.yml with sane defaults on first creation.
bootstrap_customer_init() {
  local customer="$1"
  [[ -z "$customer" ]] && return 1

  local dir
  dir="$(bootstrap_customer_dir "$customer")"
  local lockdir="${dir}.lock"

  # Fast path: already initialized.
  if [[ -f "$dir/policy.yml" ]]; then
    return 0
  fi

  # Ensure parent (customers/) exists so mkdir-lock has a place to land.
  # The lockdir itself MUST be created non-recursively (atomic).
  mkdir -p "$(dirname "$dir")"

  # Acquire mkdir-lock; bail (success) if held > 5s — a concurrent caller wins.
  _bc_acquire_lock "$lockdir" 5 || return 0

  # Double-checked locking: another caller may have completed during the wait.
  if [[ -f "$dir/policy.yml" ]]; then
    _bc_release_lock "$lockdir"
    return 0
  fi

  mkdir -p "$dir"
  local seed_tmp="$dir/policy.yml.tmp.$$"
  local created
  created=$(date -u +%Y-%m-%d)
  cat > "$seed_tmp" <<EOF
# Customer-level policy for $customer.
# Auto-seeded by ark create (Phase 4 bootstrap-autonomy).
# Cascading order: env > project > THIS FILE > vault > default.

# Override deploy target for all of $customer's projects:
# bootstrap.deploy_override: cloudflare-workers

# Override stack default for all of $customer's projects:
# bootstrap.stack_override: vite-react-hono

# Customer metadata:
customer.name: $customer
customer.created: $created
EOF
  mv "$seed_tmp" "$dir/policy.yml"

  _bc_release_lock "$lockdir"
  return 0
}

# === Self-test (only when run directly) ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" == "test" ]]; then
  echo "🧪 bootstrap-customer.sh self-test"
  echo ""

  pass=0
  fail=0
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  export ARK_HOME="$TMP"

  # Test 1: bootstrap_customer_init creates dir + policy.yml.
  bootstrap_customer_init acme
  if [[ -f "$TMP/customers/acme/policy.yml" ]]; then
    pass=$((pass+1)); echo "  ✅ init creates customer dir + policy.yml"
  else
    fail=$((fail+1)); echo "  ❌ init didn't create policy.yml"
  fi

  # Test 2: idempotent — second call returns 0 without recreating.
  orig_md5=$(md5 -q "$TMP/customers/acme/policy.yml" 2>/dev/null || md5sum "$TMP/customers/acme/policy.yml" | awk '{print $1}')
  sleep 1
  bootstrap_customer_init acme
  new_md5=$(md5 -q "$TMP/customers/acme/policy.yml" 2>/dev/null || md5sum "$TMP/customers/acme/policy.yml" | awk '{print $1}')
  if [[ "$orig_md5" == "$new_md5" ]]; then
    pass=$((pass+1)); echo "  ✅ idempotent: file unchanged on re-init"
  else
    fail=$((fail+1)); echo "  ❌ idempotent broken — md5 changed"
  fi

  # Test 3: bootstrap_customer_resolve_policy reads the seeded customer.name.
  val=$(bootstrap_customer_resolve_policy acme customer.name "default")
  if [[ "$val" == "acme" ]]; then
    pass=$((pass+1)); echo "  ✅ resolve_policy reads seeded value"
  else
    fail=$((fail+1)); echo "  ❌ resolve_policy got '$val'"
  fi

  # Test 4: resolve falls back to default when key missing.
  val=$(bootstrap_customer_resolve_policy acme bootstrap.deploy_override "fallback")
  if [[ "$val" == "fallback" ]]; then
    pass=$((pass+1)); echo "  ✅ resolve_policy default fallback"
  else
    fail=$((fail+1)); echo "  ❌ resolve_policy fallback got '$val'"
  fi

  # Test 5: concurrent-init lock — fork 5 procs; assert single policy.yml created.
  for i in 1 2 3 4 5; do
    ( bootstrap_customer_init concurrent ) &
  done
  wait
  if [[ -f "$TMP/customers/concurrent/policy.yml" ]] && \
     ! [[ -d "$TMP/customers/concurrent.lock" ]]; then
    pass=$((pass+1)); echo "  ✅ concurrent init: lock released, file exists"
  else
    fail=$((fail+1)); echo "  ❌ concurrent init: lock leaked or file missing"
  fi

  # Test 6: Bash 3 compat — no associative arrays in main code.
  if head -110 "$0" | grep -qE '^[[:space:]]*(declare|local)[[:space:]]+-A'; then
    fail=$((fail+1)); echo "  ❌ Bash 4 constructs"
  else
    pass=$((pass+1)); echo "  ✅ no Bash 4 constructs"
  fi

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL BOOTSTRAP-CUSTOMER TESTS PASSED ($pass/$pass)"
    exit 0
  else
    echo "❌ $fail/$((pass+fail)) tests failed"
    exit 1
  fi
fi
