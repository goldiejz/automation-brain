#!/usr/bin/env bash
# lesson-similarity.sh — Heuristic similarity primitive for cross-customer lessons.
#
# Phase 6 Plan 06-01 (REQ-AOS-32). Pure Bash 3 + awk + coreutils. No ML, no
# external HTTP, no associative arrays, no mapfile/readarray, no `${var,,}`.
#
# Locked decision (CONTEXT.md, D-SIMILARITY): Jaccard token-overlap on
# (title + rule body) tokens, lowercased, alphanumerics only, stop-words
# removed. Returns integer 0..100.
#
# Public API:
#   lesson_tokenize "<text>"          → one token per line on stdout
#   lesson_extract_body "<lesson.md>" → title + rule body text on stdout
#   lesson_similarity "<a.md>" "<b.md>" → integer 0..100 on stdout
#
# This module is sourceable. It does NOT set -e at top level (would break
# callers). `set -uo pipefail` is safe — `pipefail` does not propagate to
# the caller, and `-u` only matters within this file's own functions.
#
# Audit discipline: pure module — no audit log writes. Pattern detection
# logs come from 06-02/06-03, not from this primitive.

set -uo pipefail

# === Stop-word list (LOCKED) ===
# 50 most common English function words + lesson-formatting noise
# (trigger/mistake/rule/date/lesson). Space-padded both ends so callers
# can do `*" $tok "*` lookups without word-boundary surprises.
LESSON_STOP_WORDS=" a an and are as at be but by do for from has have he her him his i if in is it its not of on or our she that the their them they this to was we were will with you your trigger mistake rule date lesson "

# === lesson_tokenize "<text>" ===
# Lowercase → strip non-alphanumeric → split on whitespace → drop stop-words
# and tokens of length < 2. Emits one token per line. Does NOT sort -u —
# the Jaccard step decides.
lesson_tokenize() {
  local text="${1:-}"
  [[ -z "$text" ]] && return 0

  printf '%s\n' "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9\n' ' ' \
    | tr -s ' ' '\n' \
    | awk -v sw="$LESSON_STOP_WORDS" '
        NF == 0 { next }
        length($0) < 2 { next }
        { if (index(sw, " " $0 " ") == 0) print $0 }
      '
}

# === lesson_extract_body "<lesson.md>" ===
# Extracts the comparable body of a lesson file:
#   Format A (strategix convention, `## Lesson: <title>`):
#     emit the title text + the **Rule:** field content (until next
#     **Field:** marker or blank line).
#   Format B (plain `# Heading`):
#     emit the first heading text + the first non-blank paragraph after it.
#
# If file missing or empty: emit nothing (caller's Jaccard yields 0).
lesson_extract_body() {
  local file="${1:-}"

  if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
    echo "lesson-similarity: file not found: ${file:-<empty>}" >&2
    return 0
  fi
  [[ ! -s "$file" ]] && return 0

  # Format A detection (case-insensitive — tolerate uppercase variants)
  if grep -qi '^## lesson:' "$file" 2>/dev/null; then
    awk '
      BEGIN { in_block = 0; in_rule = 0; emitted_title = 0 }
      # First ## Lesson: line opens block (case-insensitive)
      tolower($0) ~ /^## lesson:/ {
        if (in_block == 1) { exit }   # only first block
        in_block = 1
        title = $0
        sub(/^##[[:space:]]*[Ll][Ee][Ss][Ss][Oo][Nn]:[[:space:]]*/, "", title)
        if (length(title) > 0 && emitted_title == 0) {
          print title
          emitted_title = 1
        }
        next
      }
      # Next ## heading closes the block
      in_block == 1 && /^## / { exit }
      # Within the block, capture **Rule:** content (case-insensitive)
      in_block == 1 && tolower($0) ~ /^\*\*rule:\*\*/ {
        in_rule = 1
        line = $0
        sub(/^\*\*[Rr][Uu][Ll][Ee]:\*\*[[:space:]]*/, "", line)
        if (length(line) > 0) print line
        next
      }
      # End rule on next **Field:** marker or blank line
      in_rule == 1 && /^\*\*[A-Za-z]+:\*\*/ { in_rule = 0; next }
      in_rule == 1 && /^[[:space:]]*$/ { in_rule = 0; next }
      in_rule == 1 { print $0; next }
    ' "$file"
    return 0
  fi

  # Format B: plain `# Heading` + first paragraph
  if grep -q '^# ' "$file" 2>/dev/null; then
    awk '
      BEGIN { found_heading = 0; in_para = 0; printed_para = 0 }
      found_heading == 0 && /^# / {
        line = $0
        sub(/^#[[:space:]]+/, "", line)
        print line
        found_heading = 1
        next
      }
      found_heading == 1 && printed_para == 0 && /^[[:space:]]*$/ {
        if (in_para == 1) { exit }
        next
      }
      found_heading == 1 && printed_para == 0 && /^[^[:space:]]/ {
        # Skip subsequent headings — only first paragraph
        if ($0 ~ /^#/) { exit }
        print $0
        in_para = 1
        next
      }
    ' "$file"
    return 0
  fi

  # Neither format — emit whole file as a fallback so similarity is still
  # computable. (Edge case: lessons without any heading.)
  cat "$file"
}

# === lesson_similarity "<a.md>" "<b.md>" ===
# Jaccard token-overlap: |A ∩ B| / |A ∪ B| × 100, integer division.
# Returns 0 (not error) when union is empty.
lesson_similarity() {
  local a="${1:-}"
  local b="${2:-}"
  local body_a body_b
  local tmp_a tmp_b inter union

  body_a=$(lesson_extract_body "$a" 2>/dev/null)
  body_b=$(lesson_extract_body "$b" 2>/dev/null)

  if [[ -z "$body_a" ]] || [[ -z "$body_b" ]]; then
    echo 0
    return 0
  fi

  tmp_a=$(mktemp -t lesson-sim.XXXXXX)
  tmp_b=$(mktemp -t lesson-sim.XXXXXX)
  # Cleanup on return (subshell-scoped — safe even if multiple callers)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_a' '$tmp_b'" RETURN 2>/dev/null || true

  printf '%s\n' "$body_a" | lesson_tokenize "$(cat)" | sort -u > "$tmp_a"
  printf '%s\n' "$body_b" | lesson_tokenize "$(cat)" | sort -u > "$tmp_b"

  # Re-tokenise: the pipe-with-cat dance above is awkward. Do it cleanly:
  lesson_tokenize "$body_a" | sort -u > "$tmp_a"
  lesson_tokenize "$body_b" | sort -u > "$tmp_b"

  inter=$(comm -12 "$tmp_a" "$tmp_b" | wc -l | tr -d ' ')
  union=$(cat "$tmp_a" "$tmp_b" | sort -u | wc -l | tr -d ' ')

  rm -f "$tmp_a" "$tmp_b"

  awk -v i="$inter" -v u="$union" 'BEGIN {
    if (u == 0) { print 0 } else { printf "%d\n", (i * 100) / u }
  }'
}

# === CLI / Self-test ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    tokenize)
      shift
      lesson_tokenize "$*"
      exit 0
      ;;
    extract)
      lesson_extract_body "${2:-}"
      exit 0
      ;;
    similarity)
      lesson_similarity "${2:-}" "${3:-}"
      exit 0
      ;;
    test)
      : # fall through to test block below
      ;;
    "")
      echo "Usage: $0 test | tokenize <text> | extract <lesson.md> | similarity <a> <b>" >&2
      exit 1
      ;;
    *)
      echo "Usage: $0 test | tokenize <text> | extract <lesson.md> | similarity <a> <b>" >&2
      exit 1
      ;;
  esac

  # ---- Self-test ----
  echo "lesson-similarity.sh self-test"
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
  assert_range() {
    local lo="$1" hi="$2" actual="$3" label="$4"
    if [[ "$actual" =~ ^[0-9]+$ ]] && [[ "$actual" -ge "$lo" ]] && [[ "$actual" -le "$hi" ]]; then
      echo "  PASS $label  (got $actual, expected ${lo}..${hi})"
      pass=$((pass + 1))
    else
      echo "  FAIL $label  (got '$actual', expected ${lo}..${hi})"
      fail=$((fail + 1))
    fi
  }

  TMP_DIR=$(mktemp -d -t lesson-sim-test.XXXXXX)
  trap 'rm -rf "$TMP_DIR"' EXIT

  # Fixture A: strategix-format lesson
  A="$TMP_DIR/lesson-a.md"
  cat > "$A" <<'EOF'
## Lesson: D1 migrations require explicit column lists
**Trigger:** Migration 023 failed silently
**Mistake:** Used SELECT * in INSERT INTO __new
**Rule:** Always list columns explicitly in table-recreate migrations to avoid positional misalignment between source and destination schemas.
**Date:** 2026-04-19
EOF

  # Fixture A (uppercase variant)
  A_caps="$TMP_DIR/lesson-a-caps.md"
  tr '[:lower:]' '[:upper:]' < "$A" > "$A_caps"

  # Fixture A (with extra stop-words sprinkled in — same content)
  A_stop="$TMP_DIR/lesson-a-stop.md"
  cat > "$A_stop" <<'EOF'
## Lesson: D1 migrations require explicit column lists
**Trigger:** Migration 023 failed silently
**Mistake:** Used SELECT * in INSERT INTO __new
**Rule:** Always list a the columns explicitly in the table-recreate migrations to avoid positional misalignment between the source and the destination schemas.
**Date:** 2026-04-19
EOF

  # Fixture X: disjoint vocabulary lesson
  X="$TMP_DIR/lesson-x.md"
  cat > "$X" <<'EOF'
## Lesson: Cron worker deployment requires manual wrangler config
**Trigger:** Sync job stopped firing overnight
**Mistake:** Assumed CI would deploy cron worker alongside main app
**Rule:** Document separate deploy command for cron-worker subdirectory; verify schedule binding via dashboard after every release.
**Date:** 2026-04-15
EOF

  # Half-overlap synthetic
  HA="$TMP_DIR/half-a.md"
  HB="$TMP_DIR/half-b.md"
  cat > "$HA" <<'EOF'
## Lesson: alpha
**Rule:** kappa lambda
**Date:** 2026-01-01
EOF
  cat > "$HB" <<'EOF'
## Lesson: alpha
**Rule:** mu nu
**Date:** 2026-01-01
EOF

  # Format-B (plain heading) variants
  HEAD1="$TMP_DIR/head1.md"
  HEAD2="$TMP_DIR/head2.md"
  cat > "$HEAD1" <<'EOF'
# Migration ordering matters

Always list columns explicitly when copying rows between recreated tables.
EOF
  cat > "$HEAD2" <<'EOF'
# Migration Ordering Matters

Always list columns explicitly when copying rows between recreated tables.
EOF

  # --- Assertions ---

  # Locate the BASH_SOURCE guard line so scans below can scope to the lib
  # region (everything above this line). Computed once, used by tests 12+13.
  guard_line=$(awk '/^if[[:space:]]+\[\[[[:space:]]+"\$\{BASH_SOURCE\[0\]\}"[[:space:]]+==[[:space:]]+"\$\{0\}"[[:space:]]+\]\];[[:space:]]+then/ { print NR; exit }' "$0")
  if [[ -z "$guard_line" ]]; then
    guard_line=$(grep -n 'BASH_SOURCE\[0\]' "$0" | head -1 | cut -d: -f1)
  fi

  # 1. Identical file → 100
  assert_eq "100" "$(lesson_similarity "$A" "$A")" "identical file -> 100"

  # 2. Disjoint vocabulary → low (allow up to 10 for chance overlap on rare common words)
  disjoint=$(lesson_similarity "$A" "$X")
  if [[ "$disjoint" -le 15 ]]; then
    echo "  PASS disjoint vocabulary -> low (got $disjoint)"
    pass=$((pass + 1))
  else
    echo "  FAIL disjoint vocabulary -> low  (got $disjoint, expected <= 15)"
    fail=$((fail + 1))
  fi

  # 3. Case-only delta → 100
  assert_eq "100" "$(lesson_similarity "$A" "$A_caps")" "case-only delta -> 100"

  # 4. Stop-word-only delta → 100
  assert_eq "100" "$(lesson_similarity "$A" "$A_stop")" "stop-word-only delta -> 100"

  # 5. Half-overlap synthetic (1 of 3 unique tokens shared post-stop-words)
  half=$(lesson_similarity "$HA" "$HB")
  assert_range 20 70 "$half" "half-overlap synthetic in 20..70"

  # 6. Missing file → 0
  assert_eq "0" "$(lesson_similarity "/nonexistent/path-a.md" "$A")" "missing file -> 0"
  assert_eq "0" "$(lesson_similarity "$A" "/nonexistent/path-b.md")" "missing file (other side) -> 0"

  # 7. Both missing → 0
  assert_eq "0" "$(lesson_similarity "/nope/a" "/nope/b")" "both missing -> 0"

  # 8. Empty file → 0
  EMPTY="$TMP_DIR/empty.md"
  : > "$EMPTY"
  assert_eq "0" "$(lesson_similarity "$EMPTY" "$A")" "empty file -> 0"

  # 9. Stop-words alone don't dominate (two files sharing only stop-words)
  SW1="$TMP_DIR/sw1.md"
  SW2="$TMP_DIR/sw2.md"
  cat > "$SW1" <<'EOF'
## Lesson: foo
**Rule:** the and or but with for from
**Date:** x
EOF
  cat > "$SW2" <<'EOF'
## Lesson: bar
**Rule:** the and or but with for from
**Date:** x
EOF
  # After stop-word strip both bodies tokenise to {foo} and {bar} respectively
  # → 0% overlap. (Title goes into the body too.)
  sw_score=$(lesson_similarity "$SW1" "$SW2")
  if [[ "$sw_score" -le 10 ]]; then
    echo "  PASS stop-words alone don't dominate (got $sw_score)"
    pass=$((pass + 1))
  else
    echo "  FAIL stop-words alone don't dominate  (got $sw_score, expected <= 10)"
    fail=$((fail + 1))
  fi

  # 10. Markdown formatting (case + heading punctuation) doesn't break match
  assert_eq "100" "$(lesson_similarity "$HEAD1" "$HEAD2")" "format B case+punct delta -> 100"

  # 11. Real-lesson sample range — A vs A with 3 words substituted
  A_MUT="$TMP_DIR/lesson-a-mut.md"
  cat > "$A_MUT" <<'EOF'
## Lesson: D1 migrations require explicit column lists
**Trigger:** Migration 023 failed silently
**Mistake:** Used SELECT * in INSERT INTO __new
**Rule:** Always list columns thoroughly in table-recreate migrations to prevent positional misalignment between source and destination schemas during copy.
**Date:** 2026-04-19
EOF
  mut_score=$(lesson_similarity "$A" "$A_MUT")
  assert_range 60 99 "$mut_score" "real-lesson sample (3 word swap) in 60..99"

  # 12. No `read -p` in this script — scan only the lib region (above guard),
  # skipping comments and self-test region (which references the pattern).
  if [[ -n "${guard_line:-}" ]]; then
    rp_hits=$(head -n "$guard_line" "$0" | grep -v '^[[:space:]]*#' | grep -cE '(^|[^A-Za-z_])read[[:space:]]+-p[[:space:]]' || true)
  else
    rp_hits=$(grep -v '^[[:space:]]*#' "$0" | grep -cE '(^|[^A-Za-z_])read[[:space:]]+-p[[:space:]]' || true)
  fi
  if [[ "$rp_hits" -eq 0 ]]; then
    echo "  PASS no 'read -p' in lib region"
    pass=$((pass + 1))
  else
    echo "  FAIL contains 'read -p' in lib region ($rp_hits hits)"
    fail=$((fail + 1))
  fi

  # 13. Bash-3 compat scan (lib region only — before this self-test block)
  # Find the line number of the BASH_SOURCE guard and scan only above it.
  guard_line=$(awk '/^if \[\[ "\$\{BASH_SOURCE\[0\]\}" == "\$\{0\}" \]\]; then/ { print NR; exit }' "$0")
  if [[ -z "$guard_line" ]]; then
    guard_line=$(awk '/BASH_SOURCE\[0\].*==.*\$\{0\}/ { print NR; exit }' "$0")
  fi
  if [[ -n "$guard_line" ]]; then
    bad=$(head -n "$guard_line" "$0" \
      | grep -v '^[[:space:]]*#' \
      | grep -cE '(^|[[:space:]])(declare -A|mapfile|readarray)([[:space:]]|$)' || true)
    if [[ "$bad" -eq 0 ]]; then
      echo "  PASS bash-3 compat: 0 bash-4-only constructs in lib region"
      pass=$((pass + 1))
    else
      echo "  FAIL bash-3 compat: $bad bash-4-only constructs in lib region"
      fail=$((fail + 1))
    fi
  else
    echo "  FAIL bash-3 compat scan: could not locate BASH_SOURCE guard line"
    fail=$((fail + 1))
  fi

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "ALL LESSON-SIMILARITY TESTS PASSED ($pass/$pass)"
    echo ""
    echo "✅ ALL LESSON-SIMILARITY TESTS PASSED"
    exit 0
  else
    echo "$fail/$((pass+fail)) tests failed"
    exit 1
  fi
fi
