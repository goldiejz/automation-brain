#!/usr/bin/env bash
# policy-digest.sh — Human-readable policy-evolution digest writer.
# Phase 3 Plan 03-04 (REQ-AOS-12).
#
# Reads ~/vaults/ark/observability/policy.db (SQLite, schema_version=1) and
# writes ~/vaults/ark/observability/policy-evolution.md — a human-readable
# markdown digest of every pattern Ark has scored, grouped into
# PROMOTED / DEPRECATED / MEDIOCRE_MIDDLE sections, plus a list of the
# four hard-coded true-blocker classes (excluded from learning).
#
# Atomic write: writes to <digest>.tmp.$$ then mv -f.
# Re-runs OVERWRITE the digest (current view, not journal).
# Read-only over the audit DB; never UPDATEs or INSERTs.
#
# Bash 3 compatible (macOS default). Sourceable library — no top-level
# `set -e`. Single-quoted heredocs for SQL (no shell expansion inside).
#
# NOTE on integration with 03-02 (policy-learner.sh):
# When this plan was executed, policy-learner.sh from 03-02 had not yet landed.
# This file therefore implements `learner_write_digest` standalone, computing
# scoring directly via SQL. When 03-02 ships, its policy-learner.sh should
# either:
#   (a) `source` this file and call `learner_write_digest` from `learner_run`, or
#   (b) merge the function definition below into policy-learner.sh and delete
#       this file.
# Either path is fine — see 03-04-SUMMARY.md.

# Resolve VAULT_PATH and DB path the same way the rest of the toolchain does.
_DIGEST_VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"

# Source policy-db.sh so we can reuse db_path() if available; otherwise fall back.
_DIGEST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -f "$_DIGEST_LIB_DIR/policy-db.sh" ]]; then
    # shellcheck disable=SC1091
    source "$_DIGEST_LIB_DIR/policy-db.sh"
fi

# Internal: resolve DB path with override support.
_digest_db_path() {
    if [[ -n "${ARK_POLICY_DB:-}" ]]; then
        echo "$ARK_POLICY_DB"
    elif command -v db_path >/dev/null 2>&1; then
        db_path
    else
        echo "${_DIGEST_VAULT_PATH}/observability/policy.db"
    fi
}

# Internal: scoring SQL as a single TSV stream.
# Columns: class, decision, dispatcher, complexity, n, success_count, rate_pct
# True-blocker filter: applied at SQL level — exclude class='escalation' and
# the (class='budget', decision='ESCALATE_MONTHLY_CAP') tuple.
_digest_score_tsv() {
    local since="${1:-1970-01-01T00:00:00Z}"
    local db; db="$(_digest_db_path)"
    if [[ ! -f "$db" ]]; then
        return 0
    fi
    # Use single-quoted heredoc — no shell expansion inside SQL.
    sqlite3 -separator $'\t' "$db" <<SQL
SELECT
    class,
    decision,
    COALESCE(json_extract(context, '\$.dispatcher'), 'none') AS dispatcher,
    COALESCE(json_extract(context, '\$.complexity'), 'none') AS complexity,
    COUNT(*)                                       AS n,
    SUM(CASE WHEN outcome='success' THEN 1 ELSE 0 END) AS success_count,
    CAST( (SUM(CASE WHEN outcome='success' THEN 1 ELSE 0 END) * 100.0)
        / COUNT(*) AS INTEGER )                    AS rate_pct
FROM decisions
WHERE outcome IS NOT NULL
  AND ts >= '$since'
  AND NOT (class = 'escalation')
  AND NOT (class = 'budget' AND decision = 'ESCALATE_MONTHLY_CAP')
GROUP BY class, decision, dispatcher, complexity
HAVING n >= 5
ORDER BY rate_pct DESC, n DESC, class, decision;
SQL
}

# learner_write_digest [since-iso8601]
# Writes policy-evolution.md atomically.
learner_write_digest() {
    local since="${1:-1970-01-01T00:00:00Z}"
    local digest_dir="${_DIGEST_VAULT_PATH}/observability"
    local digest="${digest_dir}/policy-evolution.md"
    mkdir -p "$digest_dir"
    local tmp="${digest}.tmp.$$"

    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local scored
    scored="$(_digest_score_tsv "$since")"

    # Bucket rows in awk so we read once.
    local promoted deprecated mediocre
    if [[ -n "$scored" ]]; then
        promoted="$(printf '%s\n' "$scored" | awk -F'\t' '$7 >= 80 { print }')"
        deprecated="$(printf '%s\n' "$scored" | awk -F'\t' '$7 <= 20 { print }')"
        mediocre="$(printf '%s\n' "$scored" | awk -F'\t' '$7 > 20 && $7 < 80 { print }')"
    else
        promoted=""
        deprecated=""
        mediocre=""
    fi

    {
        printf '%s\n' '# Policy Evolution Digest'
        printf '**Window:** %s → %s  \n' "$since" "$now"
        printf '**Generated:** %s\n' "$now"
        printf '\n'

        printf '%s\n' '## Promoted (≥5 occurrences, ≥80% success)'
        printf '\n'
        printf '%s\n' '| Class | Decision | Dispatcher | Complexity | n | Success rate |'
        printf '%s\n' '|-------|----------|------------|------------|---|--------------|'
        if [[ -n "$promoted" ]]; then
            printf '%s\n' "$promoted" | awk -F'\t' '{
                printf("| %s | %s | %s | %s | %s | %s%% |\n", $1, $2, $3, $4, $5, $7)
            }'
        fi
        printf '\n'

        printf '%s\n' '## Deprecated (≥5 occurrences, ≤20% success)'
        printf '\n'
        printf '%s\n' '| Class | Decision | Dispatcher | Complexity | n | Success rate |'
        printf '%s\n' '|-------|----------|------------|------------|---|--------------|'
        if [[ -n "$deprecated" ]]; then
            printf '%s\n' "$deprecated" | awk -F'\t' '{
                printf("| %s | %s | %s | %s | %s | %s%% |\n", $1, $2, $3, $4, $5, $7)
            }'
        fi
        printf '\n'

        printf '%s\n' '## Mediocre middle (20–80%, left alone)'
        printf '\n'
        printf '%s\n' '| Class | Decision | Dispatcher | Complexity | n | Success rate |'
        printf '%s\n' '|-------|----------|------------|------------|---|--------------|'
        if [[ -n "$mediocre" ]]; then
            printf '%s\n' "$mediocre" | awk -F'\t' '{
                printf("| %s | %s | %s | %s | %s | %s%% |\n", $1, $2, $3, $4, $5, $7)
            }'
        fi
        printf '\n'

        printf '%s\n' '## True-blocker classes (excluded from learning)'
        printf '%s\n' '- monthly-budget'
        printf '%s\n' '- architectural-ambiguity'
        printf '%s\n' '- destructive-op'
        printf '%s\n' '- repeated-failure'
    } > "$tmp"

    mv -f "$tmp" "$digest"
    echo "Digest written: $digest" >&2
}

# ----------------------------------------------------------------------------
# Self-test
# ----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" == "test" ]]; then
    set -uo pipefail

    TMPDB="/tmp/ark_digest_test_$$.db"
    TMPVAULT="/tmp/ark_digest_vault_$$"
    rm -rf "$TMPVAULT"
    mkdir -p "$TMPVAULT/observability"
    rm -f "$TMPDB"

    export ARK_POLICY_DB="$TMPDB"
    export ARK_HOME="$TMPVAULT"
    _DIGEST_VAULT_PATH="$ARK_HOME"

    # Initialise schema using policy-db.sh's db_init if available.
    if command -v db_init >/dev/null 2>&1; then
        db_init >/dev/null
    else
        sqlite3 "$TMPDB" <<'SQL' >/dev/null
CREATE TABLE IF NOT EXISTS decisions (
    decision_id TEXT PRIMARY KEY,
    ts TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1,
    class TEXT NOT NULL,
    decision TEXT NOT NULL,
    reason TEXT NOT NULL,
    context TEXT,
    outcome TEXT,
    correlation_id TEXT REFERENCES decisions(decision_id)
);
SQL
    fi

    # ----- Synthetic patterns -----
    # PROMOTE: dispatch_failure / SELF_HEAL / gemini / deep — 6 rows, 5 success / 1 failure (83%)
    # DEPRECATE: dispatch_failure / SELF_HEAL / codex / simple — 6 rows, 1 success / 5 failure (16%)
    # MEDIOCRE: dispatch_failure / SELF_HEAL / haiku / medium — 6 rows, 3 success / 3 failure (50%)
    # TRUE-BLOCKER: budget / ESCALATE_MONTHLY_CAP — 6 rows, 6 success (must NOT appear in promote)

    insert_row() {
        # $1=id $2=class $3=decision $4=dispatcher $5=complexity $6=outcome $7=ts
        local id="$1" cls="$2" dec="$3" disp="$4" cmplx="$5" out="$6" ts="$7"
        local ctx="{\"dispatcher\":\"$disp\",\"complexity\":\"$cmplx\"}"
        sqlite3 "$TMPDB" \
          "INSERT INTO decisions(decision_id, ts, class, decision, reason, context, outcome) \
           VALUES('$id', '$ts', '$cls', '$dec', 'synthetic', '$ctx', '$out');"
    }

    # PROMOTE bucket (5/6 success → 83%)
    insert_row p1 dispatch_failure SELF_HEAL gemini deep success "2026-04-20T00:00:01Z"
    insert_row p2 dispatch_failure SELF_HEAL gemini deep success "2026-04-20T00:00:02Z"
    insert_row p3 dispatch_failure SELF_HEAL gemini deep success "2026-04-20T00:00:03Z"
    insert_row p4 dispatch_failure SELF_HEAL gemini deep success "2026-04-20T00:00:04Z"
    insert_row p5 dispatch_failure SELF_HEAL gemini deep success "2026-04-20T00:00:05Z"
    insert_row p6 dispatch_failure SELF_HEAL gemini deep failure "2026-04-20T00:00:06Z"

    # DEPRECATE bucket (1/6 success → 16%)
    insert_row d1 dispatch_failure SELF_HEAL codex simple success "2026-04-20T00:01:01Z"
    insert_row d2 dispatch_failure SELF_HEAL codex simple failure "2026-04-20T00:01:02Z"
    insert_row d3 dispatch_failure SELF_HEAL codex simple failure "2026-04-20T00:01:03Z"
    insert_row d4 dispatch_failure SELF_HEAL codex simple failure "2026-04-20T00:01:04Z"
    insert_row d5 dispatch_failure SELF_HEAL codex simple failure "2026-04-20T00:01:05Z"
    insert_row d6 dispatch_failure SELF_HEAL codex simple failure "2026-04-20T00:01:06Z"

    # MEDIOCRE bucket (3/6 success → 50%)
    insert_row m1 dispatch_failure SELF_HEAL haiku medium success "2026-04-20T00:02:01Z"
    insert_row m2 dispatch_failure SELF_HEAL haiku medium success "2026-04-20T00:02:02Z"
    insert_row m3 dispatch_failure SELF_HEAL haiku medium success "2026-04-20T00:02:03Z"
    insert_row m4 dispatch_failure SELF_HEAL haiku medium failure "2026-04-20T00:02:04Z"
    insert_row m5 dispatch_failure SELF_HEAL haiku medium failure "2026-04-20T00:02:05Z"
    insert_row m6 dispatch_failure SELF_HEAL haiku medium failure "2026-04-20T00:02:06Z"

    # TRUE-BLOCKER bucket — 6 success at 100%, MUST be excluded
    insert_row b1 budget ESCALATE_MONTHLY_CAP none none success "2026-04-20T00:03:01Z"
    insert_row b2 budget ESCALATE_MONTHLY_CAP none none success "2026-04-20T00:03:02Z"
    insert_row b3 budget ESCALATE_MONTHLY_CAP none none success "2026-04-20T00:03:03Z"
    insert_row b4 budget ESCALATE_MONTHLY_CAP none none success "2026-04-20T00:03:04Z"
    insert_row b5 budget ESCALATE_MONTHLY_CAP none none success "2026-04-20T00:03:05Z"
    insert_row b6 budget ESCALATE_MONTHLY_CAP none none success "2026-04-20T00:03:06Z"

    # ESCALATION bucket — also must be excluded
    insert_row e1 escalation ESCALATE_REPEATED_FAILURE none none success "2026-04-20T00:04:01Z"
    insert_row e2 escalation ESCALATE_REPEATED_FAILURE none none success "2026-04-20T00:04:02Z"
    insert_row e3 escalation ESCALATE_REPEATED_FAILURE none none success "2026-04-20T00:04:03Z"
    insert_row e4 escalation ESCALATE_REPEATED_FAILURE none none success "2026-04-20T00:04:04Z"
    insert_row e5 escalation ESCALATE_REPEATED_FAILURE none none success "2026-04-20T00:04:05Z"
    insert_row e6 escalation ESCALATE_REPEATED_FAILURE none none success "2026-04-20T00:04:06Z"

    DIGEST="$TMPVAULT/observability/policy-evolution.md"

    # ----- Run 1 -----
    learner_write_digest "1970-01-01T00:00:00Z"

    pass=0; fail=0
    assert() {
        local label="$1"; shift
        if "$@"; then
            echo "  ✅ $label"; pass=$((pass+1))
        else
            echo "  ❌ $label"; fail=$((fail+1))
        fi
    }

    echo
    echo "=== Self-test: digest writer ==="

    assert "digest file exists"  test -f "$DIGEST"
    assert "has Promoted header" grep -q '^## Promoted' "$DIGEST"
    assert "has Deprecated header" grep -q '^## Deprecated' "$DIGEST"
    assert "has Mediocre header" grep -q '^## Mediocre' "$DIGEST"
    assert "has true-blocker header" grep -q '^## True-blocker classes' "$DIGEST"

    # The promoted row should include 'gemini' and 83%.
    assert "promoted row mentions gemini" grep -A 50 '^## Promoted' "$DIGEST" | grep -q 'gemini'
    assert "promoted row shows 83%"        grep -A 50 '^## Promoted' "$DIGEST" | grep -q '83%'

    # The deprecated row should include 'codex' and 16%.
    assert "deprecated row mentions codex" grep -A 50 '^## Deprecated' "$DIGEST" | grep -q 'codex'
    assert "deprecated row shows 16%"      grep -A 50 '^## Deprecated' "$DIGEST" | grep -q '16%'

    # The mediocre row should include 'haiku' and 50%.
    assert "mediocre row mentions haiku" grep -A 50 '^## Mediocre' "$DIGEST" | grep -q 'haiku'
    assert "mediocre row shows 50%"      grep -A 50 '^## Mediocre' "$DIGEST" | grep -q '50%'

    # True-blocker exclusion: ESCALATE_MONTHLY_CAP and ESCALATE_REPEATED_FAILURE must
    # NOT appear in any of the table sections (only as static class names in the bottom list).
    if grep -E '^\| .* \|.* (ESCALATE_MONTHLY_CAP|ESCALATE_REPEATED_FAILURE) ' "$DIGEST" >/dev/null 2>&1; then
        echo "  ❌ true-blocker tuple leaked into a table"
        fail=$((fail+1))
    else
        echo "  ✅ true-blocker tuples not in any table"
        pass=$((pass+1))
    fi

    # Sanity: each table section should contain exactly one data row for our fixtures.
    promoted_rows=$(awk '/^## Promoted/{f=1;next} /^## /{f=0} f && /^\| [^-]/ && !/^\| Class /' "$DIGEST" | wc -l | tr -d ' ')
    deprecated_rows=$(awk '/^## Deprecated/{f=1;next} /^## /{f=0} f && /^\| [^-]/ && !/^\| Class /' "$DIGEST" | wc -l | tr -d ' ')
    mediocre_rows=$(awk '/^## Mediocre/{f=1;next} /^## /{f=0} f && /^\| [^-]/ && !/^\| Class /' "$DIGEST" | wc -l | tr -d ' ')

    if [[ "$promoted_rows" -eq 1 ]]; then
        echo "  ✅ exactly 1 promoted data row ($promoted_rows)"; pass=$((pass+1))
    else
        echo "  ❌ promoted data rows expected 1 got $promoted_rows"; fail=$((fail+1))
    fi
    if [[ "$deprecated_rows" -eq 1 ]]; then
        echo "  ✅ exactly 1 deprecated data row ($deprecated_rows)"; pass=$((pass+1))
    else
        echo "  ❌ deprecated data rows expected 1 got $deprecated_rows"; fail=$((fail+1))
    fi
    if [[ "$mediocre_rows" -eq 1 ]]; then
        echo "  ✅ exactly 1 mediocre data row ($mediocre_rows)"; pass=$((pass+1))
    else
        echo "  ❌ mediocre data rows expected 1 got $mediocre_rows"; fail=$((fail+1))
    fi

    # ----- Run 2: idempotency (strip Generated:/Window: lines and diff) -----
    cp "$DIGEST" "${DIGEST}.run1"
    sleep 1   # ensure timestamp changes (we strip those lines in the diff)
    learner_write_digest "1970-01-01T00:00:00Z"
    cp "$DIGEST" "${DIGEST}.run2"

    diff_out=$(diff <(grep -vE '^(\*\*Generated:|\*\*Window:)' "${DIGEST}.run1") \
                   <(grep -vE '^(\*\*Generated:|\*\*Window:)' "${DIGEST}.run2") || true)
    if [[ -z "$diff_out" ]]; then
        echo "  ✅ idempotent (run1 == run2 modulo timestamps)"; pass=$((pass+1))
    else
        echo "  ❌ idempotency violated:"; echo "$diff_out"; fail=$((fail+1))
    fi

    # Atomic write: no leftover .tmp.* files
    leftover=$(ls "$TMPVAULT/observability/" 2>/dev/null | grep -c '\.tmp\.' || true)
    if [[ "$leftover" -eq 0 ]]; then
        echo "  ✅ no leftover .tmp.* files"; pass=$((pass+1))
    else
        echo "  ❌ leftover tmp files: $leftover"; fail=$((fail+1))
    fi

    # Cleanup
    rm -rf "$TMPVAULT" "$TMPDB"

    echo
    echo "=== Results: $pass passed, $fail failed ==="
    if [[ "$fail" -eq 0 ]]; then
        echo "✅ ALL DIGEST TESTS PASSED"
        exit 0
    else
        echo "❌ DIGEST TESTS FAILED"
        exit 1
    fi
fi
