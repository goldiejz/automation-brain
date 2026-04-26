#!/usr/bin/env bash
# bootstrap-policy.sh — Phase 4 inference engine for AOS.
#
# Sourced library + self-test entry point. Turns a one-line project
# description into a typed verdict (type/stack/deploy/customer) plus
# a confidence score, with full audit logging via _policy_log from
# scripts/ark-policy.sh.
#
# Heuristic-only: keyword-overlap scoring against
# bootstrap/project-types/*.md template frontmatter.
# No ML, no embeddings — pure substring counting.
#
# Public API:
#   bootstrap_infer_type <description>          -> "<type>\t<score_pct>"
#   bootstrap_infer_stack <type>                -> "<stack>"
#   bootstrap_infer_deploy <type> [customer]    -> "<deploy>"
#   bootstrap_infer_customer <description>      -> "<customer|scratch>"
#   bootstrap_classify <description> [customer_override]
#       -> stdout: "<type>\t<stack>\t<deploy>\t<customer>\t<confidence_pct>"
#       -> side effect: _policy_log "bootstrap" with full context JSON
#       -> return 0 if confident (>=threshold), 1 if escalation emitted
#
# Bash 3 compat (macOS default):
#   - NO `declare -A` (associative arrays)
#   - NO `${var,,}` lowercasing (use `tr '[:upper:]' '[:lower:]'`)
#   - NO Bash regex captures (BASH_REMATCH); use awk where needed
#
# Sourced lib discipline (mirrors scripts/lib/policy-config.sh):
#   - NO top-level `set -euo pipefail` — would propagate to callers.
#   - All helpers prefixed `_bp_`; public API is `bootstrap_*`.
#
# Audit-writer discipline:
#   - Every emission goes through `_policy_log` (single writer).
#   - Never inline `INSERT INTO decisions`.

# === Source ark-policy.sh (which transitively sources policy-config.sh + policy-db.sh) ===
# Guard: ark-policy.sh has an inline self-test triggered by `$1 == "test"`. Since
# we may be invoked with `bash bootstrap-policy.sh test`, we must hide $1 from
# the sourced script — otherwise its self-test runs and exits before our own.
_BP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
if [[ -f "$_BP_DIR/ark-policy.sh" ]]; then
  # Source with empty positional args so ark-policy.sh's `if [[ "${1:-}" == "test" ]]`
  # evaluates false. Bash 3 compat: use a subshell-free trick via `set --`.
  _BP_SAVED_ARGS=("$@")
  set --
  source "$_BP_DIR/ark-policy.sh"
  set -- "${_BP_SAVED_ARGS[@]}"
  unset _BP_SAVED_ARGS
else
  # Graceful degradation: stub _policy_log so direct invocation doesn't break.
  _policy_log() { echo "stub-decision-id"; }
  policy_config_get() { echo "$2"; }
  policy_config_has() { return 1; }
fi

# === Source bootstrap-customer stub (for bootstrap_customer_resolve_policy) ===
# shellcheck disable=SC1091
if [[ -f "$_BP_DIR/lib/bootstrap-customer.sh" ]]; then
  source "$_BP_DIR/lib/bootstrap-customer.sh"
else
  bootstrap_customer_resolve_policy() { echo "${3:-}"; }
fi

# === VAULT_PATH fallback (mirrors ark-policy.sh) ===
: "${VAULT_PATH:=${ARK_HOME:-$HOME/vaults/ark}}"

# === Lowercase helper (Bash 3 — no ${var,,}) ===
_bp_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# === Read template frontmatter `keywords:` line ===
# Echoes a space-separated list of lowercased keyword tokens.
_bp_read_template_keywords() {
  local file="$1"
  [[ ! -f "$file" ]] && return 0
  awk '
    BEGIN { infm=0; done=0 }
    /^---[[:space:]]*$/ {
      if (infm == 0) { infm = 1; next }
      else { exit }
    }
    infm == 1 {
      # Match `keywords: a, b, c`
      if (match($0, /^[[:space:]]*keywords[[:space:]]*:/)) {
        val = $0
        sub(/^[[:space:]]*keywords[[:space:]]*:/, "", val)
        sub(/^[[:space:]]+/, "", val)
        sub(/[[:space:]]+$/, "", val)
        # Strip surrounding quotes
        if (substr(val,1,1) == "\"" && substr(val,length(val),1) == "\"") {
          val = substr(val, 2, length(val)-2)
        }
        # Replace commas with spaces
        gsub(/,/, " ", val)
        # Collapse runs of whitespace
        gsub(/[[:space:]]+/, " ", val)
        sub(/^[[:space:]]+/, "", val)
        sub(/[[:space:]]+$/, "", val)
        print tolower(val)
        done = 1
        exit
      }
    }
  ' "$file"
}

# === Read an arbitrary scalar frontmatter field ===
# Echoes value (unquoted) or empty string.
_bp_read_template_field() {
  local file="$1" field="$2"
  [[ ! -f "$file" ]] && return 0
  awk -v k="$field" '
    BEGIN { infm=0 }
    /^---[[:space:]]*$/ {
      if (infm == 0) { infm = 1; next }
      else { exit }
    }
    infm == 1 {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      idx = index(line, ":")
      if (idx == 0) next
      key = substr(line, 1, idx-1)
      val = substr(line, idx+1)
      sub(/^[[:space:]]+/, "", val)
      sub(/[[:space:]]+$/, "", val)
      # Strip surrounding quotes
      if (substr(val,1,1) == "\"" && substr(val,length(val),1) == "\"") {
        val = substr(val, 2, length(val)-2)
      }
      if (key == k) { print val; exit }
    }
  ' "$file"
}

# === bootstrap_infer_type <description> ===
# Emits "<type>\t<score_pct>" on stdout (real TAB).
bootstrap_infer_type() {
  local description="$1"
  local desc_lc
  desc_lc=$(_bp_lower "$description")

  local vault="${ARK_HOME:-$VAULT_PATH}"
  local template_dir="$vault/bootstrap/project-types"

  if [[ ! -d "$template_dir" ]]; then
    printf 'custom\t0\n'
    return 0
  fi

  local best_score=0
  local best_file=""
  local best_type=""
  local file kw_line score total matched kw

  for file in "$template_dir"/*.md; do
    [[ ! -f "$file" ]] && continue
    kw_line=$(_bp_read_template_keywords "$file")
    if [[ -z "$kw_line" ]]; then
      continue
    fi
    total=0
    matched=0
    for kw in $kw_line; do
      total=$((total + 1))
      case "$desc_lc" in
        *"$kw"*) matched=$((matched + 1)) ;;
      esac
    done
    if [[ "$total" -eq 0 ]]; then
      score=0
    else
      score=$(( matched * 100 / total ))
    fi
    if [[ "$score" -gt "$best_score" ]]; then
      best_score="$score"
      best_file="$file"
      local pt
      pt=$(_bp_read_template_field "$file" project_type)
      if [[ -z "$pt" ]]; then
        # Fallback: basename minus -template.md / .md
        pt=$(basename "$file" .md)
        pt="${pt%-template}"
      fi
      best_type="$pt"
    fi
  done

  if [[ -z "$best_type" ]]; then
    printf 'custom\t0\n'
    return 0
  fi

  printf '%s\t%s\n' "$best_type" "$best_score"
}

# === bootstrap_infer_stack <type> ===
# Honors policy.yml override (`bootstrap.stack_override`) > template default > "custom".
bootstrap_infer_stack() {
  local type="$1"
  if policy_config_has bootstrap.stack_override 2>/dev/null; then
    local override
    override=$(policy_config_get bootstrap.stack_override "")
    if [[ -n "$override" ]]; then
      echo "$override"
      return 0
    fi
  fi

  local vault="${ARK_HOME:-$VAULT_PATH}"
  local file="$vault/bootstrap/project-types/${type}-template.md"
  if [[ ! -f "$file" ]]; then
    echo "custom"
    return 0
  fi
  local stack
  stack=$(_bp_read_template_field "$file" default_stack)
  if [[ -z "$stack" ]]; then
    echo "custom"
  else
    echo "$stack"
  fi
}

# === bootstrap_infer_deploy <type> [customer] ===
bootstrap_infer_deploy() {
  local type="$1"
  local customer="${2:-}"

  if [[ -n "$customer" ]] && [[ "$customer" != "scratch" ]]; then
    local cust_override
    cust_override=$(bootstrap_customer_resolve_policy "$customer" bootstrap.deploy_override "")
    if [[ -n "$cust_override" ]]; then
      echo "$cust_override"
      return 0
    fi
  fi

  case "$type" in
    service-desk|revops|ops-intelligence)
      echo "cloudflare-workers"
      ;;
    custom|scratch)
      echo "none"
      ;;
    *)
      echo "none"
      ;;
  esac
}

# === bootstrap_infer_customer <description> ===
# Parses 'for <name>' from description (case-insensitive). Empty -> "scratch".
# Sanitizes: alphanumeric only, lowercased, max 32 chars.
bootstrap_infer_customer() {
  local description="$1"
  local desc_lc
  desc_lc=$(_bp_lower "$description")

  # Awk-extract the token following the literal word "for".
  local raw
  raw=$(echo "$desc_lc" | awk '
    {
      n = NF
      for (i = 1; i < n; i++) {
        if ($i == "for") {
          print $(i+1)
          exit
        }
      }
    }
  ')

  if [[ -z "$raw" ]]; then
    echo "scratch"
    return 0
  fi

  # Sanitize: keep alphanumerics only.
  local sanitized
  sanitized=$(echo "$raw" | tr -cd 'a-z0-9')
  if [[ -z "$sanitized" ]]; then
    echo "scratch"
    return 0
  fi
  # Truncate to 32 chars
  echo "${sanitized:0:32}"
}

# === JSON-escape helper (backslash + quote) ===
_bp_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# === bootstrap_classify <description> [customer_override] ===
bootstrap_classify() {
  local description="$1"
  local customer_override="${2:-}"

  local type_score type score
  type_score=$(bootstrap_infer_type "$description")
  type=$(printf '%s' "$type_score" | awk -F'\t' '{print $1}')
  score=$(printf '%s' "$type_score" | awk -F'\t' '{print $2}')
  [[ -z "$score" ]] && score=0

  local customer
  if [[ -n "$customer_override" ]]; then
    customer="$customer_override"
  else
    customer=$(bootstrap_infer_customer "$description")
  fi

  local stack deploy
  stack=$(bootstrap_infer_stack "$type")
  deploy=$(bootstrap_infer_deploy "$type" "$customer")

  local threshold
  threshold=$(policy_config_get bootstrap.confidence_threshold_pct 50)

  # Build context JSON
  local desc_e type_e stack_e deploy_e cust_e
  desc_e=$(_bp_json_escape "$description")
  type_e=$(_bp_json_escape "$type")
  stack_e=$(_bp_json_escape "$stack")
  deploy_e=$(_bp_json_escape "$deploy")
  cust_e=$(_bp_json_escape "$customer")
  local context_json
  context_json=$(printf '{"description":"%s","type":"%s","stack":"%s","deploy":"%s","customer":"%s","confidence_pct":%s}' \
    "$desc_e" "$type_e" "$stack_e" "$deploy_e" "$cust_e" "$score")

  if [[ "$score" -ge "$threshold" ]]; then
    _policy_log "bootstrap" "CLASSIFY_CONFIDENT" "type=$type score=$score" "$context_json" >/dev/null
    printf '%s\t%s\t%s\t%s\t%s\n' "$type" "$stack" "$deploy" "$customer" "$score"
    return 0
  fi

  # Escalation path
  _policy_log "escalation" "architectural-ambiguity" \
    "bootstrap_classify low_confidence type=$type score=$score" \
    "$context_json" >/dev/null

  local vault="${ARK_HOME:-$VAULT_PATH}"
  local esc_file="$vault/ESCALATIONS.md"
  if [[ ! -f "$esc_file" ]]; then
    mkdir -p "$(dirname "$esc_file")"
    {
      echo "# ESCALATIONS"
      echo ""
      echo "## Open"
      echo ""
    } > "$esc_file"
  fi
  if ! grep -q '^## Open' "$esc_file" 2>/dev/null; then
    {
      echo ""
      echo "## Open"
      echo ""
    } >> "$esc_file"
  fi
  local iso
  iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf -- '- [ ] %s [architectural-ambiguity] bootstrap_classify low_confidence: "%s" → best=%s@%s%%\n' \
    "$iso" "$description" "$type" "$score" >> "$esc_file"

  printf '%s\t%s\t%s\t%s\t%s\n' "$type" "$stack" "$deploy" "$customer" "$score"
  return 1
}

# === Self-test (only when invoked directly with `test`) ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" == "test" ]]; then
  echo "🧪 bootstrap-policy.sh self-test"
  echo ""

  pass=0
  fail=0

  assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  ✅ $label"
      pass=$((pass+1))
    else
      echo "  ❌ $label  (expected: '$expected', got: '$actual')"
      fail=$((fail+1))
    fi
  }

  assert_ge() {
    local actual="$1" min="$2" label="$3"
    if [[ "$actual" -ge "$min" ]]; then
      echo "  ✅ $label (got: $actual >= $min)"
      pass=$((pass+1))
    else
      echo "  ❌ $label (got: $actual, expected >= $min)"
      fail=$((fail+1))
    fi
  }

  # Setup: tmp vault + isolated DB so we never touch ~/vaults/ark/observability/policy.db
  TMP_VAULT=$(mktemp -d)
  trap 'rm -rf "$TMP_VAULT"' EXIT
  export ARK_HOME="$TMP_VAULT"
  export VAULT_PATH="$TMP_VAULT"
  export ARK_POLICY_DB="$TMP_VAULT/observability/policy.db"
  mkdir -p "$TMP_VAULT/bootstrap/project-types"
  mkdir -p "$TMP_VAULT/observability"

  # Re-init the SQLite DB at the new isolated path.
  if type db_init >/dev/null 2>&1; then
    db_init >/dev/null
  fi

  # Minimal templates that include the keyword frontmatter that 04-02 will add.
  cat > "$TMP_VAULT/bootstrap/project-types/service-desk-template.md" <<'EOF'
---
project_type: service-desk
keywords: service desk, ticket, sla, helpdesk, itil
default_stack: vite-react-hono
default_deploy: cloudflare-workers
---
# Service Desk Template
EOF

  cat > "$TMP_VAULT/bootstrap/project-types/custom-template.md" <<'EOF'
---
project_type: custom
keywords:
default_stack: custom
default_deploy: none
---
# Custom Template
EOF

  echo "=== Test 1: bootstrap_infer_type — service desk match ==="
  out=$(bootstrap_infer_type "service desk for acme with sla and itil")
  t1_type=$(printf '%s' "$out" | awk -F'\t' '{print $1}')
  t1_score=$(printf '%s' "$out" | awk -F'\t' '{print $2}')
  assert_eq "service-desk" "$t1_type" "infer_type returns service-desk"
  assert_ge "$t1_score" 50 "infer_type score >= 50"

  echo ""
  echo "=== Test 2: bootstrap_infer_customer — extracts 'acme' ==="
  out=$(bootstrap_infer_customer "service desk for acme")
  assert_eq "acme" "$out" "extracts 'acme' after 'for'"

  echo ""
  echo "=== Test 3: bootstrap_infer_customer — no 'for' phrase → scratch ==="
  out=$(bootstrap_infer_customer "internal scratch tool")
  assert_eq "scratch" "$out" "no 'for' phrase yields 'scratch'"

  echo ""
  echo "=== Test 4: bootstrap_infer_stack — service-desk → vite-react-hono ==="
  out=$(bootstrap_infer_stack "service-desk")
  assert_eq "vite-react-hono" "$out" "service-desk default_stack"

  echo ""
  echo "=== Test 5: bootstrap_infer_deploy — service-desk → cloudflare-workers ==="
  out=$(bootstrap_infer_deploy "service-desk")
  assert_eq "cloudflare-workers" "$out" "service-desk → cloudflare-workers"

  echo ""
  echo "=== Test 6: bootstrap_infer_deploy — custom → none ==="
  out=$(bootstrap_infer_deploy "custom")
  assert_eq "none" "$out" "custom → none"

  echo ""
  echo "=== Test 7: bootstrap_classify — confident path ==="
  # Reset DB count baseline
  baseline=$(sqlite3 "$ARK_POLICY_DB" "SELECT COUNT(*) FROM decisions WHERE class='bootstrap';" 2>/dev/null || echo 0)
  if bootstrap_classify "service desk for acme with itil sla" >/tmp/bp_test_out_$$ 2>/dev/null; then
    rc=0
  else
    rc=$?
  fi
  tsv=$(cat /tmp/bp_test_out_$$)
  rm -f /tmp/bp_test_out_$$
  assert_eq "0" "$rc" "classify confident → returns 0"
  field1=$(printf '%s' "$tsv" | awk -F'\t' '{print $1}')
  assert_eq "service-desk" "$field1" "classify TSV first field == service-desk"
  fields=$(printf '%s' "$tsv" | awk -F'\t' '{print NF}')
  assert_eq "5" "$fields" "classify TSV has 5 fields"
  bs_count=$(sqlite3 "$ARK_POLICY_DB" "SELECT COUNT(*) FROM decisions WHERE class='bootstrap';" 2>/dev/null || echo 0)
  if [[ "$bs_count" -gt "$baseline" ]]; then
    echo "  ✅ _policy_log emitted at least one 'bootstrap' row (baseline=$baseline now=$bs_count)"
    pass=$((pass+1))
  else
    echo "  ❌ no new 'bootstrap' row (baseline=$baseline now=$bs_count)"
    fail=$((fail+1))
  fi

  echo ""
  echo "=== Test 8: bootstrap_classify — low_confidence escalation ==="
  baseline_esc=$(sqlite3 "$ARK_POLICY_DB" "SELECT COUNT(*) FROM decisions WHERE class='escalation';" 2>/dev/null || echo 0)
  if bootstrap_classify "vague random nonsense xyzzy" >/tmp/bp_test_out_$$ 2>/dev/null; then
    rc2=0
  else
    rc2=$?
  fi
  rm -f /tmp/bp_test_out_$$
  if [[ "$rc2" -ne 0 ]]; then
    echo "  ✅ classify low_confidence → returns non-zero (rc=$rc2)"
    pass=$((pass+1))
  else
    echo "  ❌ classify should return non-zero on low confidence"
    fail=$((fail+1))
  fi
  esc_count=$(sqlite3 "$ARK_POLICY_DB" "SELECT COUNT(*) FROM decisions WHERE class='escalation' AND decision='architectural-ambiguity';" 2>/dev/null || echo 0)
  if [[ "$esc_count" -gt "$baseline_esc" ]]; then
    echo "  ✅ escalation row written (baseline=$baseline_esc now=$esc_count)"
    pass=$((pass+1))
  else
    echo "  ❌ no escalation row (baseline=$baseline_esc now=$esc_count)"
    fail=$((fail+1))
  fi
  if [[ -f "$TMP_VAULT/ESCALATIONS.md" ]] && grep -q 'architectural-ambiguity' "$TMP_VAULT/ESCALATIONS.md"; then
    echo "  ✅ ESCALATIONS.md row appended"
    pass=$((pass+1))
  else
    echo "  ❌ ESCALATIONS.md missing or no row"
    fail=$((fail+1))
  fi

  echo ""
  echo "=== Test 9: Bash 3 compat — no associative arrays in main code ==="
  if head -300 "$0" | grep -qE '^[[:space:]]*(declare|local)[[:space:]]+-A'; then
    echo "  ❌ uses associative arrays"
    fail=$((fail+1))
  else
    echo "  ✅ no Bash 4-only constructs in main code"
    pass=$((pass+1))
  fi

  echo ""
  echo "=== Test 10: no actual read -p invocation ==="
  # An actual `read -p` invocation appears at the start of a statement (not in a
  # comment, echo, or grep pattern). Match only `read -p` that is the first token
  # on a line (after optional indentation), which is how a real prompt would be
  # written. The assertion lines in this self-test reference the pattern inside
  # strings/comments and so won't match this stricter form.
  if grep -nE '^[[:space:]]*read[[:space:]]+-p[[:space:]]' "$0" >/dev/null; then
    echo "  ❌ contains an actual read -p invocation"
    fail=$((fail+1))
  else
    echo "  ✅ no real read -p invocation"
    pass=$((pass+1))
  fi

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL BOOTSTRAP-POLICY TESTS PASSED ($pass/$pass)"
    exit 0
  else
    echo "❌ $fail/$((pass+fail)) tests failed"
    exit 1
  fi
fi
