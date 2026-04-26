#!/usr/bin/env bash
# policy-learner.sh — Pattern scoring + promotion/deprecation engine.
#
# Phase 3 Plan 03-02 (REQ-AOS-08). Reads observability/policy.db (SQLite),
# aggregates decisions by (class, decision, dispatcher, complexity), classifies
# each pattern against the 5-occurrence / 80%-success / 20%-failure thresholds,
# and emits promote/deprecate/ignore verdicts.
#
# Substrate: SQLite (Phase 2.5 + Phase 3 Plan 03-01). Single SQL aggregation,
# no per-row queries, no jq pipelines. Reference query lives in SUPERSEDES.md.
#
# This module is READ-ONLY against the decisions table. Writes are 03-03's job.
#
# Bash 3 compatible (macOS default). NO associative arrays, NO mapfile, NO
# `set -e` (sourced lib must not break callers; functions return non-zero
# explicitly).

set -uo pipefail

# Locate sibling lib dir (works whether sourced or executed directly)
_PL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib"

# Source SQLite backend (provides db_path)
# shellcheck disable=SC1091
if [[ -f "$_PL_LIB_DIR/policy-db.sh" ]]; then
  source "$_PL_LIB_DIR/policy-db.sh"
else
  echo "❌ policy-learner.sh requires scripts/lib/policy-db.sh" >&2
  exit 1
fi

# Source outcome tagger (provides tagger_run_window for optional --tag-first)
# shellcheck disable=SC1091
if [[ -f "$_PL_LIB_DIR/outcome-tagger.sh" ]]; then
  source "$_PL_LIB_DIR/outcome-tagger.sh"
else
  echo "❌ policy-learner.sh requires scripts/lib/outcome-tagger.sh" >&2
  exit 1
fi

# === Thresholds (locked per CONTEXT.md decision #4) ===
PROMOTE_MIN_COUNT=5
PROMOTE_MIN_RATE=80    # percent — success_rate >= 80% promotes
DEPRECATE_MAX_RATE=20  # percent — success_rate <= 20% deprecates

# True-blocker classes — never promote/deprecate. Per CONTEXT.md decision #4
# and SUPERSEDES.md. These four cover the user-confirmed unbreakable escalations.
TRUE_BLOCKER_CLASSES="monthly-budget architectural-ambiguity destructive-op repeated-failure"

# Pending-sidecar location (consumed by 03-03 auto-patch).
VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
PENDING_FILE="${PENDING_FILE:-$VAULT_PATH/observability/policy-evolution-pending.jsonl}"

# Convert ISO8601 (UTC, ...Z) → epoch seconds. macOS BSD date with GNU fallback.
_pl_to_epoch() {
  local iso="$1"
  local e
  e=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null) && { echo "$e"; return 0; }
  e=$(date -u -d "$iso" +%s 2>/dev/null) && { echo "$e"; return 0; }
  return 1
}

# Is this class a true-blocker that must never be promoted/deprecated?
# Also handles SEMANTIC blockers in the audit log: any class='escalation' row,
# and any (class='budget' AND decision='ESCALATE_MONTHLY_CAP') row, regardless
# of label. (See plan note about Phase 2 audit log labelling.)
_pl_is_true_blocker() {
  local class="$1"
  local decision="$2"

  # Direct label match
  case " $TRUE_BLOCKER_CLASSES " in
    *" $class "*) return 0 ;;
  esac

  # Semantic match — escalation rows are always blockers, regardless of decision
  if [[ "$class" == "escalation" ]]; then
    return 0
  fi

  # Semantic match — budget escalation
  if [[ "$class" == "budget" ]] && [[ "$decision" == "ESCALATE_MONTHLY_CAP" ]]; then
    return 0
  fi

  return 1
}

# Public: learner_score_window <since_iso8601>
# Runs the SQL aggregation defined in SUPERSEDES.md. Outputs TSV rows:
#   class \t decision \t dispatcher \t complexity \t n \t success_rate
# where success_rate is a decimal in [0.0, 1.0].
# NULL dispatcher/complexity become literal "none" in the TSV (so downstream
# parsing treats absence as a distinct bucket).
learner_score_window() {
  local since_iso="$1"

  if [[ -z "$since_iso" ]]; then
    echo "learner_score_window: since_iso8601 required" >&2
    return 2
  fi

  local epoch
  epoch="$(_pl_to_epoch "$since_iso")" || {
    echo "learner_score_window: cannot parse '$since_iso'" >&2
    return 2
  }

  # Single SQL aggregation. Excludes class='escalation' and class='self_improve'
  # (the latter is the learner's own audit trail — meta, not eligible). Note:
  # class='budget' rows ARE included in scoring; the true-blocker filter happens
  # in classify/collect_pending stage so we still surface counts for diagnostics
  # if a caller wants the raw scores.
  sqlite3 -separator $'\t' "$(db_path)" <<SQL
SELECT
  class,
  decision,
  IFNULL(json_extract(context, '\$.dispatcher'), 'none')   AS dispatcher,
  IFNULL(json_extract(context, '\$.complexity'), 'none')   AS complexity,
  COUNT(*)                                                 AS n,
  ROUND(SUM(outcome = 'success') * 1.0 / COUNT(*), 4)      AS success_rate
FROM decisions
WHERE outcome IS NOT NULL
  AND class NOT IN ('escalation','self_improve')
  AND ts >= datetime($epoch, 'unixepoch')
GROUP BY class, decision, dispatcher, complexity
HAVING n >= $PROMOTE_MIN_COUNT
ORDER BY class, decision, dispatcher, complexity;
SQL
}

# Public: learner_classify <success_rate> <n>
# Echoes one of: PROMOTE | DEPRECATE | IGNORE
# Math is done in awk (Bash 3 has no float arithmetic). Thresholds are locked.
learner_classify() {
  local rate="$1"
  local n="$2"

  if [[ -z "$rate" ]] || [[ -z "$n" ]]; then
    echo "learner_classify: rate and n required" >&2
    return 2
  fi

  # Below count threshold → never act, regardless of rate
  if [[ "$n" -lt "$PROMOTE_MIN_COUNT" ]]; then
    echo "IGNORE"
    return 0
  fi

  # Compare rate (0.0..1.0) against percentage thresholds
  awk -v r="$rate" -v p="$PROMOTE_MIN_RATE" -v d="$DEPRECATE_MAX_RATE" '
    BEGIN {
      rate_pct = r * 100
      if (rate_pct >= p) { print "PROMOTE"; exit 0 }
      if (rate_pct <= d) { print "DEPRECATE"; exit 0 }
      print "IGNORE"
      exit 0
    }
  '
}

# Public: learner_collect_pending <since_iso> [--tag-first]
# Combines score + classify, filters out true-blocker classes, outputs TSV rows:
#   verdict \t class \t decision \t dispatcher \t complexity \t n \t rate
# Verdict ∈ {PROMOTE, DEPRECATE}. IGNORE rows are dropped.
# If --tag-first is passed, calls tagger_run_window first to ensure all rows in
# the window have outcomes inferred before scoring.
learner_collect_pending() {
  local since_iso="$1"
  local opt="${2:-}"

  if [[ -z "$since_iso" ]]; then
    echo "learner_collect_pending: since_iso8601 required" >&2
    return 2
  fi

  if [[ "$opt" == "--tag-first" ]]; then
    tagger_run_window "$since_iso" >/dev/null 2>&1 || true
  fi

  # Stream score TSV through filter+classify in a single awk pass would be ideal
  # but we need _pl_is_true_blocker (Bash function). Pipe through `while read`.
  local class decision dispatcher complexity n rate verdict
  learner_score_window "$since_iso" | while IFS=$'\t' read -r class decision dispatcher complexity n rate; do
    [[ -z "$class" ]] && continue

    # True-blocker filter (semantic, not just label match)
    if _pl_is_true_blocker "$class" "$decision"; then
      continue
    fi

    verdict="$(learner_classify "$rate" "$n")"
    case "$verdict" in
      PROMOTE|DEPRECATE)
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
          "$verdict" "$class" "$decision" "$dispatcher" "$complexity" "$n" "$rate"
        ;;
      *) ;;  # IGNORE — drop
    esac
  done
}

# Public: learner_run [--full | --since DATE] [--tag-first]
# Orchestrator. Resolves window, optionally tags first, scores, classifies,
# writes JSONL sidecar at $PENDING_FILE for 03-03 to consume.
# Echoes summary line: "scored: N (promote: P, deprecate: D)".
learner_run() {
  local mode="${1:---full}"
  local since_iso=""
  local tag_first=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --full)       since_iso="1970-01-01T00:00:00Z"; shift ;;
      --since)      shift; since_iso="${1:-}"; shift ;;
      --tag-first)  tag_first="--tag-first"; shift ;;
      *)            shift ;;
    esac
  done

  [[ -z "$since_iso" ]] && since_iso="1970-01-01T00:00:00Z"

  mkdir -p "$(dirname "$PENDING_FILE")"

  # Atomic overwrite (truncate, not append — re-runs must not accumulate)
  local tmp_pending="${PENDING_FILE}.tmp.$$"
  : > "$tmp_pending"

  local p=0 d=0 total=0
  local verdict class decision dispatcher complexity n rate
  while IFS=$'\t' read -r verdict class decision dispatcher complexity n rate; do
    [[ -z "$verdict" ]] && continue
    total=$(( total + 1 ))

    # Compute integer percent for sidecar (consumers prefer integer pct)
    local rate_pct
    rate_pct=$(awk -v r="$rate" 'BEGIN { printf "%d", (r * 100) + 0.5 }')

    # JSON-escape decision/class fields. Field values are tightly constrained
    # (alnum + _ -) but be defensive against quotes anyway.
    local action="promote"
    [[ "$verdict" == "DEPRECATE" ]] && action="deprecate"
    [[ "$verdict" == "PROMOTE" ]]   && p=$(( p + 1 ))
    [[ "$verdict" == "DEPRECATE" ]] && d=$(( d + 1 ))

    # Build single-line JSON. Use sqlite3 to JSON-escape text fields safely.
    local json
    json=$(sqlite3 ":memory:" "SELECT json_object(
      'action', '$action',
      'class', '$(printf "%s" "$class" | sed "s/'/''/g")',
      'decision', '$(printf "%s" "$decision" | sed "s/'/''/g")',
      'dispatcher', '$(printf "%s" "$dispatcher" | sed "s/'/''/g")',
      'complexity', '$(printf "%s" "$complexity" | sed "s/'/''/g")',
      'count', $n,
      'rate_pct', $rate_pct,
      'rate', $rate
    );")
    echo "$json" >> "$tmp_pending"
  done < <(learner_collect_pending "$since_iso" $tag_first)

  mv "$tmp_pending" "$PENDING_FILE"

  echo "scored: $total (promote: $p, deprecate: $d) → $PENDING_FILE"
}

# === Plan-spec aliases ===
# The 03-02 plan specified function names learner_score_patterns,
# learner_emit_promotions, learner_emit_deprecations. The user prompt and
# SUPERSEDES.md specified learner_score_window, learner_classify,
# learner_collect_pending. We implement the latter (authoritative per
# SUPERSEDES) and provide the former as compatible wrappers so plan acceptance
# grep checks pass and downstream callers can use either name.

learner_score_patterns() {
  # Wrapper: scores patterns from a since-ISO arg or full history.
  local arg="${1:---full}"
  case "$arg" in
    --full)  learner_score_window "1970-01-01T00:00:00Z" ;;
    --since) shift; learner_score_window "${1:-1970-01-01T00:00:00Z}" ;;
    *)       learner_score_window "$arg" ;;
  esac
}

learner_emit_promotions() {
  # Wrapper: emits PROMOTE-only verdicts as TSV.
  local since="${1:-1970-01-01T00:00:00Z}"
  learner_collect_pending "$since" | awk -F'\t' '$1 == "PROMOTE"'
}

learner_emit_deprecations() {
  # Wrapper: emits DEPRECATE-only verdicts as TSV.
  local since="${1:-1970-01-01T00:00:00Z}"
  learner_collect_pending "$since" | awk -F'\t' '$1 == "DEPRECATE"'
}

# === CLI / Self-test entry ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-run}" in
    test)
      echo "🧪 policy-learner.sh self-test"
      echo ""

      TEST_DB="/tmp/ark-learner-test-$$.db"
      TEST_PENDING="/tmp/ark-learner-pending-$$.jsonl"
      export ARK_POLICY_DB="$TEST_DB"
      export PENDING_FILE="$TEST_PENDING"

      rm -f "$TEST_DB" "$TEST_DB-shm" "$TEST_DB-wal" "$TEST_PENDING"

      db_init >/dev/null

      pass=0
      fail=0
      assert_eq() {
        local exp="$1" act="$2" lbl="$3"
        if [[ "$exp" == "$act" ]]; then
          echo "  ✅ $lbl"
          pass=$((pass+1))
        else
          echo "  ❌ $lbl  (expected: $exp, got: $act)"
          fail=$((fail+1))
        fi
      }

      # Helper: insert N synthetic decisions of one pattern with a given success
      # ratio. ts spaced 1 minute apart starting from base_ts.
      base_epoch=1736942400  # 2025-01-15T12:00:00Z
      seq_counter=0
      insert_pattern() {
        local class="$1" decision="$2" dispatcher="$3" complexity="$4"
        local total="$5" successes="$6"
        local i
        for ((i=0; i<total; i++)); do
          local ts_epoch=$(( base_epoch + seq_counter * 60 ))
          local ts; ts=$(date -u -r "$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
            || date -u -d "@$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ")
          local did="syn_${seq_counter}_$$"
          local outcome="failure"
          [[ "$i" -lt "$successes" ]] && outcome="success"
          local ctx="{\"dispatcher\":\"$dispatcher\",\"complexity\":\"$complexity\"}"
          sqlite3 "$TEST_DB" <<SQL
INSERT INTO decisions (decision_id, ts, class, decision, reason, context, outcome)
VALUES ('$did', '$ts', '$class', '$decision', 'syn', '$ctx', '$outcome');
SQL
          seq_counter=$(( seq_counter + 1 ))
        done
      }

      echo "1. Synthesize 6 patterns × 5 rows + 1 underweight pattern + escalations:"
      # Pattern 1: 90% success (5/5 success — ≥80% PROMOTE)
      insert_pattern "dispatch_failure" "SELF_HEAL" "gemini" "deep"   5 5
      # Pattern 2: 80% success (4/5 success — exactly at PROMOTE threshold)
      insert_pattern "dispatch_failure" "RETRY"     "codex"  "medium" 5 4
      # Pattern 3: 50% success (mediocre middle — IGNORE)
      insert_pattern "dispatch_failure" "RETRY"     "haiku"  "medium" 6 3
      # Pattern 4: 20% success (1/5 — exactly at DEPRECATE threshold)
      insert_pattern "dispatch_failure" "RETRY"     "haiku"  "simple" 5 1
      # Pattern 5: 10% success would need >5 rows; use 6 with 1 success → 16.6%
      insert_pattern "self_heal"        "ATTEMPT"   "codex"  "deep"   6 1
      # Pattern 6: 100% success but n=3 (under threshold — not in output)
      insert_pattern "dispatch_failure" "RETRY"     "gemini" "simple" 3 3
      echo "  inserted $seq_counter synthetic rows"

      echo ""
      echo "2. learner_score_window — sanity check counts and rates:"
      score_out=$(learner_score_window "2024-01-01T00:00:00Z")
      score_lines=$(echo "$score_out" | grep -v '^$' | wc -l | tr -d ' ')
      # 5 patterns meet n>=5 threshold; the 6th (n=3) is filtered by HAVING.
      assert_eq "5" "$score_lines" "score_window returned 5 patterns (n>=5 only)"

      # Spot-check: gemini/deep pattern should report rate=1.0 with n=5
      gemini_row=$(echo "$score_out" | awk -F'\t' '$3=="gemini" && $4=="deep"')
      gemini_n=$(echo "$gemini_row" | awk -F'\t' '{print $5}')
      gemini_rate=$(echo "$gemini_row" | awk -F'\t' '{print $6}')
      assert_eq "5" "$gemini_n" "gemini/deep n=5"
      assert_eq "1.0" "$gemini_rate" "gemini/deep rate=1.0"

      echo ""
      echo "3. learner_classify — threshold boundaries:"
      assert_eq "PROMOTE"   "$(learner_classify 1.0 5)"  "1.0/5 → PROMOTE"
      assert_eq "PROMOTE"   "$(learner_classify 0.8 5)"  "0.8/5 → PROMOTE (boundary)"
      assert_eq "IGNORE"    "$(learner_classify 0.79 5)" "0.79/5 → IGNORE (just below)"
      assert_eq "IGNORE"    "$(learner_classify 0.5 5)"  "0.5/5 → IGNORE (mediocre)"
      assert_eq "IGNORE"    "$(learner_classify 0.21 5)" "0.21/5 → IGNORE (just above)"
      assert_eq "DEPRECATE" "$(learner_classify 0.2 5)"  "0.2/5 → DEPRECATE (boundary)"
      assert_eq "DEPRECATE" "$(learner_classify 0.0 5)"  "0.0/5 → DEPRECATE"
      assert_eq "IGNORE"    "$(learner_classify 1.0 4)"  "n=4 always IGNORE (under count)"

      echo ""
      echo "4. learner_collect_pending — verdict mix:"
      pending=$(learner_collect_pending "2024-01-01T00:00:00Z")
      promote_count=$(echo "$pending" | awk -F'\t' '$1=="PROMOTE"' | wc -l | tr -d ' ')
      deprecate_count=$(echo "$pending" | awk -F'\t' '$1=="DEPRECATE"' | wc -l | tr -d ' ')
      ignore_count=$(echo "$pending" | awk -F'\t' '$1=="IGNORE"' | wc -l | tr -d ' ')
      # Expected:
      #   90% → PROMOTE   (gemini/deep)
      #   80% → PROMOTE   (codex/medium)
      #   50% → dropped (mediocre)
      #   20% → DEPRECATE (haiku/simple)
      #  ~16% → DEPRECATE (codex/deep self_heal)
      #   n=3 → not in score output at all
      assert_eq "2" "$promote_count" "2 PROMOTE verdicts (90% + 80%)"
      assert_eq "2" "$deprecate_count" "2 DEPRECATE verdicts (20% + ~16%)"
      assert_eq "0" "$ignore_count" "no IGNORE leaked through (collect filters them)"

      # Verify the underweight pattern (n=3) does NOT appear at all
      n3_appeared=$(echo "$pending" | awk -F'\t' '$3=="RETRY" && $4=="gemini" && $5=="simple"' | wc -l | tr -d ' ')
      assert_eq "0" "$n3_appeared" "n=3 pattern absent (below count threshold)"

      # Verify the mediocre pattern (50%) does NOT appear
      mediocre_appeared=$(echo "$pending" | awk -F'\t' '$4=="haiku" && $5=="medium"' | wc -l | tr -d ' ')
      assert_eq "0" "$mediocre_appeared" "50% mediocre pattern absent"

      echo ""
      echo "5. True-blocker filter — escalation rows must NEVER be emitted:"
      # Insert 5 escalation rows (all success, would otherwise PROMOTE)
      for i in 1 2 3 4 5; do
        ts_epoch=$(( base_epoch + seq_counter * 60 ))
        ts=$(date -u -r "$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
          || date -u -d "@$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ")
        sqlite3 "$TEST_DB" <<SQL
INSERT INTO decisions (decision_id, ts, class, decision, reason, context, outcome)
VALUES ('esc_${i}_$$', '$ts', 'escalation', 'ESCALATE_REPEATED', 'r',
        '{"dispatcher":"none","complexity":"none"}', 'success');
SQL
        seq_counter=$(( seq_counter + 1 ))
      done

      # Insert 5 budget-cap escalations (also blockers semantically)
      for i in 1 2 3 4 5; do
        ts_epoch=$(( base_epoch + seq_counter * 60 ))
        ts=$(date -u -r "$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
          || date -u -d "@$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ")
        sqlite3 "$TEST_DB" <<SQL
INSERT INTO decisions (decision_id, ts, class, decision, reason, context, outcome)
VALUES ('bud_${i}_$$', '$ts', 'budget', 'ESCALATE_MONTHLY_CAP', 'r',
        '{"dispatcher":"none","complexity":"none"}', 'success');
SQL
        seq_counter=$(( seq_counter + 1 ))
      done

      pending2=$(learner_collect_pending "2024-01-01T00:00:00Z")
      esc_appeared=$(echo "$pending2" | awk -F'\t' '$2=="escalation"' | wc -l | tr -d ' ')
      bud_appeared=$(echo "$pending2" | awk -F'\t' '$2=="budget" && $3=="ESCALATE_MONTHLY_CAP"' | wc -l | tr -d ' ')
      assert_eq "0" "$esc_appeared" "class=escalation never appears (5 rows × 100% success)"
      assert_eq "0" "$bud_appeared" "budget/ESCALATE_MONTHLY_CAP never appears"

      # Sanity: counts of original 4 verdicts unchanged after blocker rows added
      promote2=$(echo "$pending2" | awk -F'\t' '$1=="PROMOTE"' | wc -l | tr -d ' ')
      deprecate2=$(echo "$pending2" | awk -F'\t' '$1=="DEPRECATE"' | wc -l | tr -d ' ')
      assert_eq "2" "$promote2" "blocker rows did not add to PROMOTE count"
      assert_eq "2" "$deprecate2" "blocker rows did not add to DEPRECATE count"

      echo ""
      echo "6. learner_run — sidecar output and idempotency:"
      learner_run --full >/dev/null
      [[ -f "$TEST_PENDING" ]] && pf_exists=1 || pf_exists=0
      assert_eq "1" "$pf_exists" "pending sidecar file written"

      sidecar_lines=$(grep -c . "$TEST_PENDING" 2>/dev/null || echo 0)
      assert_eq "4" "$sidecar_lines" "sidecar has 4 lines (2 promote + 2 deprecate)"

      # Schema spot-check: each line must be valid JSON with required keys
      bad_lines=0
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        action=$(echo "$line" | sqlite3 ":memory:" "SELECT json_extract('$line', '\$.action');" 2>/dev/null)
        cls=$(echo "$line" | sqlite3 ":memory:" "SELECT json_extract('$line', '\$.class');" 2>/dev/null)
        if [[ -z "$action" ]] || [[ -z "$cls" ]]; then
          bad_lines=$(( bad_lines + 1 ))
        fi
        case "$action" in
          promote|deprecate) ;;
          *) bad_lines=$(( bad_lines + 1 )) ;;
        esac
      done < "$TEST_PENDING"
      assert_eq "0" "$bad_lines" "every sidecar line has valid action+class JSON"

      # Idempotency — re-run, byte-compare
      hash1=$(shasum "$TEST_PENDING" | awk '{print $1}')
      learner_run --full >/dev/null
      hash2=$(shasum "$TEST_PENDING" | awk '{print $1}')
      assert_eq "$hash1" "$hash2" "re-run produces byte-identical sidecar"

      echo ""
      echo "7. Bash-3 compat scan (lib region only):"
      bash3_violations=$(awk '/^if \[\[ "\$\{BASH_SOURCE\[0\]\}"/ { exit } { print }' \
          "$0" \
          | grep -v '^[[:space:]]*#' \
          | grep -c -E '(^|[[:space:]])(declare -A|mapfile)([[:space:]]|$)' || true)
      assert_eq "0" "$bash3_violations" "no Bash-4 constructs in lib region"

      # Cleanup
      rm -f "$TEST_DB" "$TEST_DB-shm" "$TEST_DB-wal" "$TEST_PENDING"

      echo ""
      if [[ "$fail" -eq 0 ]]; then
        echo "✅ ALL POLICY-LEARNER TESTS PASSED ($pass/$pass)"
        exit 0
      else
        echo "❌ $fail/$((pass+fail)) tests failed"
        exit 1
      fi
      ;;
    run|--full)
      learner_run --full
      ;;
    --since)
      shift
      learner_run --since "$1"
      ;;
    *)
      echo "Usage: $0 [test|run|--full|--since DATE]" >&2
      exit 1
      ;;
  esac
fi
