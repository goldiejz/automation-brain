#!/usr/bin/env bash
# lesson-promoter.sh — Cross-customer lesson discovery + clustering + classification.
#
# Phase 6 Plans 06-02 (this) and 06-03 (apply-pending sentinel section).
# Requirements: REQ-AOS-31 (cross-customer lesson promotion), REQ-AOS-33
# (anti-pattern routing).
#
# READ-ONLY against per-customer tasks/lessons.md files at this stage.
# Vault writes are confined to the apply-pending sentinel section (filled
# by Plan 06-03). No `_policy_log` calls in 06-02 — apply step is the
# audit boundary (Phase 2 single-writer contract).
#
# Public API:
#   promoter_scan_lessons [root]    — TSV: customer<TAB>lesson_path<TAB>title<TAB>severity
#   promoter_cluster_similar        — TSV: cluster_id<TAB>customer<TAB>lesson_path<TAB>title<TAB>severity<TAB>similarity
#   promoter_classify_cluster       — TSV: cluster_id<TAB>verdict<TAB>customer_count<TAB>lesson_count<TAB>route<TAB>title_seed
#   promoter_run [--full|--since DATE] [--apply] [--dry-run]
#
# Bash 3 compat (macOS default). NO `declare -A`, `mapfile`, `readarray`.
# NOT `set -e` (sourceable lib must not break callers).

set -uo pipefail

# Locate sibling lib dir (works whether sourced or executed directly)
_LP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib"

# Source similarity primitive (06-01)
# shellcheck disable=SC1091
if [[ -f "$_LP_LIB_DIR/lesson-similarity.sh" ]]; then
  source "$_LP_LIB_DIR/lesson-similarity.sh"
else
  echo "❌ lesson-promoter.sh requires scripts/lib/lesson-similarity.sh (Plan 06-01)" >&2
  exit 1
fi

# === Locked thresholds (CONTEXT.md D-PROMOTION-THRESHOLD) ===
PROMOTE_MIN_CUSTOMERS=2
PROMOTE_MIN_OCCURRENCES=3
PROMOTE_MIN_SIMILARITY=60

# === Roots and targets ===
ARK_PORTFOLIO_ROOT="${ARK_PORTFOLIO_ROOT:-$HOME/code}"
VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
UNIVERSAL_TARGET="${UNIVERSAL_TARGET:-$VAULT_PATH/lessons/universal-patterns.md}"
ANTIPATTERN_TARGET="${ANTIPATTERN_TARGET:-$VAULT_PATH/bootstrap/anti-patterns.md}"

# === _lp_split_file <path> <out_dir> ===
# Split a multi-lesson tasks/lessons.md into one tmp file per `## Lesson:` block.
# For files without `## Lesson:`, treat the whole file as a single lesson.
# Echoes each emitted tmp path on stdout.
_lp_split_file() {
  local file="$1"
  local out_dir="$2"
  local base
  # Use a hash of the source path so two customers' lessons.md files don't
  # collide on basename in the shared scan tmpdir.
  local path_hash
  path_hash=$(printf '%s' "$file" | shasum 2>/dev/null | cut -c1-12)
  if [[ -z "$path_hash" ]]; then
    path_hash=$(printf '%s' "$file" | md5 -q 2>/dev/null | cut -c1-12)
  fi
  base="$(basename "$file" .md)-$path_hash"

  if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
    return 0
  fi

  # Detect Format A (## Lesson: ...) blocks
  if grep -qi '^## lesson:' "$file" 2>/dev/null; then
    awk -v out_dir="$out_dir" -v base="$base" '
      BEGIN { idx = 0; current = "" }
      tolower($0) ~ /^## lesson:/ {
        if (current != "") {
          fname = out_dir "/" base "-" idx ".md"
          print current > fname
          close(fname)
          print fname
          idx++
        }
        current = $0 "\n"
        next
      }
      # Next ## (non-Lesson) heading closes block too
      current != "" && /^## / && tolower($0) !~ /^## lesson:/ {
        fname = out_dir "/" base "-" idx ".md"
        print current > fname
        close(fname)
        print fname
        idx++
        current = ""
        next
      }
      current != "" { current = current $0 "\n"; next }
      END {
        if (current != "") {
          fname = out_dir "/" base "-" idx ".md"
          print current > fname
          close(fname)
          print fname
        }
      }
    ' "$file"
    return 0
  fi

  # Format B / fallback: whole file as single lesson
  local fname="$out_dir/$base-0.md"
  cp "$file" "$fname"
  echo "$fname"
}

# === _lp_infer_severity <lesson_file> ===
# anti  → title or body contains 'anti-pattern' or "don't" / "do not"
# high  → contains WARNING|CRITICAL|MUST
# normal → default
_lp_infer_severity() {
  local file="$1"
  if grep -qiE "anti-pattern|don't|do not" "$file" 2>/dev/null; then
    echo "anti"
    return 0
  fi
  if grep -qE "WARNING|CRITICAL|MUST" "$file" 2>/dev/null; then
    echo "high"
    return 0
  fi
  echo "normal"
}

# === _lp_extract_title <lesson_file> ===
# Strip "## Lesson:" prefix from first heading; fallback to first "# " heading.
_lp_extract_title() {
  local file="$1"
  local title
  title=$(grep -i '^## lesson:' "$file" 2>/dev/null | head -1 \
    | sed -E 's/^##[[:space:]]*[Ll][Ee][Ss][Ss][Oo][Nn]:[[:space:]]*//')
  if [[ -n "$title" ]]; then
    echo "$title"
    return 0
  fi
  title=$(grep '^# ' "$file" 2>/dev/null | head -1 | sed -E 's/^#[[:space:]]+//')
  if [[ -n "$title" ]]; then
    echo "$title"
    return 0
  fi
  echo "(untitled)"
}

# === promoter_scan_lessons [root] ===
# Walks <root>/*/tasks/lessons.md (depth 2 — never recurse into project subtrees).
# Splits each file into one lesson per tmp path. Emits TSV rows:
#   customer<TAB>lesson_path<TAB>title<TAB>severity
# Tmp output directory survives until caller cleans up (orchestrator has trap).
promoter_scan_lessons() {
  local root="${1:-$ARK_PORTFOLIO_ROOT}"
  local since_epoch="${LP_SINCE_EPOCH:-0}"
  local out_dir
  out_dir=$(mktemp -d -t ark-lesson-scan-XXXXXXXX)
  # Export for orchestrator cleanup
  export LP_LAST_SCAN_TMPDIR="$out_dir"

  if [[ ! -d "$root" ]]; then
    return 0
  fi

  local lesson_file customer customer_dir lesson_path title severity mtime
  for lesson_file in "$root"/*/tasks/lessons.md; do
    [[ -f "$lesson_file" ]] || continue
    if [[ "$since_epoch" -gt 0 ]]; then
      mtime=$(stat -f %m "$lesson_file" 2>/dev/null || stat -c %Y "$lesson_file" 2>/dev/null || echo 0)
      [[ "$mtime" -lt "$since_epoch" ]] && continue
    fi
    customer_dir=$(dirname "$(dirname "$lesson_file")")
    customer=$(basename "$customer_dir")

    # Split and iterate
    while IFS= read -r lesson_path; do
      [[ -z "$lesson_path" ]] && continue
      [[ -f "$lesson_path" ]] || continue
      title=$(_lp_extract_title "$lesson_path")
      severity=$(_lp_infer_severity "$lesson_path")
      printf '%s\t%s\t%s\t%s\n' "$customer" "$lesson_path" "$title" "$severity"
    done < <(_lp_split_file "$lesson_file" "$out_dir")
  done
}

# === promoter_cluster_similar ===
# Reads scan TSV from stdin, applies greedy single-link clustering against
# cluster seeds. Threshold = $PROMOTE_MIN_SIMILARITY (60).
# Emits TSV: cluster_id<TAB>customer<TAB>lesson_path<TAB>title<TAB>severity<TAB>similarity_to_seed
promoter_cluster_similar() {
  local line customer lesson_path title severity
  # Bash-3-compat: parallel indexed arrays (no associative)
  local -a seed_paths
  seed_paths=()
  local seed_count=0
  local i sim assigned cluster_id

  while IFS=$'\t' read -r customer lesson_path title severity; do
    [[ -z "$lesson_path" ]] && continue
    assigned=-1
    sim=100
    i=0
    while [[ "$i" -lt "$seed_count" ]]; do
      sim=$(lesson_similarity "$lesson_path" "${seed_paths[$i]}" 2>/dev/null)
      sim="${sim:-0}"
      if [[ "$sim" -ge "$PROMOTE_MIN_SIMILARITY" ]]; then
        assigned="$i"
        break
      fi
      i=$((i + 1))
    done
    if [[ "$assigned" -ge 0 ]]; then
      cluster_id="$assigned"
    else
      cluster_id="$seed_count"
      seed_paths[$seed_count]="$lesson_path"
      seed_count=$((seed_count + 1))
      sim=100
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$cluster_id" "$customer" "$lesson_path" "$title" "$severity" "$sim"
  done
}

# === promoter_classify_cluster ===
# Reads cluster TSV from stdin, emits one row per cluster:
#   cluster_id<TAB>verdict<TAB>customer_count<TAB>lesson_count<TAB>route<TAB>title_seed
# verdict ∈ {PROMOTE, DEPRECATED, MEDIOCRE_KEPT_PER_CUSTOMER}
# route   ∈ {universal-patterns, anti-patterns, none}
promoter_classify_cluster() {
  # Stage stdin to a tmp file so we can re-scan per cluster
  local stage
  stage=$(mktemp -t ark-cluster-stage-XXXXXXXX)
  cat > "$stage"

  if [[ ! -s "$stage" ]]; then
    rm -f "$stage"
    return 0
  fi

  # Get unique cluster IDs in order of first appearance
  local cluster_ids
  cluster_ids=$(awk -F'\t' '!seen[$1]++ { print $1 }' "$stage")

  local cid customer_count lesson_count title_seed has_anti has_do has_dont route verdict
  while IFS= read -r cid; do
    [[ -z "$cid" ]] && continue
    # Subset for this cluster
    customer_count=$(awk -F'\t' -v c="$cid" '$1==c { print $2 }' "$stage" | sort -u | wc -l | tr -d ' ')
    lesson_count=$(awk -F'\t' -v c="$cid" '$1==c' "$stage" | wc -l | tr -d ' ')
    title_seed=$(awk -F'\t' -v c="$cid" '$1==c { print $4; exit }' "$stage")
    has_anti=$(awk -F'\t' -v c="$cid" '$1==c && $5=="anti"' "$stage" | wc -l | tr -d ' ')

    # Conflict heuristic (intentionally narrow — a guard, not a resolver):
    # A row has POSITIVE imperative if its title contains "do " or "always"
    # but does NOT also contain a negation ("don't", "do not", "never",
    # "anti-pattern"). A row has NEGATIVE imperative if its title contains
    # "don't" / "do not" / "never" / "anti-pattern". Conflict = both kinds
    # present in the same cluster across distinct customers.
    has_do=$(awk -F'\t' -v c="$cid" '$1==c { t=tolower($4);
        is_neg = (t ~ /don'\''?t|do not|never|anti-pattern/);
        is_pos = (t ~ /(^| )do( |$)|always/);
        if (is_pos && !is_neg) print "POS"
      }' "$stage" | grep -c POS || true)
    has_dont=$(awk -F'\t' -v c="$cid" '$1==c { t=tolower($4);
        if (t ~ /don'\''?t|do not|never|anti-pattern/) print "NEG"
      }' "$stage" | grep -c NEG || true)
    has_do=$(echo "$has_do" | tr -d ' \n')
    has_dont=$(echo "$has_dont" | tr -d ' \n')

    if [[ "$customer_count" -ge 2 ]] && [[ "$has_do" -ge 1 ]] && [[ "$has_dont" -ge 1 ]]; then
      verdict="DEPRECATED"
      route="none"
    elif [[ "$customer_count" -ge "$PROMOTE_MIN_CUSTOMERS" ]] && [[ "$lesson_count" -ge "$PROMOTE_MIN_OCCURRENCES" ]]; then
      verdict="PROMOTE"
      if [[ "$has_anti" -ge 1 ]]; then
        route="anti-patterns"
      else
        route="universal-patterns"
      fi
    else
      verdict="MEDIOCRE_KEPT_PER_CUSTOMER"
      route="none"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$cid" "$verdict" "$customer_count" "$lesson_count" "$route" "$title_seed"
  done <<< "$cluster_ids"

  rm -f "$stage"
}

# === SECTION: apply-pending (Plan 06-03) ===
# Plan 06-03 fills this section in. It must define:
#   promoter_apply_pending <verdicts_tsv_file>
# which:
#   - For each PROMOTE row, atomically appends a canonical entry to the
#     route file ($UNIVERSAL_TARGET or $ANTIPATTERN_TARGET) under a
#     mkdir-lock at $VAULT_PATH/.lesson-promoter.lock.
#   - Idempotency: grep for canonical marker (cluster title + customer
#     citation) before append; skip if present.
#   - Audits via `_policy_log "lesson_promote" "PROMOTED" ...` (single
#     writer rule from Phase 2). DEPRECATED rows audit-log decision
#     "DEPRECATED" without writing the file.
#   - Commits each touched vault file via git -C "$VAULT_PATH" commit.
#   - Returns 0 on success; non-zero on lock failure.
promoter_apply_pending() {
  echo "# Plan 06-03 has not been applied yet — apply-pending stub" >&2
  return 0
}
# === END SECTION: apply-pending ===

# === promoter_run [--full | --since DATE] [--apply] [--dry-run] ===
promoter_run() {
  local mode="full"
  local since=""
  local apply=0
  local dry_run=0

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --full)    mode="full"; shift ;;
      --since)   mode="since"; since="${2:-}"; shift 2 ;;
      --apply)   apply=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      *)         shift ;;
    esac
  done

  if [[ "$mode" == "since" ]] && [[ -n "$since" ]]; then
    local since_epoch
    since_epoch=$(date -u -j -f "%Y-%m-%d" "$since" +%s 2>/dev/null \
      || date -u -d "$since" +%s 2>/dev/null \
      || echo 0)
    export LP_SINCE_EPOCH="$since_epoch"
  else
    export LP_SINCE_EPOCH=0
  fi

  local scan_tsv cluster_tsv verdicts_tsv
  scan_tsv=$(promoter_scan_lessons "$ARK_PORTFOLIO_ROOT")
  local scan_tmpdir="${LP_LAST_SCAN_TMPDIR:-}"
  trap '[[ -n "${scan_tmpdir:-}" ]] && rm -rf "$scan_tmpdir"' EXIT

  if [[ -z "$scan_tsv" ]]; then
    echo "clusters: 0 (promote: 0, deprecate: 0, mediocre: 0)"
    return 0
  fi

  cluster_tsv=$(printf '%s\n' "$scan_tsv" | promoter_cluster_similar)
  verdicts_tsv=$(printf '%s\n' "$cluster_tsv" | promoter_classify_cluster)

  if [[ "$dry_run" -eq 1 ]]; then
    printf '%s\n' "$verdicts_tsv"
    return 0
  fi

  local p d m
  p=$(printf '%s\n' "$verdicts_tsv" | awk -F'\t' '$2=="PROMOTE"' | wc -l | tr -d ' ')
  d=$(printf '%s\n' "$verdicts_tsv" | awk -F'\t' '$2=="DEPRECATED"' | wc -l | tr -d ' ')
  m=$(printf '%s\n' "$verdicts_tsv" | awk -F'\t' '$2=="MEDIOCRE_KEPT_PER_CUSTOMER"' | wc -l | tr -d ' ')
  echo "clusters: $((p+d+m)) (promote: $p, deprecate: $d, mediocre: $m)"

  if [[ "$apply" -eq 1 ]]; then
    local verdicts_file
    verdicts_file=$(mktemp -t ark-promoter-verdicts-XXXXXXXX)
    printf '%s\n' "$verdicts_tsv" > "$verdicts_file"
    promoter_apply_pending "$verdicts_file"
    rm -f "$verdicts_file"
  fi
}

# === CLI / Self-test ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    scan)        shift; promoter_scan_lessons "${1:-$ARK_PORTFOLIO_ROOT}"; exit 0 ;;
    cluster)     promoter_cluster_similar; exit 0 ;;
    classify)    promoter_classify_cluster; exit 0 ;;
    run|--full)  promoter_run --full; exit 0 ;;
    --since)     shift; promoter_run --since "${1:-}"; exit 0 ;;
    --apply)     promoter_run --apply; exit 0 ;;
    --dry-run)   promoter_run --dry-run; exit 0 ;;
    test)        : ;;  # fall through to self-test
    "")          echo "Usage: $0 [test|scan|cluster|classify|run|--full|--since DATE|--apply|--dry-run]" >&2; exit 1 ;;
    *)           echo "Usage: $0 [test|scan|cluster|classify|run|--full|--since DATE|--apply|--dry-run]" >&2; exit 1 ;;
  esac

  # ---- Self-test ----
  echo "lesson-promoter.sh self-test"
  echo ""

  pass=0
  fail=0
  assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  PASS $label"
      pass=$((pass + 1))
    else
      echo "  FAIL $label  (expected: '$expected', got: '$actual')"
      fail=$((fail + 1))
    fi
  }
  assert_ge() {
    local lo="$1" actual="$2" label="$3"
    if [[ "$actual" =~ ^[0-9]+$ ]] && [[ "$actual" -ge "$lo" ]]; then
      echo "  PASS $label  (got $actual, expected >=$lo)"
      pass=$((pass + 1))
    else
      echo "  FAIL $label  (got '$actual', expected >=$lo)"
      fail=$((fail + 1))
    fi
  }

  # --- Real-vault md5 capture (BEFORE any test work) ---
  REAL_VAULT_FILE="$HOME/vaults/ark/lessons/universal-patterns.md"
  if [[ -f "$REAL_VAULT_FILE" ]]; then
    REAL_MD5_BEFORE=$(md5 -q "$REAL_VAULT_FILE" 2>/dev/null \
      || md5sum "$REAL_VAULT_FILE" 2>/dev/null | awk '{print $1}')
  else
    REAL_MD5_BEFORE=""
  fi

  # --- Build isolated portfolio + tmp vault ---
  TEST_PORTFOLIO=$(mktemp -d -t ark-promoter-test-XXXXXXXX)
  TEST_VAULT=$(mktemp -d -t ark-promoter-vault-XXXXXXXX)
  mkdir -p "$TEST_VAULT/lessons" "$TEST_VAULT/bootstrap"
  : > "$TEST_VAULT/lessons/universal-patterns.md"
  : > "$TEST_VAULT/bootstrap/anti-patterns.md"
  CANARY_BEFORE=$(md5 -q "$TEST_VAULT/lessons/universal-patterns.md" 2>/dev/null \
    || md5sum "$TEST_VAULT/lessons/universal-patterns.md" 2>/dev/null | awk '{print $1}')

  export ARK_PORTFOLIO_ROOT="$TEST_PORTFOLIO"
  export VAULT_PATH="$TEST_VAULT"
  export ARK_HOME="$TEST_VAULT"
  export UNIVERSAL_TARGET="$TEST_VAULT/lessons/universal-patterns.md"
  export ANTIPATTERN_TARGET="$TEST_VAULT/bootstrap/anti-patterns.md"

  trap 'rm -rf "$TEST_PORTFOLIO" "$TEST_VAULT" "${LP_LAST_SCAN_TMPDIR:-/nonexistent-xyz}"' EXIT

  mkdir -p "$TEST_PORTFOLIO/cust-a/tasks" \
           "$TEST_PORTFOLIO/cust-b/tasks" \
           "$TEST_PORTFOLIO/cust-c/tasks"

  # cust-a: 3 lessons. Two RBAC variants (to satisfy ≥3 occurrence threshold
  # together with cust-b), one wrangler.
  cat > "$TEST_PORTFOLIO/cust-a/tasks/lessons.md" <<'EOF'
# Lessons Learned

## Lesson: Centralise RBAC role arrays in single source of truth
**Trigger:** Inline role arrays drifted between routes and middleware
**Mistake:** Hardcoded role list in three different files
**Rule:** Every RBAC role array must live in one centralised module. Routes and components import the array. Lint forbids inline role arrays. Centralised role array is the single source of truth.
**Date:** 2026-04-01

## Lesson: RBAC role arrays must be centralised in single source module
**Trigger:** Role array drift caught in code review
**Mistake:** Inline role arrays scattered across components and routes
**Rule:** Centralise every RBAC role array in one single source of truth module. Routes and components must import the centralised role array. Lint forbids inline role arrays anywhere in source.
**Date:** 2026-04-03

## Lesson: Wrangler binding deploy requires explicit project name
**Trigger:** Wrong D1 binding deployed
**Mistake:** Assumed default project from wrangler.toml
**Rule:** Always pass --project-name explicitly when deploying wrangler pages with multiple environments.
**Date:** 2026-04-02
EOF

  # cust-b: 1 lesson highly similar to cust-a's first (RBAC centralisation).
  # NOTE: title + rule body must share most vocabulary to clear the 60% Jaccard
  # threshold (06-01 confirmed real-lesson scores are typically <10%; fixture
  # is intentionally engineered to exceed the threshold).
  cat > "$TEST_PORTFOLIO/cust-b/tasks/lessons.md" <<'EOF'
# Lessons Learned

## Lesson: Centralise RBAC role arrays in single source of truth
**Trigger:** Inline role arrays drifted between routes and components
**Mistake:** Hardcoded role list in different files instead of centralised module
**Rule:** Every RBAC role array must live in one centralised module. Routes and components import the array. Lint forbids inline role arrays. Centralised role array is single source of truth.
**Date:** 2026-04-05
EOF

  # cust-c: 1 anti-pattern lesson + 1 unrelated migration lesson
  cat > "$TEST_PORTFOLIO/cust-c/tasks/lessons.md" <<'EOF'
# Lessons Learned

## Lesson: Anti-pattern: don't hardcode secrets in source code
**Trigger:** API key was committed to git history
**Mistake:** Hardcoded the key inline instead of using env var
**Rule:** Anti-pattern: never hardcode secrets. Always use environment variables or a secret manager. Don't commit secrets to source.
**Date:** 2026-04-10

## Lesson: Always run migrations after push
**Trigger:** Schema drift in prod
**Mistake:** Forgot to run migrations after deploying code
**Rule:** Always run wrangler d1 migrations apply after pushing schema changes. Verify production schema matches repository schema.
**Date:** 2026-04-12
EOF

  # --- Assertion 1: scan returns >= 5 rows ---
  scan_out=$(promoter_scan_lessons "$TEST_PORTFOLIO")
  scan_count=$(printf '%s\n' "$scan_out" | grep -c . || true)
  scan_count=$(echo "$scan_count" | tr -d ' \n')
  assert_ge 5 "$scan_count" "scan emits >=5 lesson rows across 3 customers"

  # --- Assertion 2: each row has 4 tab-separated fields ---
  bad_rows=$(printf '%s\n' "$scan_out" | awk -F'\t' 'NF != 4' | grep -c . || true)
  bad_rows=$(echo "$bad_rows" | tr -d ' \n')
  assert_eq "0" "$bad_rows" "every scan row has exactly 4 tab-separated fields"

  # --- Assertion 3: anti-pattern row has severity=anti ---
  anti_rows=$(printf '%s\n' "$scan_out" | awk -F'\t' '$4=="anti"' | grep -c . || true)
  anti_rows=$(echo "$anti_rows" | tr -d ' \n')
  assert_ge 1 "$anti_rows" "anti-pattern lesson has severity=anti"

  # --- Assertion 4: clustering produces a cluster spanning cust-a + cust-b ---
  cluster_out=$(printf '%s\n' "$scan_out" | promoter_cluster_similar)
  # Find a cluster_id that includes BOTH cust-a and cust-b
  shared_cluster=$(printf '%s\n' "$cluster_out" \
    | awk -F'\t' '{ key=$1; cust[key]=cust[key]","$2 }
                  END { for (k in cust) print k"\t"cust[k] }' \
    | awk -F'\t' '$2 ~ /cust-a/ && $2 ~ /cust-b/ { print $1 }' | head -1)
  if [[ -n "$shared_cluster" ]]; then
    echo "  PASS cust-a + cust-b RBAC lessons cluster (cluster_id=$shared_cluster)"
    pass=$((pass + 1))
  else
    echo "  FAIL cust-a + cust-b RBAC lessons did NOT cluster (similarity < 60?)"
    echo "----- scan_out -----"; printf '%s\n' "$scan_out"
    echo "----- cluster_out -----"; printf '%s\n' "$cluster_out"
    fail=$((fail + 1))
  fi

  # --- Assertion 5: that cluster classifies as PROMOTE w/ universal-patterns route ---
  verdict_out=$(printf '%s\n' "$cluster_out" | promoter_classify_cluster)
  if [[ -n "$shared_cluster" ]]; then
    shared_verdict=$(printf '%s\n' "$verdict_out" | awk -F'\t' -v c="$shared_cluster" '$1==c { print $2 }')
    shared_route=$(printf '%s\n' "$verdict_out" | awk -F'\t' -v c="$shared_cluster" '$1==c { print $5 }')
    shared_custcount=$(printf '%s\n' "$verdict_out" | awk -F'\t' -v c="$shared_cluster" '$1==c { print $3 }')
    assert_eq "PROMOTE" "$shared_verdict" "RBAC cluster verdict=PROMOTE"
    assert_eq "universal-patterns" "$shared_route" "RBAC cluster route=universal-patterns"
    assert_eq "2" "$shared_custcount" "RBAC cluster customer_count=2"
  else
    fail=$((fail + 3))
    echo "  FAIL skipped 3 verdict assertions (no shared cluster)"
  fi

  # --- Assertion 6: lone anti-pattern with 1 customer → MEDIOCRE_KEPT_PER_CUSTOMER ---
  # Find cluster containing the anti-pattern (severity=anti) which has only cust-c
  anti_cluster=$(printf '%s\n' "$cluster_out" \
    | awk -F'\t' '$5=="anti" { print $1 }' | head -1)
  if [[ -n "$anti_cluster" ]]; then
    anti_verdict=$(printf '%s\n' "$verdict_out" | awk -F'\t' -v c="$anti_cluster" '$1==c { print $2 }')
    assert_eq "MEDIOCRE_KEPT_PER_CUSTOMER" "$anti_verdict" "single-customer anti-pattern → MEDIOCRE (count threshold honored)"
  else
    fail=$((fail + 1))
    echo "  FAIL no anti cluster found"
  fi

  # --- Assertion 7: add anti-pattern lessons to cust-a AND cust-b → re-run, verdict=PROMOTE w/ route=anti-patterns ---
  cat >> "$TEST_PORTFOLIO/cust-a/tasks/lessons.md" <<'EOF'

## Lesson: Anti-pattern: don't hardcode secrets in source code
**Trigger:** API key committed
**Mistake:** Hardcoded secret value inline
**Rule:** Anti-pattern: never hardcode secrets. Always use environment variables or a secret manager. Don't commit secrets to source.
**Date:** 2026-04-15
EOF
  cat >> "$TEST_PORTFOLIO/cust-b/tasks/lessons.md" <<'EOF'

## Lesson: Anti-pattern: don't hardcode secrets in source code
**Trigger:** Token leaked in repo
**Mistake:** Hardcoded the secret token inline
**Rule:** Anti-pattern: never hardcode secrets. Always use environment variables or a secret manager. Don't commit secrets to source.
**Date:** 2026-04-16
EOF
  # Re-scan + cluster + classify
  scan_out2=$(promoter_scan_lessons "$TEST_PORTFOLIO")
  cluster_out2=$(printf '%s\n' "$scan_out2" | promoter_cluster_similar)
  verdict_out2=$(printf '%s\n' "$cluster_out2" | promoter_classify_cluster)
  # Find cluster that contains rows with severity=anti AND >=2 distinct customers
  anti_promote=$(printf '%s\n' "$cluster_out2" \
    | awk -F'\t' '$5=="anti" { print $1 }' | sort -u \
    | while IFS= read -r cid; do
        [[ -z "$cid" ]] && continue
        cc=$(awk -F'\t' -v c="$cid" '$1==c { print $2 }' <<< "$cluster_out2" | sort -u | wc -l | tr -d ' ')
        if [[ "$cc" -ge 2 ]]; then echo "$cid"; break; fi
      done)
  if [[ -n "$anti_promote" ]]; then
    anti_v=$(printf '%s\n' "$verdict_out2" | awk -F'\t' -v c="$anti_promote" '$1==c { print $2 }')
    anti_r=$(printf '%s\n' "$verdict_out2" | awk -F'\t' -v c="$anti_promote" '$1==c { print $5 }')
    assert_eq "PROMOTE" "$anti_v" "multi-customer anti-pattern verdict=PROMOTE"
    assert_eq "anti-patterns" "$anti_r" "multi-customer anti-pattern route=anti-patterns"
  else
    fail=$((fail + 2))
    echo "  FAIL no multi-customer anti-pattern cluster found after seeding"
  fi

  # --- Assertion 8: promoter_run --dry-run prints verdicts TSV ---
  dry_out=$(promoter_run --dry-run 2>/dev/null)
  dry_lines=$(printf '%s\n' "$dry_out" | grep -c . || true)
  dry_lines=$(echo "$dry_lines" | tr -d ' \n')
  assert_ge 1 "$dry_lines" "promoter_run --dry-run emits verdicts TSV"

  # --- Assertion 9: promoter_run --full does NOT mutate canary universal-patterns.md ---
  promoter_run --full >/dev/null 2>&1
  CANARY_AFTER=$(md5 -q "$TEST_VAULT/lessons/universal-patterns.md" 2>/dev/null \
    || md5sum "$TEST_VAULT/lessons/universal-patterns.md" 2>/dev/null | awk '{print $1}')
  assert_eq "$CANARY_BEFORE" "$CANARY_AFTER" "promoter_run --full does NOT mutate canary universal-patterns.md (no apply)"

  # --- Assertion 10: real-vault md5 unchanged before/after self-test ---
  if [[ -n "$REAL_MD5_BEFORE" ]]; then
    REAL_MD5_AFTER=$(md5 -q "$REAL_VAULT_FILE" 2>/dev/null \
      || md5sum "$REAL_VAULT_FILE" 2>/dev/null | awk '{print $1}')
    assert_eq "$REAL_MD5_BEFORE" "$REAL_MD5_AFTER" "real-vault universal-patterns.md md5 unchanged"
  else
    echo "  PASS real-vault file did not exist before test (no mutation possible)"
    pass=$((pass + 1))
  fi

  # --- Assertion 11: section sentinel for 06-03 present ---
  sentinel_open=$(grep -c '^# === SECTION: apply-pending (Plan 06-03) ===' "$0" || true)
  sentinel_open=$(echo "$sentinel_open" | tr -d ' \n')
  assert_eq "1" "$sentinel_open" "06-03 sentinel section open marker present"
  sentinel_close=$(grep -c '^# === END SECTION: apply-pending ===' "$0" || true)
  sentinel_close=$(echo "$sentinel_close" | tr -d ' \n')
  assert_eq "1" "$sentinel_close" "06-03 sentinel section close marker present"

  # --- Assertion 12: bash-3 compat scan in lib region (above guard) ---
  guard_line=$(awk '/^if[[:space:]]+\[\[[[:space:]]+"\$\{BASH_SOURCE\[0\]\}"[[:space:]]+==[[:space:]]+"\$\{0\}"[[:space:]]+\]\];[[:space:]]+then/ { print NR; exit }' "$0")
  if [[ -z "$guard_line" ]]; then
    guard_line=$(grep -n 'BASH_SOURCE\[0\]' "$0" | head -1 | cut -d: -f1)
  fi
  if [[ -n "$guard_line" ]]; then
    bad=$(head -n "$guard_line" "$0" \
      | grep -v '^[[:space:]]*#' \
      | grep -cE '(^|[[:space:]])(declare -A|mapfile|readarray)([[:space:]]|$)' || true)
    bad=$(echo "$bad" | tr -d ' \n')
    assert_eq "0" "$bad" "bash-3 compat: 0 declare-A/mapfile/readarray in lib region"
  else
    echo "  FAIL bash-3 compat scan: could not locate guard line"
    fail=$((fail + 1))
  fi

  # --- Assertion 13: no `read -p` in lib region ---
  if [[ -n "$guard_line" ]]; then
    rp_hits=$(head -n "$guard_line" "$0" \
      | grep -v '^[[:space:]]*#' \
      | grep -cE '(^|[^A-Za-z_])read[[:space:]]+-p[[:space:]]' || true)
    rp_hits=$(echo "$rp_hits" | tr -d ' \n')
    assert_eq "0" "$rp_hits" "no 'read -p' in lib region"
  else
    fail=$((fail + 1))
  fi

  # --- Assertion 14: $VAULT_PATH was redirected to tmp during test ---
  case "$VAULT_PATH" in
    /tmp/*|/var/folders/*) vp_isolated=1 ;;
    *)                     vp_isolated=0 ;;
  esac
  assert_eq "1" "$vp_isolated" "VAULT_PATH redirected to tmp dir during self-test (real-vault isolation)"

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "ALL LESSON-PROMOTER TESTS PASSED ($pass/$pass)"
    echo ""
    echo "✅ ALL LESSON-PROMOTER TESTS PASSED"
    exit 0
  else
    echo "$fail/$((pass+fail)) tests failed"
    exit 1
  fi
fi
