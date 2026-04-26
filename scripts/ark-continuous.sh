#!/usr/bin/env bash
# ark-continuous.sh — Phase 7 AOS daemon: INBOX consumer + tick loop
#
# Plan 07-02 (REQ-AOS-40, REQ-AOS-41) — main daemon body.
#
# Sources:
#   scripts/ark-policy.sh      — single-writer audit (`_policy_log`)
#   scripts/lib/inbox-parser.sh — frontmatter parse + intent dispatch
#   scripts/ark-escalations.sh — `ark_escalate` queue writer
#   scripts/lib/policy-config.sh — cascading config (via ark-policy.sh)
#
# Public API (sourceable lib + CLI guard):
#   continuous_acquire_lock          mkdir-style lock at $LOCK_DIR; trap on EXIT cleans up.
#   continuous_release_lock          rmdir lock (idempotent).
#   continuous_check_daily_cap       0=PROCEED, 1=SUSPENDED; echoes USED=N CAP=M to stderr.
#   continuous_process_inbox <file>  Lifecycle one INBOX file (parse → dispatch → mv/rename).
#   continuous_record_failure        Bumps fail-counter; auto-creates PAUSE at 3 consecutive.
#   continuous_record_success        Resets fail-counter.
#   continuous_tick                  Single tick orchestrator (the cron entrypoint).
#   continuous_self_test             12+ assertions in mktemp -d isolation.
#
# Audit decisions emitted by this file (class:continuous):
#   TICK_START | TICK_COMPLETE | INBOX_DISPATCH | INBOX_PROCESSED | INBOX_FAILED |
#   INBOX_MALFORMED | DAILY_CAP_HIT | LOCK_CONTENDED | PAUSE_ACTIVE | AUTO_PAUSE_3_FAIL
# Decisions deferred to other plans:
#   STUCK_PHASE_DETECTED, AUTO_PAUSED  — Plan 07-03 (health-monitor)
#   WEEKLY_DIGEST_WRITTEN              — Plan 07-06 (separate script)
#
# Bash 3 compat (macOS): no `declare -A`, no `mapfile`, no `${var,,}`.
# IMPORTANT: Sourceable library — does NOT set -e/-u/-o pipefail at file scope.

# === Paths (resolve via ARK_HOME so self-test can isolate) ===
VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
INBOX_DIR="$VAULT_PATH/INBOX"
LOCK_DIR="$VAULT_PATH/.continuous.lock"
PAUSE_FILE="$VAULT_PATH/PAUSE"
FAIL_COUNT_FILE="$VAULT_PATH/.continuous-fail-count"
CONTINUOUS_LOG="$VAULT_PATH/observability/continuous-operation.log"
ESCALATIONS_FILE="$VAULT_PATH/ESCALATIONS.md"

# === Source dependencies (graceful degradation) ===
_ARK_CONTINUOUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# shellcheck disable=SC1091
if [[ -f "$_ARK_CONTINUOUS_DIR/ark-policy.sh" ]]; then
  # ark-policy.sh sources policy-config.sh + policy-db.sh internally
  source "$_ARK_CONTINUOUS_DIR/ark-policy.sh"
else
  # Stub: log to stderr only
  _policy_log() { echo "[stub _policy_log] class=$1 decision=$2 reason=$3" >&2; echo "stub-id"; }
  policy_config_get() { echo "$2"; }
fi

# shellcheck disable=SC1091
if [[ -f "$_ARK_CONTINUOUS_DIR/lib/inbox-parser.sh" ]]; then
  source "$_ARK_CONTINUOUS_DIR/lib/inbox-parser.sh"
else
  inbox_parse_frontmatter() { echo "inbox-parser.sh missing" >&2; return 2; }
  inbox_validate_intent()   { return 1; }
  inbox_dispatch_intent()   { return 1; }
fi

# shellcheck disable=SC1091
if [[ -f "$_ARK_CONTINUOUS_DIR/ark-escalations.sh" ]]; then
  source "$_ARK_CONTINUOUS_DIR/ark-escalations.sh"
else
  ark_escalate() { echo "[stub ark_escalate] $*" >&2; return 1; }
fi

# === Internal: reset paths after ARK_HOME changes (used by self-test) ===
_continuous_refresh_paths() {
  VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
  INBOX_DIR="$VAULT_PATH/INBOX"
  LOCK_DIR="$VAULT_PATH/.continuous.lock"
  PAUSE_FILE="$VAULT_PATH/PAUSE"
  FAIL_COUNT_FILE="$VAULT_PATH/.continuous-fail-count"
  CONTINUOUS_LOG="$VAULT_PATH/observability/continuous-operation.log"
  ESCALATIONS_FILE="$VAULT_PATH/ESCALATIONS.md"
}

# === Internal: ensure observability log directory + file exist ===
_continuous_ensure_log() {
  local dir
  dir="$(dirname "$CONTINUOUS_LOG")"
  mkdir -p "$dir" 2>/dev/null
  [[ -f "$CONTINUOUS_LOG" ]] || : > "$CONTINUOUS_LOG"
}

# === continuous_acquire_lock — mkdir-style lock ===
# Returns 0 if acquired, 1 if contended.
continuous_acquire_lock() {
  mkdir -p "$VAULT_PATH" 2>/dev/null
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    # Trap installed by caller (continuous_tick) so we don't leak across nested calls.
    return 0
  fi
  return 1
}

# === continuous_release_lock — idempotent rmdir ===
continuous_release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

# === continuous_check_daily_cap ===
# Returns 0 if USED < CAP (PROCEED), 1 if exceeded (SUSPENDED).
# Echoes "USED=N CAP=M" to stderr for caller-side logging.
continuous_check_daily_cap() {
  local cap used
  cap=$(policy_config_get continuous.daily_token_cap 50000 2>/dev/null)
  [[ -z "$cap" ]] && cap=50000

  used=0
  # Try SQLite first via db_path() if available
  if type db_path >/dev/null 2>&1; then
    local dbp
    dbp="$(db_path 2>/dev/null)"
    if [[ -f "$dbp" ]]; then
      # Sum tokens from class IN ('budget','dispatch') for today (UTC).
      # CONTEXT.md D-CONT-DAILY-CAP — coarse approximation; truth is the audit log.
      local q="SELECT IFNULL(SUM(json_extract(context,'\$.tokens')),0) FROM decisions WHERE class IN ('budget','dispatch','dispatcher') AND ts >= date('now','start of day');"
      used=$(sqlite3 "$dbp" "$q" 2>/dev/null)
      [[ -z "$used" ]] && used=0
    fi
  fi

  # Coerce to integer (sqlite may return floats)
  used=${used%.*}
  [[ "$used" =~ ^[0-9]+$ ]] || used=0

  echo "USED=$used CAP=$cap" >&2
  if [[ "$used" -ge "$cap" ]]; then
    return 1
  fi
  return 0
}

# === continuous_record_failure ===
# Bumps a per-vault failure counter. If counter reaches 3, auto-creates PAUSE,
# fires AUTO_PAUSE_3_FAIL audit, and queues a repeated-failure escalation.
# Idempotent: if PAUSE already exists, no double-escalate.
continuous_record_failure() {
  local count=0
  if [[ -f "$FAIL_COUNT_FILE" ]]; then
    count=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
  fi
  count=$((count + 1))
  echo "$count" > "$FAIL_COUNT_FILE"

  if [[ "$count" -ge 3 ]] && [[ ! -f "$PAUSE_FILE" ]]; then
    : > "$PAUSE_FILE"
    _policy_log "continuous" "AUTO_PAUSE_3_FAIL" \
      "consecutive_failures=$count" \
      "{\"fail_count\":$count}" \
      >/dev/null 2>&1
    ark_escalate "repeated-failure" \
      "ark-continuous: $count consecutive failure ticks → auto-paused" \
      "Daemon ticks failed $count consecutive times. PAUSE file auto-created at $PAUSE_FILE. Investigate INBOX/.failed files and observability/continuous-operation.log, then \`ark continuous resume\`." \
      >/dev/null 2>&1 || true
  fi
}

# === continuous_record_success — reset fail counter ===
continuous_record_success() {
  rm -f "$FAIL_COUNT_FILE" 2>/dev/null || true
}

# === Internal: append a markdown entry to ESCALATIONS.md (single-writer route) ===
# Uses ark_escalate when available; never touches the file directly.
_continuous_queue_failure() {
  local file="$1"
  local intent="$2"
  local rc="$3"
  ark_escalate "repeated-failure" \
    "ark-continuous: dispatch failed for $(basename "$file")" \
    "Intent: $intent
Exit code: $rc
File renamed to ${file%.md}.failed
Inspect $CONTINUOUS_LOG for the dispatch transcript." \
    >/dev/null 2>&1 || true
}

# === continuous_process_inbox <file> ===
# Returns 0 on successful dispatch + archive; 1 on malformed/failed.
continuous_process_inbox() {
  local file="$1"
  if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
    echo "continuous_process_inbox: file not found: $file" >&2
    return 1
  fi
  _continuous_ensure_log

  local fname
  fname="$(basename "$file")"

  # 1. Parse frontmatter
  local parsed
  parsed=$(inbox_parse_frontmatter "$file" 2>/dev/null)
  local prc=$?
  if [[ "$prc" -ne 0 ]]; then
    # Malformed → rename in place
    mv "$file" "${file%.md}.malformed" 2>/dev/null || true
    _policy_log "continuous" "INBOX_MALFORMED" \
      "no_frontmatter_or_missing_intent" \
      "{\"file\":\"$fname\"}" \
      >/dev/null 2>&1
    return 1
  fi

  # 2. Eval parsed assignments into local scope
  local INTENT="" CUSTOMER="" PRIORITY="" DESC="" PROJECT="" PHASE=""
  local line key val
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    case "$key" in
      INTENT)   INTENT="$val" ;;
      CUSTOMER) CUSTOMER="$val" ;;
      PRIORITY) PRIORITY="$val" ;;
      DESC)     DESC="$val" ;;
      PROJECT)  PROJECT="$val" ;;
      PHASE)    PHASE="$val" ;;
    esac
  done <<EOF
$parsed
EOF

  # 3. Validate intent
  if ! inbox_validate_intent "$INTENT" 2>/dev/null; then
    mv "$file" "${file%.md}.malformed" 2>/dev/null || true
    _policy_log "continuous" "INBOX_MALFORMED" \
      "unknown_intent:$INTENT" \
      "{\"file\":\"$fname\",\"intent\":\"$INTENT\"}" \
      >/dev/null 2>&1
    return 1
  fi

  # 4. Build dispatch command
  local cmd
  cmd=$(inbox_dispatch_intent "$INTENT" "$CUSTOMER" "$PRIORITY" "$DESC" "$PHASE" 2>/dev/null)
  local drc=$?
  if [[ "$drc" -ne 0 ]] || [[ -z "$cmd" ]]; then
    mv "$file" "${file%.md}.failed" 2>/dev/null || true
    _policy_log "continuous" "INBOX_FAILED" \
      "dispatch_build_failed:$INTENT" \
      "{\"file\":\"$fname\",\"intent\":\"$INTENT\"}" \
      >/dev/null 2>&1
    _continuous_queue_failure "$file" "$INTENT" "$drc"
    return 1
  fi

  # 5. Audit DISPATCH (pre-eval)
  _policy_log "continuous" "INBOX_DISPATCH" \
    "intent=$INTENT customer=$CUSTOMER" \
    "{\"file\":\"$fname\",\"intent\":\"$INTENT\",\"customer\":\"$CUSTOMER\",\"priority\":\"$PRIORITY\"}" \
    >/dev/null 2>&1

  # 6. Eval dispatch command (in subshell), capturing transcript to log.
  # Honor ARK_CREATE_GITHUB invariant: do not set it here. Caller environment governs.
  local rc=0
  (
    set +e
    eval "$cmd"
    exit $?
  ) >> "$CONTINUOUS_LOG" 2>&1
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    # Success → move to processed/<UTC-date>/
    local today
    today=$(date -u +%Y-%m-%d)
    local destdir="$INBOX_DIR/processed/$today"
    mkdir -p "$destdir" 2>/dev/null
    mv "$file" "$destdir/" 2>/dev/null || true
    _policy_log "continuous" "INBOX_PROCESSED" \
      "intent:$INTENT" \
      "{\"file\":\"$fname\",\"customer\":\"$CUSTOMER\",\"intent\":\"$INTENT\"}" \
      >/dev/null 2>&1
    return 0
  else
    # Failure → rename .failed + escalate
    mv "$file" "${file%.md}.failed" 2>/dev/null || true
    _policy_log "continuous" "INBOX_FAILED" \
      "exit:$rc intent:$INTENT" \
      "{\"file\":\"$fname\",\"intent\":\"$INTENT\",\"exit\":$rc}" \
      >/dev/null 2>&1
    _continuous_queue_failure "$file" "$INTENT" "$rc"
    return 1
  fi
}

# === continuous_tick — single tick orchestrator ===
# Returns 0 on success (including PAUSE/cap/lock skip); non-zero only on
# infrastructure failure. Business outcomes are audit rows, not exit codes.
continuous_tick() {
  _continuous_refresh_paths

  # 1. PAUSE check (BEFORE lock, so PAUSE is honored even if a stale lock exists)
  if [[ -f "$PAUSE_FILE" ]]; then
    _policy_log "continuous" "PAUSE_ACTIVE" \
      "pause_file_present" \
      "{\"pause_file\":\"$PAUSE_FILE\"}" \
      >/dev/null 2>&1
    return 0
  fi

  # 2. Acquire lock
  if ! continuous_acquire_lock; then
    _policy_log "continuous" "LOCK_CONTENDED" \
      "another_tick_in_progress" \
      "{\"lock\":\"$LOCK_DIR\"}" \
      >/dev/null 2>&1
    return 0
  fi

  # Trap to release lock on any exit path (including SIGINT/SIGTERM/error).
  # shellcheck disable=SC2064
  trap "continuous_release_lock" EXIT INT TERM

  _continuous_ensure_log
  _policy_log "continuous" "TICK_START" "tick_began" "null" >/dev/null 2>&1

  # 3. Daily cap check
  if ! continuous_check_daily_cap 2>/dev/null; then
    _policy_log "continuous" "DAILY_CAP_HIT" \
      "daily_token_cap_exceeded" \
      "null" \
      >/dev/null 2>&1
    continuous_release_lock
    trap - EXIT INT TERM
    return 0
  fi

  # 4. Scan INBOX
  local processed=0 failed=0 malformed=0
  if [[ -d "$INBOX_DIR" ]]; then
    # Bash 3 compat: while read with null-safe-ish find output
    local f
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      [[ ! -f "$f" ]] && continue
      # Pre-check parse to classify malformed before lifecycle wrapper runs
      local pre
      pre=$(inbox_parse_frontmatter "$f" 2>/dev/null)
      local pprc=$?
      if [[ "$pprc" -ne 0 ]]; then
        continuous_process_inbox "$f" >/dev/null 2>&1
        malformed=$((malformed + 1))
        continue
      fi
      if continuous_process_inbox "$f" >/dev/null 2>&1; then
        processed=$((processed + 1))
      else
        # Distinguish malformed-after-parse (unknown intent) vs failed dispatch.
        # Re-detect by suffix of the now-renamed file.
        if [[ -f "${f%.md}.malformed" ]]; then
          malformed=$((malformed + 1))
        else
          failed=$((failed + 1))
        fi
      fi
    done < <(find "$INBOX_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
  fi

  # 5. Update fail counter (success if no failures this tick)
  if [[ "$failed" -gt 0 ]]; then
    continuous_record_failure
  else
    continuous_record_success
  fi

  # 6. SECTION sentinel: health-monitor (Plan 07-03 fills in)
  # === SECTION: health-monitor (Plan 07-03) ===
  # Body added by Plan 07-03. Implements continuous_health_monitor —
  # stuck-phase detection (no STATE.md modification >24h + no recent commits)
  # and 3-tick consecutive-stuck escalation (idempotent dedupe via
  # correlation_id on the STUCK_PHASE_DETECTED audit row).
  # === END SECTION: health-monitor ===

  # 7. Audit TICK_COMPLETE
  _policy_log "continuous" "TICK_COMPLETE" \
    "p:$processed f:$failed m:$malformed" \
    "{\"processed\":$processed,\"failed\":$failed,\"malformed\":$malformed}" \
    >/dev/null 2>&1

  # 8. Release lock
  continuous_release_lock
  trap - EXIT INT TERM
  return 0
}

# === SECTION: subcommands (Plan 07-04) ===
# Body added by Plan 07-04. Implements:
#   continuous_install     — generate + load ~/Library/LaunchAgents/com.ark.continuous.plist
#   continuous_uninstall   — unload + remove plist
#   continuous_status      — show last tick, next tick, recent decisions, daily token used
#   continuous_pause       — touch PAUSE file
#   continuous_resume      — rm PAUSE file
#   continuous_plist_emit  — pure stdout plist generator (idempotent, byte-stable)
# === END SECTION: subcommands ===

# === continuous_self_test — 12+ assertions in mktemp -d isolation ===
continuous_self_test() {
  local pass=0 fail=0
  local TMP REAL_DB_MD5_BEFORE REAL_DB_MD5_AFTER

  TMP=$(mktemp -d 2>/dev/null) || { echo "mktemp failed"; return 1; }

  # Capture real-vault md5 invariant baseline (if real db exists).
  local real_db="${HOME}/vaults/ark/observability/policy.db"
  REAL_DB_MD5_BEFORE=""
  if [[ -f "$real_db" ]]; then
    REAL_DB_MD5_BEFORE=$(md5 -q "$real_db" 2>/dev/null || md5sum "$real_db" 2>/dev/null | awk '{print $1}')
  fi

  echo "🧪 ark-continuous.sh self-test (fixture: $TMP)"
  echo ""

  _ct_assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  ✅ $label"
      pass=$((pass+1))
    else
      echo "  ❌ $label  (expected: '$expected', got: '$actual')"
      fail=$((fail+1))
    fi
  }

  _ct_assert_true() {
    local cond_label="$2"
    if [[ "$1" == "1" ]]; then
      echo "  ✅ $cond_label"
      pass=$((pass+1))
    else
      echo "  ❌ $cond_label"
      fail=$((fail+1))
    fi
  }

  # Set up isolated environment.
  export ARK_HOME="$TMP/vault"
  export ARK_POLICY_DB="$TMP/vault/observability/policy.db"
  mkdir -p "$ARK_HOME/INBOX" "$ARK_HOME/observability"
  _continuous_refresh_paths

  # Initialise isolated DB so _policy_log goes there, not real DB.
  if type db_init >/dev/null 2>&1; then
    db_init >/dev/null 2>&1
  fi

  # Mock `ark` on PATH: success unless filename contains "fail" pattern.
  local MOCK_BIN="$TMP/bin"
  mkdir -p "$MOCK_BIN"
  cat > "$MOCK_BIN/ark" <<'MOCK_ARK'
#!/usr/bin/env bash
# Mock ark: success unless ARK_MOCK_FAIL=1 is set.
if [[ "${ARK_MOCK_FAIL:-0}" == "1" ]]; then
  echo "mock-ark: forced failure (ARK_MOCK_FAIL=1)" >&2
  exit 1
fi
echo "mock-ark invoked: $*"
exit 0
MOCK_ARK
  chmod +x "$MOCK_BIN/ark"
  export PATH="$MOCK_BIN:$PATH"

  # Helper: count audit rows for class:continuous matching a decision string.
  _ct_count() {
    local decision="$1"
    if type db_path >/dev/null 2>&1 && [[ -f "$(db_path)" ]]; then
      sqlite3 "$(db_path)" "SELECT COUNT(*) FROM decisions WHERE class='continuous' AND decision='$decision';" 2>/dev/null
    else
      echo 0
    fi
  }

  # ----------------------------------------------------------------------
  # Test 1: Empty INBOX → tick returns 0; TICK_START + TICK_COMPLETE only.
  # ----------------------------------------------------------------------
  echo "Test 1: Empty INBOX tick"
  continuous_tick >/dev/null 2>&1
  local rc=$?
  _ct_assert_eq "0" "$rc" "Test 1: empty-INBOX tick returns 0"
  _ct_assert_eq "1" "$(_ct_count TICK_START)" "Test 1a: TICK_START logged once"
  _ct_assert_eq "1" "$(_ct_count TICK_COMPLETE)" "Test 1b: TICK_COMPLETE logged once"
  _ct_assert_eq "0" "$(_ct_count INBOX_DISPATCH)" "Test 1c: no INBOX_DISPATCH on empty"
  _ct_assert_eq "0" "$(_ct_count INBOX_PROCESSED)" "Test 1d: no INBOX_PROCESSED on empty"

  # ----------------------------------------------------------------------
  # Test 2: One valid resume file → dispatched; file moves to processed/<date>/
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 2: Valid resume file"
  cat > "$INBOX_DIR/02-resume.md" <<'EOF'
---
intent: resume
customer: acme
---
# resume project
EOF
  continuous_tick >/dev/null 2>&1
  local today
  today=$(date -u +%Y-%m-%d)
  if [[ -f "$INBOX_DIR/processed/$today/02-resume.md" ]]; then
    _ct_assert_eq "1" "1" "Test 2: file moved to processed/$today/"
  else
    _ct_assert_eq "1" "0" "Test 2: file moved to processed/$today/"
  fi
  _ct_assert_eq "1" "$(_ct_count INBOX_PROCESSED)" "Test 2a: INBOX_PROCESSED row logged"
  _ct_assert_eq "1" "$(_ct_count INBOX_DISPATCH)" "Test 2b: INBOX_DISPATCH row logged"

  # ----------------------------------------------------------------------
  # Test 3: Malformed file → renamed .malformed + INBOX_MALFORMED logged
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 3: Malformed file"
  cat > "$INBOX_DIR/03-bad.md" <<'EOF'
no frontmatter at all
just garbage
EOF
  continuous_tick >/dev/null 2>&1
  if [[ -f "$INBOX_DIR/03-bad.malformed" ]]; then
    _ct_assert_eq "1" "1" "Test 3: file renamed .malformed"
  else
    _ct_assert_eq "1" "0" "Test 3: file renamed .malformed (got: $(ls "$INBOX_DIR" | tr '\n' ' '))"
  fi
  _ct_assert_eq "1" "$(_ct_count INBOX_MALFORMED)" "Test 3a: INBOX_MALFORMED row logged"

  # ----------------------------------------------------------------------
  # Test 4: Failing intent → renamed .failed + ESCALATIONS entry queued
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 4: Failing dispatch"
  cat > "$INBOX_DIR/04-fail.md" <<'EOF'
---
intent: resume
customer: failcorp
---
# this will fail
EOF
  ARK_MOCK_FAIL=1 continuous_tick >/dev/null 2>&1
  if [[ -f "$INBOX_DIR/04-fail.failed" ]]; then
    _ct_assert_eq "1" "1" "Test 4: file renamed .failed"
  else
    _ct_assert_eq "1" "0" "Test 4: file renamed .failed (got: $(ls "$INBOX_DIR" | tr '\n' ' '))"
  fi
  _ct_assert_eq "1" "$(_ct_count INBOX_FAILED)" "Test 4a: INBOX_FAILED row logged"
  if [[ -f "$ARK_HOME/ESCALATIONS.md" ]]; then
    _ct_assert_eq "1" "1" "Test 4b: ESCALATIONS.md created (escalation queued)"
  else
    _ct_assert_eq "1" "0" "Test 4b: ESCALATIONS.md created"
  fi

  # ----------------------------------------------------------------------
  # Test 5: PAUSE file present → tick exits 0; PAUSE_ACTIVE row; no new processing
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 5: PAUSE file"
  : > "$PAUSE_FILE"
  cat > "$INBOX_DIR/05-paused.md" <<'EOF'
---
intent: resume
---
# would-be processed
EOF
  local before_pause_count
  before_pause_count=$(_ct_count INBOX_PROCESSED)
  continuous_tick >/dev/null 2>&1
  rc=$?
  _ct_assert_eq "0" "$rc" "Test 5: paused tick returns 0"
  _ct_assert_eq "1" "$(_ct_count PAUSE_ACTIVE)" "Test 5a: PAUSE_ACTIVE row logged"
  if [[ -f "$INBOX_DIR/05-paused.md" ]]; then
    _ct_assert_eq "1" "1" "Test 5b: INBOX file untouched while paused"
  else
    _ct_assert_eq "1" "0" "Test 5b: INBOX file untouched while paused"
  fi
  _ct_assert_eq "$before_pause_count" "$(_ct_count INBOX_PROCESSED)" "Test 5c: no new INBOX_PROCESSED while paused"
  rm -f "$PAUSE_FILE"
  rm -f "$INBOX_DIR/05-paused.md"

  # ----------------------------------------------------------------------
  # Test 6: Lock contention → second tick logs LOCK_CONTENDED
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 6: Lock contention"
  mkdir -p "$LOCK_DIR"  # simulate another tick holding lock
  continuous_tick >/dev/null 2>&1
  rc=$?
  _ct_assert_eq "0" "$rc" "Test 6: contended tick returns 0"
  _ct_assert_eq "1" "$(_ct_count LOCK_CONTENDED)" "Test 6a: LOCK_CONTENDED row logged"
  rmdir "$LOCK_DIR" 2>/dev/null || true

  # ----------------------------------------------------------------------
  # Test 7: Daily cap = 0 → DAILY_CAP_HIT, no INBOX scan
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 7: Daily cap exceeded (cap=0)"
  cat > "$INBOX_DIR/07-capped.md" <<'EOF'
---
intent: resume
---
# would-be processed
EOF
  # Override policy_config_get for cap key only via env, by shadowing the func.
  # Simpler: monkey-patch policy_config_get for this test region.
  _orig_pcg=$(declare -f policy_config_get)
  policy_config_get() {
    if [[ "$1" == "continuous.daily_token_cap" ]]; then
      echo "0"
      return 0
    fi
    echo "$2"
  }
  local before_cap_count
  before_cap_count=$(_ct_count INBOX_PROCESSED)
  continuous_tick >/dev/null 2>&1
  _ct_assert_eq "1" "$(_ct_count DAILY_CAP_HIT)" "Test 7: DAILY_CAP_HIT row logged"
  _ct_assert_eq "$before_cap_count" "$(_ct_count INBOX_PROCESSED)" "Test 7a: no INBOX_PROCESSED while capped"
  # Restore original
  eval "$_orig_pcg"
  rm -f "$INBOX_DIR/07-capped.md"

  # ----------------------------------------------------------------------
  # Test 8: Daily cap not exceeded → returns 0
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 8: Daily cap under threshold"
  if continuous_check_daily_cap 2>/dev/null; then
    _ct_assert_eq "1" "1" "Test 8: continuous_check_daily_cap returns 0 under cap"
  else
    _ct_assert_eq "1" "0" "Test 8: continuous_check_daily_cap returns 0 under cap"
  fi

  # ----------------------------------------------------------------------
  # Test 9: Two files (good + malformed) in one tick — both lifecycled correctly
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 9: Mixed batch (good + malformed)"
  cat > "$INBOX_DIR/09-good.md" <<'EOF'
---
intent: promote-lessons
---
# promote
EOF
  cat > "$INBOX_DIR/09-bad.md" <<'EOF'
not a frontmatter file
EOF
  local before_proc=$(_ct_count INBOX_PROCESSED)
  local before_mal=$(_ct_count INBOX_MALFORMED)
  continuous_tick >/dev/null 2>&1
  local after_proc=$(_ct_count INBOX_PROCESSED)
  local after_mal=$(_ct_count INBOX_MALFORMED)
  _ct_assert_eq "1" "$((after_proc - before_proc))" "Test 9: one new INBOX_PROCESSED"
  _ct_assert_eq "1" "$((after_mal - before_mal))" "Test 9a: one new INBOX_MALFORMED"
  if [[ -f "$INBOX_DIR/09-bad.malformed" ]] && [[ ! -f "$INBOX_DIR/09-good.md" ]]; then
    _ct_assert_eq "1" "1" "Test 9b: good→processed, bad→.malformed"
  else
    _ct_assert_eq "1" "0" "Test 9b: good→processed, bad→.malformed"
  fi

  # ----------------------------------------------------------------------
  # Test 10: Lock dir is removed after every tick (trap discipline)
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 10: Lock cleanup"
  if [[ ! -d "$LOCK_DIR" ]]; then
    _ct_assert_eq "1" "1" "Test 10: lock dir absent after tick (trap released)"
  else
    _ct_assert_eq "1" "0" "Test 10: lock dir absent after tick (trap released)"
  fi

  # ----------------------------------------------------------------------
  # Test 11: 3 consecutive failure ticks → PAUSE auto-created
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 11: 3-fail auto-pause"
  rm -f "$FAIL_COUNT_FILE" "$PAUSE_FILE"
  local i
  for i in 1 2 3; do
    cat > "$INBOX_DIR/fail-$i.md" <<EOF
---
intent: resume
customer: failcorp$i
---
# fail $i
EOF
    ARK_MOCK_FAIL=1 continuous_tick >/dev/null 2>&1
  done
  if [[ -f "$PAUSE_FILE" ]]; then
    _ct_assert_eq "1" "1" "Test 11: PAUSE auto-created after 3 consecutive failures"
  else
    _ct_assert_eq "1" "0" "Test 11: PAUSE auto-created after 3 consecutive failures"
  fi
  local auto_pause_n
  auto_pause_n=$(_ct_count AUTO_PAUSE_3_FAIL)
  if [[ "$auto_pause_n" -ge "1" ]]; then
    _ct_assert_eq "1" "1" "Test 11a: AUTO_PAUSE_3_FAIL row logged"
  else
    _ct_assert_eq "1" "0" "Test 11a: AUTO_PAUSE_3_FAIL row logged (got $auto_pause_n)"
  fi
  rm -f "$PAUSE_FILE" "$FAIL_COUNT_FILE"
  rm -f "$INBOX_DIR/"fail-*.failed 2>/dev/null

  # ----------------------------------------------------------------------
  # Test 12: Successful tick clears fail counter
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 12: Success resets fail counter"
  echo "2" > "$FAIL_COUNT_FILE"
  cat > "$INBOX_DIR/12-good.md" <<'EOF'
---
intent: resume
---
# good
EOF
  continuous_tick >/dev/null 2>&1
  if [[ ! -f "$FAIL_COUNT_FILE" ]]; then
    _ct_assert_eq "1" "1" "Test 12: fail counter cleared after success"
  else
    _ct_assert_eq "1" "0" "Test 12: fail counter cleared after success (still: $(cat "$FAIL_COUNT_FILE"))"
  fi

  # ----------------------------------------------------------------------
  # Test 13: Sentinel sections present
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 13: Sentinel sections for 07-03 + 07-04"
  local self_path="${BASH_SOURCE[0]}"
  if grep -q '# === SECTION: health-monitor (Plan 07-03) ===' "$self_path"; then
    _ct_assert_eq "1" "1" "Test 13: health-monitor sentinel present"
  else
    _ct_assert_eq "1" "0" "Test 13: health-monitor sentinel present"
  fi
  if grep -q '# === SECTION: subcommands (Plan 07-04) ===' "$self_path"; then
    _ct_assert_eq "1" "1" "Test 13a: subcommands sentinel present"
  else
    _ct_assert_eq "1" "0" "Test 13a: subcommands sentinel present"
  fi

  # ----------------------------------------------------------------------
  # Test 14: No `read -p` invocation in code (regression guard)
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 14: Hygiene checks"
  if grep -nE '^[[:space:]]*read[[:space:]]+-p' "$self_path" >/dev/null 2>&1; then
    _ct_assert_eq "1" "0" "Test 14: no read -p in code"
  else
    _ct_assert_eq "1" "1" "Test 14: no read -p in code"
  fi
  if grep -nE '(^[[:space:]]*declare[[:space:]]+-A[[:space:]])|(^[[:space:]]*mapfile[[:space:]])' "$self_path" >/dev/null 2>&1; then
    _ct_assert_eq "1" "0" "Test 14a: bash 3 compat (no declare -A/mapfile)"
  else
    _ct_assert_eq "1" "1" "Test 14a: bash 3 compat (no declare -A/mapfile)"
  fi

  # ----------------------------------------------------------------------
  # Test 15: Real-vault md5 invariant — real policy.db unchanged
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 15: Real-vault md5 invariant"
  if [[ -n "$REAL_DB_MD5_BEFORE" ]]; then
    REAL_DB_MD5_AFTER=$(md5 -q "$real_db" 2>/dev/null || md5sum "$real_db" 2>/dev/null | awk '{print $1}')
    _ct_assert_eq "$REAL_DB_MD5_BEFORE" "$REAL_DB_MD5_AFTER" "Test 15: real ~/vaults/ark/observability/policy.db md5 unchanged"
  else
    echo "  ⏭  Test 15: skipped (no real policy.db on this system)"
    pass=$((pass+1))
  fi

  # Cleanup
  rm -rf "$TMP" 2>/dev/null
  unset ARK_HOME ARK_POLICY_DB
  _continuous_refresh_paths

  echo ""
  local total=$((pass+fail))
  echo "RESULT: $pass/$total pass"
  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL ARK-CONTINUOUS CORE TESTS PASSED"
    return 0
  else
    echo "❌ $fail/$total tests failed"
    return 1
  fi
}

# === CLI guard — only act when invoked directly ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test|self-test|test)
      continuous_self_test
      exit $?
      ;;
    --tick|tick)
      continuous_tick
      exit $?
      ;;
    "")
      # Default: silent no-op (lib sourceable without side effects)
      :
      ;;
    *)
      echo "Usage: $0 [--self-test|--tick]" >&2
      exit 2
      ;;
  esac
fi
