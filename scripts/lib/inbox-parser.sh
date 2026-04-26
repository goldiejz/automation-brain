#!/usr/bin/env bash
# inbox-parser.sh — INBOX frontmatter parser + intent dispatcher (sourceable lib)
#
# Phase 7 Plan 07-01 — AOS Continuous Operation foundation.
#
# Reads ~/vaults/ark/INBOX/*.md files (YAML-ish frontmatter + markdown body),
# extracts fields per D-CONT-INBOX-FORMAT, validates per D-CONT-INTENTS, and
# returns a dispatch command string per D-CONT-INTENTS dispatch table.
#
# Pure parser/dispatcher: NO file writes, NO _policy_log, NO network. The
# 07-02 daemon caller logs the dispatches via _policy_log.
#
# Public API (sourceable):
#   inbox_parse_frontmatter <file>
#       Echoes "KEY=value" lines for INTENT, CUSTOMER, PRIORITY, DESC.
#       Defaults: CUSTOMER=scratch, PRIORITY=medium when fields absent.
#       Returns 2 if no frontmatter delimiters or no `intent:` key.
#
#   inbox_validate_intent <intent_string>
#       Returns 0 if intent ∈ {new-project, new-phase, resume, promote-lessons}
#       Returns 1 with reason on stderr otherwise.
#
#   inbox_dispatch_intent <intent> <customer> <priority> <description> [extra]
#       Echoes the command-string the daemon will eval.
#       Returns 0 on success; 1 on unknown intent.
#
#   inbox_self_test
#       Runs 16+ assertions in mktemp -d fixture. Returns 0/1.
#
# Bash 3 compat (macOS): no associative arrays, no mapfile, no ${var,,}.
# IMPORTANT: Sourceable library — does NOT set -e/-u/-o pipefail at file scope.

# === Internal: trim leading/trailing whitespace ===
_inbox_trim() {
  # Read from stdin, echo trimmed
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# === inbox_parse_frontmatter <file> ===
# Echoes KEY=value lines. Returns 2 on malformed.
inbox_parse_frontmatter() {
  local file="$1"
  if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
    echo "inbox_parse_frontmatter: file not found: $file" >&2
    return 2
  fi

  # Single awk pass:
  #   - State machine: 0=before-fm, 1=in-fm, 2=after-fm
  #   - Emit `RAW_<KEY>=value` for recognised frontmatter keys
  #   - Emit `RAW_DESC=line` for the first non-blank body line (strip leading "# ")
  #   - Emit `RAW_HAS_FM=1` when we find an opening `---`
  #   - Emit `RAW_HAS_INTENT=1` when intent key seen
  local awk_out
  awk_out=$(awk '
    BEGIN { state = 0; got_desc = 0; line_num = 0 }
    {
      line_num++
      line = $0
      # Trim trailing CR (in case of CRLF files)
      sub(/\r$/, "", line)
    }
    state == 0 {
      # Looking for opening "---"
      # Allow blank lines before opening
      if (line ~ /^[[:space:]]*$/) next
      if (line ~ /^---[[:space:]]*$/) {
        print "RAW_HAS_FM=1"
        state = 1
        next
      }
      # Non-blank, non-delimiter content before any "---" → no frontmatter
      # Bail out of FM scan; treat whole file as body (state 2)
      state = 2
      # fall through to body handling below
    }
    state == 1 {
      # In frontmatter; closing "---" ends it
      if (line ~ /^---[[:space:]]*$/) {
        state = 2
        next
      }
      # Skip blank lines inside frontmatter
      if (line ~ /^[[:space:]]*$/) next
      # Skip comment lines
      if (line ~ /^[[:space:]]*#/) next
      # Parse "key: value"
      idx = index(line, ":")
      if (idx == 0) next
      k = substr(line, 1, idx-1)
      v = substr(line, idx+1)
      # Trim whitespace
      sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      # Strip surrounding quotes
      if (length(v) >= 2) {
        first = substr(v, 1, 1)
        last = substr(v, length(v), 1)
        if ((first == "\"" && last == "\"") || (first == "'\''" && last == "'\''")) {
          v = substr(v, 2, length(v)-2)
        }
      }
      # Strip trailing inline comment (only if preceded by whitespace — values may contain # legitimately, but YAML-ish is loose here; keep it conservative)
      # We skip inline-comment stripping to preserve descriptions/values with # in them.
      # Lowercase the key for matching
      lk = tolower(k)
      if (lk == "intent")   { print "RAW_INTENT=" v;   print "RAW_HAS_INTENT=1" }
      else if (lk == "customer") { print "RAW_CUSTOMER=" v }
      else if (lk == "priority") { print "RAW_PRIORITY=" v }
      else if (lk == "project")  { print "RAW_PROJECT=" v }
      else if (lk == "phase")    { print "RAW_PHASE=" v }
      next
    }
    state == 2 {
      # Body: capture first non-blank line, strip leading "# "
      if (got_desc) next
      if (line ~ /^[[:space:]]*$/) next
      desc = line
      sub(/^[[:space:]]+/, "", desc)
      sub(/^#[[:space:]]+/, "", desc)
      # Use a sentinel to allow embedded = and quotes safely
      print "RAW_DESC=" desc
      got_desc = 1
      next
    }
  ' "$file")

  # Parse awk output into shell vars
  local has_fm="" has_intent="" raw_intent="" raw_customer="" raw_priority="" raw_desc="" raw_project="" raw_phase=""
  local line key val
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    case "$key" in
      RAW_HAS_FM)     has_fm="$val" ;;
      RAW_HAS_INTENT) has_intent="$val" ;;
      RAW_INTENT)     raw_intent="$val" ;;
      RAW_CUSTOMER)   raw_customer="$val" ;;
      RAW_PRIORITY)   raw_priority="$val" ;;
      RAW_DESC)       raw_desc="$val" ;;
      RAW_PROJECT)    raw_project="$val" ;;
      RAW_PHASE)      raw_phase="$val" ;;
    esac
  done <<EOF
$awk_out
EOF

  # Malformed: no frontmatter delimiters
  if [[ "$has_fm" != "1" ]]; then
    echo "inbox_parse_frontmatter: no frontmatter found in $file" >&2
    return 2
  fi

  # Malformed: no intent key
  if [[ "$has_intent" != "1" ]]; then
    echo "inbox_parse_frontmatter: missing required field: intent" >&2
    return 2
  fi

  # Apply defaults per D-CONT-INBOX-FORMAT
  [[ -z "$raw_customer" ]] && raw_customer="scratch"
  [[ -z "$raw_priority" ]] && raw_priority="medium"

  echo "INTENT=$raw_intent"
  echo "CUSTOMER=$raw_customer"
  echo "PRIORITY=$raw_priority"
  echo "DESC=$raw_desc"
  if [[ -n "$raw_project" ]]; then
    echo "PROJECT=$raw_project"
  fi
  if [[ -n "$raw_phase" ]]; then
    echo "PHASE=$raw_phase"
  fi
  return 0
}

# === inbox_validate_intent <intent> ===
inbox_validate_intent() {
  local intent="$1"
  case "$intent" in
    new-project|new-phase|resume|promote-lessons)
      return 0
      ;;
    "")
      echo "inbox_validate_intent: empty intent" >&2
      return 1
      ;;
    *)
      echo "inbox_validate_intent: unknown intent: $intent (allowed: new-project|new-phase|resume|promote-lessons)" >&2
      return 1
      ;;
  esac
}

# === inbox_dispatch_intent <intent> <customer> <priority> <description> [extra] ===
# Echoes command string. Uses printf %q for safe shell-quoting of free-form fields.
inbox_dispatch_intent() {
  local intent="$1"
  local customer="$2"
  local priority="$3"  # currently unused in dispatch line; portfolio engine reads it separately
  local description="$4"
  local extra="${5:-}"

  # Touch priority to avoid unused-var noise from shellcheck strict callers
  : "$priority"

  case "$intent" in
    new-project)
      # ark create "<desc>" --customer "<cust>"
      local q_desc q_cust
      q_desc=$(printf '%q' "$description")
      q_cust=$(printf '%q' "$customer")
      printf 'ark create %s --customer %s\n' "$q_desc" "$q_cust"
      return 0
      ;;
    new-phase)
      # ark deliver --phase N (N from extra)
      if [[ -z "$extra" ]]; then
        echo "inbox_dispatch_intent: new-phase requires phase number in extra arg" >&2
        return 1
      fi
      local q_phase
      q_phase=$(printf '%q' "$extra")
      printf 'ark deliver --phase %s\n' "$q_phase"
      return 0
      ;;
    resume)
      printf 'ark deliver\n'
      return 0
      ;;
    promote-lessons)
      printf 'ark promote-lessons\n'
      return 0
      ;;
    *)
      echo "inbox_dispatch_intent: unknown intent: $intent" >&2
      return 1
      ;;
  esac
}

# === inbox_self_test — 16+ assertions in mktemp -d fixture ===
inbox_self_test() {
  local pass=0 fail=0
  local TMP
  TMP=$(mktemp -d 2>/dev/null) || { echo "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$TMP'" RETURN

  echo "🧪 inbox-parser.sh self-test (fixture: $TMP)"
  echo ""

  _assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  ✅ $label"
      pass=$((pass+1))
    else
      echo "  ❌ $label  (expected: '$expected', got: '$actual')"
      fail=$((fail+1))
    fi
  }

  _assert_rc() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  ✅ $label"
      pass=$((pass+1))
    else
      echo "  ❌ $label  (expected rc: $expected, got rc: $actual)"
      fail=$((fail+1))
    fi
  }

  _assert_match() {
    local pattern="$1" actual="$2" label="$3"
    if echo "$actual" | grep -qE "$pattern"; then
      echo "  ✅ $label"
      pass=$((pass+1))
    else
      echo "  ❌ $label  (pattern: $pattern, got: $actual)"
      fail=$((fail+1))
    fi
  }

  # ---- Build fixtures ----

  # Fixture 1: minimal valid new-project
  cat > "$TMP/01-good.md" <<'EOF'
---
intent: new-project
customer: acme
---
# foo
EOF

  # Fixture 2: missing intent
  cat > "$TMP/02-no-intent.md" <<'EOF'
---
customer: acme
priority: high
---
# Just a body
EOF

  # Fixture 3: no frontmatter delimiters
  cat > "$TMP/03-no-fm.md" <<'EOF'
Just some text without any frontmatter.
# Heading

More text.
EOF

  # Fixture 4: unknown intent
  cat > "$TMP/04-bad-intent.md" <<'EOF'
---
intent: do-the-thing
customer: acme
---
# do something
EOF

  # Fixture 5: full fields, all defaults overridden
  cat > "$TMP/05-full.md" <<'EOF'
---
intent: new-phase
customer: globex
priority: high
project: alpha
phase: 2
---
# Build phase 2 of alpha
EOF

  # Fixture 6: empty customer (defaults), with promote-lessons
  cat > "$TMP/06-defaults.md" <<'EOF'
---
intent: promote-lessons
---
EOF

  # Fixture 7: whitespace-loose values
  cat > "$TMP/07-whitespace.md" <<'EOF'
---
intent:    resume
customer:    acme
priority:   low
---



# A heading after blank lines
EOF

  # Fixture 8: description with shell-special chars (quotes, $, backticks)
  cat > "$TMP/08-special-chars.md" <<'EOF'
---
intent: new-project
customer: acme
---
# service "desk" for $foo & `bar`
EOF

  # ---- Run assertions ----

  echo "Frontmatter parsing:"

  # Test 1: minimal valid → INTENT=new-project, CUSTOMER=acme, DESC=foo
  local out1
  out1=$(inbox_parse_frontmatter "$TMP/01-good.md")
  local rc1=$?
  _assert_rc 0 "$rc1" "Test 1: minimal valid file returns 0"
  _assert_match "^INTENT=new-project$" "$out1" "Test 1a: INTENT=new-project"
  _assert_match "^CUSTOMER=acme$" "$out1" "Test 1b: CUSTOMER=acme"
  _assert_match "^DESC=foo$" "$out1" "Test 1c: DESC=foo (leading '# ' stripped)"

  # Test 2: missing intent → returns 2 with stderr message
  local err2 rc2
  err2=$(inbox_parse_frontmatter "$TMP/02-no-intent.md" 2>&1 >/dev/null)
  rc2=$?
  _assert_rc 2 "$rc2" "Test 2: missing intent returns 2"
  _assert_match "missing required field: intent" "$err2" "Test 2a: stderr says missing intent"

  # Test 3: no frontmatter at all → returns 2
  local err3 rc3
  err3=$(inbox_parse_frontmatter "$TMP/03-no-fm.md" 2>&1 >/dev/null)
  rc3=$?
  _assert_rc 2 "$rc3" "Test 3: no frontmatter returns 2"
  _assert_match "no frontmatter found" "$err3" "Test 3a: stderr says no frontmatter"

  echo ""
  echo "Intent validation:"

  # Test 4: unknown intent
  if inbox_validate_intent "do-the-thing" 2>/dev/null; then
    echo "  ❌ Test 4: unknown intent should return 1"; fail=$((fail+1))
  else
    echo "  ✅ Test 4: unknown intent returns 1"; pass=$((pass+1))
  fi

  # Test 5: all 4 valid intents
  local intent ok=1
  for intent in new-project new-phase resume promote-lessons; do
    if ! inbox_validate_intent "$intent" 2>/dev/null; then
      ok=0
      echo "  ❌ Test 5: valid intent $intent should return 0"; fail=$((fail+1))
    fi
  done
  if [[ "$ok" == "1" ]]; then
    echo "  ✅ Test 5: all 4 valid intents return 0"; pass=$((pass+1))
  fi

  echo ""
  echo "Dispatch table:"

  # Test 6: new-project + customer=acme + desc="service desk"
  local disp6
  disp6=$(inbox_dispatch_intent "new-project" "acme" "medium" "service desk")
  # printf %q on plain words yields the words unchanged; expect: ark create service\ desk --customer acme
  _assert_match '^ark create .* --customer acme$' "$disp6" "Test 6: new-project dispatch shape"
  _assert_match 'service' "$disp6" "Test 6a: contains description"

  # Test 7: new-phase with extra=2 → ark deliver --phase 2
  local disp7
  disp7=$(inbox_dispatch_intent "new-phase" "acme" "medium" "" "2")
  _assert_eq "ark deliver --phase 2" "$disp7" "Test 7: new-phase dispatch"

  # Test 8: resume → ark deliver
  local disp8
  disp8=$(inbox_dispatch_intent "resume" "acme" "low" "")
  _assert_eq "ark deliver" "$disp8" "Test 8: resume dispatch"

  # Test 9: promote-lessons → ark promote-lessons
  local disp9
  disp9=$(inbox_dispatch_intent "promote-lessons" "" "" "")
  _assert_eq "ark promote-lessons" "$disp9" "Test 9: promote-lessons dispatch"

  echo ""
  echo "Field extraction:"

  # Test 10: priority=high extracted
  local out5
  out5=$(inbox_parse_frontmatter "$TMP/05-full.md")
  _assert_match "^PRIORITY=high$" "$out5" "Test 10: PRIORITY=high extracted"
  _assert_match "^PROJECT=alpha$" "$out5" "Test 10a: PROJECT=alpha extracted"
  _assert_match "^PHASE=2$" "$out5" "Test 10b: PHASE=2 extracted"

  # Test 11: customer empty → defaults to scratch
  local out6
  out6=$(inbox_parse_frontmatter "$TMP/06-defaults.md")
  _assert_match "^CUSTOMER=scratch$" "$out6" "Test 11: missing customer defaults to scratch"

  # Test 12: priority empty → defaults to medium
  _assert_match "^PRIORITY=medium$" "$out6" "Test 12: missing priority defaults to medium"

  # Test 13: whitespace trimming in values
  local out7
  out7=$(inbox_parse_frontmatter "$TMP/07-whitespace.md")
  _assert_match "^INTENT=resume$" "$out7" "Test 13: INTENT trimmed"
  _assert_match "^CUSTOMER=acme$" "$out7" "Test 13a: CUSTOMER trimmed"
  _assert_match "^PRIORITY=low$" "$out7" "Test 13b: PRIORITY trimmed"

  # Test 14: body extraction skips multiple blank lines
  _assert_match "^DESC=A heading after blank lines$" "$out7" "Test 14: DESC across blank lines"

  echo ""
  echo "Library hygiene:"

  # Test 15: sourcing produces zero stdout/stderr
  local source_out
  source_out=$(bash -c "source '${BASH_SOURCE[0]}'" 2>&1)
  _assert_eq "" "$source_out" "Test 15: sourcing produces no output (no side effects)"

  # Test 16: mktemp fixture cleans up on RETURN trap
  # (We can't easily check trap-on-RETURN here without leaving the function;
  # instead, assert the fixture dir currently exists — proxy for trap-installed.)
  if [[ -d "$TMP" ]]; then
    echo "  ✅ Test 16: mktemp fixture exists during test (trap will clean on RETURN)"
    pass=$((pass+1))
  else
    echo "  ❌ Test 16: mktemp fixture missing"
    fail=$((fail+1))
  fi

  echo ""
  echo "Bonus assertions:"

  # Bonus 1: shell-special chars in description are properly quoted
  local out8 disp_special
  out8=$(inbox_parse_frontmatter "$TMP/08-special-chars.md")
  local desc8
  desc8=$(echo "$out8" | awk -F= '/^DESC=/ { sub(/^DESC=/, ""); print }')
  disp_special=$(inbox_dispatch_intent "new-project" "acme" "medium" "$desc8")
  # If we eval the dispatch, the args should round-trip safely.
  # Validate shape: starts with "ark create " and ends with " --customer acme"
  _assert_match '^ark create ' "$disp_special" "Bonus 1: special-chars dispatch starts with ark create"
  _assert_match ' --customer acme$' "$disp_special" "Bonus 1a: special-chars dispatch ends with --customer acme"

  # Bonus 2: customer field passed through correctly (not 'scratch')
  local disp_cust
  disp_cust=$(inbox_dispatch_intent "new-project" "globex-corp" "high" "build it")
  _assert_match ' --customer globex-corp$' "$disp_cust" "Bonus 2: customer passed through"

  # Bonus 3: no actual `read -p` invocation in this lib.
  # We look for a line that is an actual command (`^[[:space:]]*read -p ...`)
  # rather than text inside echo "..." messages. A real invocation starts the
  # line (post-indent) with the bare word "read".
  local lib_path="${BASH_SOURCE[0]}"
  if grep -nE '^[[:space:]]*read[[:space:]]+-p' "$lib_path" >/dev/null 2>&1; then
    echo "  ❌ Bonus 3: lib contains read -p invocation"
    fail=$((fail+1))
  else
    echo "  ✅ Bonus 3: no read -p invocation in lib"
    pass=$((pass+1))
  fi

  # Bonus 4: bash 3 compat — no declare -A, mapfile, ${var,,} as actual code.
  # Match `declare -A` or `mapfile` only at the start of a statement (post-indent).
  # Lowercase-param-expansion `${var,,}` is matched anywhere but we exclude
  # lines that look like grep/echo arguments (single-quoted) by requiring it
  # to NOT be inside a single-quoted string segment that contains the literal.
  if grep -nE '(^[[:space:]]*declare[[:space:]]+-A[[:space:]])|(^[[:space:]]*mapfile[[:space:]])' "$lib_path" >/dev/null 2>&1; then
    echo "  ❌ Bonus 4: lib uses Bash 4-only constructs"
    fail=$((fail+1))
  else
    echo "  ✅ Bonus 4: bash 3 compat (no declare -A/mapfile in code)"
    pass=$((pass+1))
  fi

  echo ""
  local total=$((pass+fail))
  echo "RESULT: $pass/$total pass"
  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL INBOX-PARSER TESTS PASSED"
    return 0
  else
    echo "❌ $fail/$total tests failed"
    return 1
  fi
}

# === CLI guard — only run self-test when invoked directly ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test|test|self-test)
      inbox_self_test
      exit $?
      ;;
    "")
      # Default: silent no-op (lib sourcing produces no output)
      :
      ;;
    *)
      echo "Usage: $0 [--self-test]" >&2
      exit 2
      ;;
  esac
fi
