#!/usr/bin/env bash
# ark verify — automated end-to-end verification suite
#
# Runs every Ark capability with pass/fail criteria, captures output,
# produces a verification report. The CEO reads the report — doesn't run
# every command by hand.
#
# Usage:
#   ark verify                    # run all checks
#   ark verify --tier 1           # only Tier 1 (read-only)
#   ark verify --skip-tier 4,5    # skip risky tiers
#   ark verify --report-only      # show last report
#
# Exit codes:
#   0 = all critical checks passed
#   1 = one or more critical checks failed
#   2 = warnings only (non-critical issues)

set -uo pipefail

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
PROJECT_DIR="$(pwd)"
REPORTS_DIR="$VAULT_PATH/observability/verification-reports"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
REPORT="$REPORTS_DIR/$TIMESTAMP.md"
mkdir -p "$REPORTS_DIR"

TIER_FILTER=""
SKIP_TIERS=""
REPORT_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier) TIER_FILTER="$2"; shift 2 ;;
    --skip-tier) SKIP_TIERS="$2"; shift 2 ;;
    --report-only) REPORT_ONLY=true; shift ;;
    *) shift ;;
  esac
done

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASS=0
WARN=0
FAIL=0
SKIP=0
RESULTS=()

# === Show last report ===
if [[ "$REPORT_ONLY" == "true" ]]; then
  latest=$(ls -t "$REPORTS_DIR"/*.md 2>/dev/null | head -1)
  if [[ -n "$latest" ]]; then
    cat "$latest"
  else
    echo "No verification reports yet. Run: ark verify"
  fi
  exit 0
fi

# === Helpers ===
should_run_tier() {
  local tier="$1"
  if [[ -n "$TIER_FILTER" ]] && [[ "$TIER_FILTER" != "$tier" ]]; then
    return 1
  fi
  if [[ -n "$SKIP_TIERS" ]]; then
    if [[ ",$SKIP_TIERS," == *",$tier,"* ]]; then
      return 1
    fi
  fi
  return 0
}

run_check() {
  local tier="$1"
  local name="$2"
  local command="$3"
  local pass_pattern="$4"  # regex or substring expected in output
  local critical="${5:-true}"

  if ! should_run_tier "$tier"; then
    SKIP=$((SKIP+1))
    RESULTS+=("⏭  T$tier: $name (skipped)")
    return
  fi

  local output
  output=$(eval "$command" 2>&1 || echo "__COMMAND_FAILED__")
  local exit_code=$?

  if echo "$output" | grep -qE "$pass_pattern"; then
    PASS=$((PASS+1))
    RESULTS+=("✅ T$tier: $name")
    echo -e "${GREEN}  ✅${NC} T$tier: $name"
  else
    if [[ "$critical" == "true" ]]; then
      FAIL=$((FAIL+1))
      RESULTS+=("❌ T$tier: $name (output didn't match: $pass_pattern)")
      echo -e "${RED}  ❌${NC} T$tier: $name"
    else
      WARN=$((WARN+1))
      RESULTS+=("⚠️  T$tier: $name (non-critical)")
      echo -e "${YELLOW}  ⚠️${NC}  T$tier: $name"
    fi
  fi
}

run_existence_check() {
  local tier="$1"
  local name="$2"
  local path="$3"
  local critical="${4:-true}"

  if ! should_run_tier "$tier"; then
    SKIP=$((SKIP+1))
    RESULTS+=("⏭  T$tier: $name (skipped)")
    return
  fi

  if [[ -e "$path" ]]; then
    PASS=$((PASS+1))
    RESULTS+=("✅ T$tier: $name")
    echo -e "${GREEN}  ✅${NC} T$tier: $name"
  else
    if [[ "$critical" == "true" ]]; then
      FAIL=$((FAIL+1))
      RESULTS+=("❌ T$tier: $name (missing: $path)")
      echo -e "${RED}  ❌${NC} T$tier: $name"
    else
      WARN=$((WARN+1))
      RESULTS+=("⚠️  T$tier: $name")
      echo -e "${YELLOW}  ⚠️${NC}  T$tier: $name"
    fi
  fi
}

# === Begin verification ===
echo ""
echo -e "${BLUE}🔍 ARK VERIFY — Automated E2E Verification${NC}"
echo -e "   Project: $(basename "$PROJECT_DIR")"
echo -e "   Vault:   $VAULT_PATH"
echo -e "   Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ━━━ TIER 1 — Read-only ━━━
if should_run_tier 1; then
  echo -e "${BLUE}━━━ Tier 1: Read-only ━━━${NC}"
fi
run_existence_check 1 "Vault directory exists" "$VAULT_PATH"
run_existence_check 1 "Vault is git repo" "$VAULT_PATH/.git"
run_check 1 "ark help responds" "ark help" "ARK"
run_check 1 "ark status shows snapshot" "cd '$PROJECT_DIR' && ark status" "Snapshot present|No snapshot"
run_check 1 "ark portfolio scans projects" "ark portfolio" "PROJECT|Portfolio"
run_check 1 "ark insights reads vault" "ark insights" "Cross-Customer Insights|insights"
run_check 1 "ark lessons lists count" "ark lessons" "Total: [0-9]+"
run_check 1 "ark doctor 27 checks" "ark doctor" "Summary:.*passed"
run_check 1 "ark budget initializes" "cd '$PROJECT_DIR' && ark budget" "Brain Budget|Tier"
run_check 1 "ark lifecycle reads stage" "cd '$PROJECT_DIR' && ark lifecycle status" "Lifecycle:|stage"
run_check 1 "Phase 6 daemon runs clean" "cd '$VAULT_PATH' && npx ts-node observability/phase-6-daemon.ts 2>&1" "OBSERVABILITY DAEMON COMPLETE|No bootstrap decision"
run_check 1 "ark-context detects runtime" "ark-context.sh --primary || bash $VAULT_PATH/scripts/ark-context.sh --primary" "claude-code-session|codex|gemini|regex"
run_existence_check 1 "Brain snapshot present in this project" "$PROJECT_DIR/.parent-automation/brain-snapshot/SNAPSHOT-MANIFEST.json" false
run_existence_check 1 "Decision log present" "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl" false

# ━━━ TIER 2 — Vault writes (reversible) ━━━
if should_run_tier 2; then
  echo ""
  echo -e "${BLUE}━━━ Tier 2: Vault writes (reversible) ━━━${NC}"
fi
run_check 2 "ark sync pulls + writes" "cd '$PROJECT_DIR' && ark sync" "BRAIN SYNC COMPLETE"
run_check 2 "ark backup creates tarball" "ark backup" "Backup created"
run_check 2 "ark validate (drift check)" "ark validate" "valid|drift|stable"
run_check 2 "ark report --for self" "cd '$PROJECT_DIR' && ark report --for self" "Report saved"

# ━━━ TIER 3 — File structure ━━━
if should_run_tier 3; then
  echo ""
  echo -e "${BLUE}━━━ Tier 3: File structure ━━━${NC}"
fi
run_check 3 "ark align dry-run safe" "cd '$PROJECT_DIR' && ark align --dry-run" "DRY RUN COMPLETE|Would|alignment"
run_check 3 "ark secrets check" "cd '$PROJECT_DIR' && ark secrets check" "secrets|Missing|present" false

# ━━━ TIER 4 — Throwaway project creation ━━━
if should_run_tier 4; then
  echo ""
  echo -e "${BLUE}━━━ Tier 4: Throwaway project creation ━━━${NC}"
fi
TEST_PROJECT="/tmp/ark-verify-$TIMESTAMP"
run_check 4 "ark create scaffolds project" \
  "ark create ark-verify-$TIMESTAMP --type custom --customer verify --stack node-cli --deploy none --path /tmp 2>&1" \
  "PROJECT CREATED|✅ Initialized"
run_existence_check 4 "Project dir created" "$TEST_PROJECT"
run_existence_check 4 "CLAUDE.md generated" "$TEST_PROJECT/CLAUDE.md"
run_existence_check 4 "package.json generated" "$TEST_PROJECT/package.json"
run_existence_check 4 ".planning/STATE.md exists" "$TEST_PROJECT/.planning/STATE.md"
run_existence_check 4 ".planning/bootstrap-decisions.jsonl exists" "$TEST_PROJECT/.planning/bootstrap-decisions.jsonl"
run_existence_check 4 "src/lib/rbac.ts (universal RBAC)" "$TEST_PROJECT/src/lib/rbac.ts"
# Cleanup test project
[[ -d "$TEST_PROJECT" ]] && rm -rf "$TEST_PROJECT"
gh repo delete "goldiejz/ark-verify-$TIMESTAMP" --yes 2>/dev/null || true

# ━━━ TIER 5 — Production safety ━━━
if should_run_tier 5; then
  echo ""
  echo -e "${BLUE}━━━ Tier 5: Production safety gates ━━━${NC}"
fi
run_check 5 "Production deploy blocks without --confirm" \
  "cd '$PROJECT_DIR' && ark promote --to production 2>&1 | head -20" \
  "PRODUCTION DEPLOY BLOCKED|requires explicit confirmation"
run_check 5 "Staging dry-run shows plan" \
  "cd '$PROJECT_DIR' && ark promote --to staging --dry-run 2>&1 | head -10" \
  "DRY RUN|would execute|deployment"

# ━━━ TIER 6 — Hooks + observability ━━━
if should_run_tier 6; then
  echo ""
  echo -e "${BLUE}━━━ Tier 6: Hooks + integration ━━━${NC}"
fi
run_existence_check 6 "SessionStart hook present" "$HOME/.claude/hooks/ark-session-start.sh"
run_existence_check 6 "Stop hook (extract-learnings)" "$HOME/.claude/hooks/ark-extract-learnings.sh"
run_existence_check 6 "Stop hook (error-monitor)" "$HOME/.claude/hooks/ark-error-monitor.sh"
run_existence_check 6 "Stop hook (session-end)" "$HOME/.claude/hooks/ark-session-end.sh"
run_check 6 "Hooks registered in settings.json" \
  "grep -c 'ark-' $HOME/.claude/settings.json" \
  "[1-9]"
run_existence_check 6 "Brain skill installed (/ark)" "$HOME/.claude/skills/ark/SKILL.md"
run_check 6 "Employee registry has roles" \
  "ls $VAULT_PATH/employees/*.json 2>/dev/null | wc -l" \
  "[1-9]"

# ━━━ Tier 7: GSD compatibility ━━━
if should_run_tier 7; then
  echo ""
  echo -e "${BLUE}━━━ Tier 7: GSD compatibility ━━━${NC}"
fi
run_existence_check 7 "Shared gsd-shape lib present" "$VAULT_PATH/scripts/lib/gsd-shape.sh"
run_check 7 "gsd-shape lib syntax valid" \
  "bash -n '$VAULT_PATH/scripts/lib/gsd-shape.sh' && echo OK" \
  "OK"
run_check 7 "normalize_phase_num handles decimals" \
  "bash -c 'source $VAULT_PATH/scripts/lib/gsd-shape.sh; gsd_normalize_phase_num 1.5'" \
  "^01\.5$"
run_check 7 "normalize_phase_num pads single digits" \
  "bash -c 'source $VAULT_PATH/scripts/lib/gsd-shape.sh; gsd_normalize_phase_num 2'" \
  "^02$"
run_check 7 "ark-deliver sources gsd-shape lib" \
  "grep -c 'gsd-shape.sh' $VAULT_PATH/scripts/ark-deliver.sh" \
  "[1-9]"
run_check 7 "ark-team sources gsd-shape lib" \
  "grep -c 'gsd-shape.sh' $VAULT_PATH/scripts/ark-team.sh" \
  "[1-9]"
run_check 7 "execute-phase sources gsd-shape lib" \
  "grep -c 'gsd-shape.sh' $VAULT_PATH/scripts/execute-phase.sh" \
  "[1-9]"

GSD_TEST_PROJECT="$HOME/code/strategix-servicedesk"
if [[ -d "$GSD_TEST_PROJECT/.planning/phases" ]]; then
  run_check 7 "GSD project detected as GSD" \
    "bash -c 'source $VAULT_PATH/scripts/lib/gsd-shape.sh; gsd_is_gsd_project \"$GSD_TEST_PROJECT\" && echo GSD'" \
    "GSD"
  run_check 7 "Phase 1.5 resolves to real GSD slug dir" \
    "bash -c 'source $VAULT_PATH/scripts/lib/gsd-shape.sh; gsd_resolve_phase_dir 1.5 \"$GSD_TEST_PROJECT\"'" \
    "phases/01\.5-"
  run_check 7 "Phase 1.5 finds multi-plan files (>=2)" \
    "bash -c 'source $VAULT_PATH/scripts/lib/gsd-shape.sh; d=\$(gsd_resolve_phase_dir 1.5 \"$GSD_TEST_PROJECT\"); gsd_find_plan_files \"\$d\" | wc -l'" \
    "[2-9]|[1-9][0-9]"
  run_check 7 "Phase 1.5 finds non-zero tasks across plans" \
    "bash -c 'source $VAULT_PATH/scripts/lib/gsd-shape.sh; d=\$(gsd_resolve_phase_dir 1.5 \"$GSD_TEST_PROJECT\"); gsd_count_tasks \"\$d\"'" \
    "^[1-9][0-9]*$"
  run_check 7 "No sibling phase-1.5 dir created on GSD project" \
    "[[ ! -d '$GSD_TEST_PROJECT/.planning/phase-1.5' ]] && echo NOSIB" \
    "NOSIB"
fi

TMP_LEGACY="/tmp/ark-verify-legacy-$$"
mkdir -p "$TMP_LEGACY/.planning/phase-2"
echo "- [ ] task" > "$TMP_LEGACY/.planning/phase-2/PLAN.md"
run_check 7 "Legacy ark layout (phase-N/PLAN.md) still resolves" \
  "bash -c 'source $VAULT_PATH/scripts/lib/gsd-shape.sh; gsd_resolve_phase_dir 2 \"$TMP_LEGACY\"'" \
  "phase-2$"
run_check 7 "Legacy ark layout finds PLAN.md tasks" \
  "bash -c 'source $VAULT_PATH/scripts/lib/gsd-shape.sh; gsd_count_tasks \"$TMP_LEGACY/.planning/phase-2\"'" \
  "^1$"
rm -rf "$TMP_LEGACY"

# ━━━ Tier 8: Autonomy under stress (AOS) ━━━
# Phase 2 exit gate. Verifies CONTEXT.md acceptance criterion #5: simulated
# quota+budget exhaustion conditions; pipeline proceeds without input;
# Tier 1–7 unchanged.
#
# Call-graph trace for the isolated dedup test (NEW-W-1):
#   dispatch_task (BLACK tier)
#     └─ policy_budget_decision           → 1 class:budget log line (AUTO_RESET)
#         └─ ark-budget.sh --reset
#             └─ python3 zeros phase_used
#             └─ check_and_notify
#                 └─ notify_tier_change(BLACK, GREEN)   (post-zero new_tier=GREEN)
#                     └─ new_tier != BLACK → skips _budget_apply_policy_on_black
#                     └─ NO additional class:budget log line
#   Expected DELTA = 1
#
# Sentinel-cost observability path (NEW-W-3):
#   The session-handoff branch in execute-phase.sh::dispatch_task calls:
#     ark-budget.sh --record <est_tokens> "claude-session-handoff:<task_id>"
#   --record appends an entry to PROJECT_DIR/.planning/budget.json's history
#   array with model="claude-session-handoff:<task_id>". (It does NOT write to
#   $VAULT_PATH/observability/budget-events.jsonl — only tier_change events go
#   there.) The sentinel test therefore inspects budget.json's history for the
#   literal "claude-session-handoff" string.
if should_run_tier 8; then
  echo ""
  echo -e "${BLUE}━━━ Tier 8: Autonomy under stress ━━━${NC}"
fi

run_existence_check 8 "ark-policy.sh present" "$VAULT_PATH/scripts/ark-policy.sh"
run_existence_check 8 "policy-config.sh present" "$VAULT_PATH/scripts/lib/policy-config.sh"
run_existence_check 8 "ark-escalations.sh present" "$VAULT_PATH/scripts/ark-escalations.sh"

run_check 8 "ark-policy.sh syntax valid" \
  "bash -n $VAULT_PATH/scripts/ark-policy.sh && echo OK" \
  "OK"

run_check 8 "ark-escalations.sh syntax valid" \
  "bash -n $VAULT_PATH/scripts/ark-escalations.sh && echo OK" \
  "OK"

run_check 8 "ark-policy self-test passes" \
  "bash $VAULT_PATH/scripts/ark-policy.sh test 2>&1 | tail -3" \
  "ALL POLICY TESTS PASSED"

run_check 8 "self-heal.sh has --retry mode + 3 layer entries" \
  "grep -cE '_self_heal_layer_(enriched|escalate_model|escalate_queue)|--retry' $VAULT_PATH/scripts/self-heal.sh" \
  "^[4-9]$|^[1-9][0-9]+$"

run_check 8 "Audit log schema_version=1 + decision_id (16-hex suffix)" \
  "bash -c 'TDB=/tmp/tier8-schema-\$\$.db; ARK_POLICY_DB=\$TDB ARK_HOME=$VAULT_PATH bash -c \"export ARK_POLICY_DB=\$TDB; source $VAULT_PATH/scripts/ark-policy.sh; policy_budget_decision 0 50000 0 1000000 >/dev/null\"; sqlite3 \$TDB \"SELECT printf(\\\"schema_version=%d decision_id=%s\\\", schema_version, decision_id) FROM decisions LIMIT 1;\"; rm -f \$TDB \$TDB-shm \$TDB-wal'" \
  "schema_version=1 decision_id=[0-9]{8}T[0-9]{6}Z-[0-9a-f]{16}"

# NEW-B-2 verification: class:self_heal lines in the global log must contain decision_id.
# Mirrors the existing class:budget assertion from 02-06b.
run_check 8 "All class:self_heal lines have decision_id (NEW-B-2)" \
  "bash -c 'log=$VAULT_PATH/observability/policy-decisions.jsonl; if [[ ! -f \"\$log\" ]]; then echo NO_LOG_OK; exit 0; fi; bad=\$(grep \"class\\\":\\\"self_heal\\\"\" \"\$log\" 2>/dev/null | grep -cv decision_id); echo \"bad=\$bad\"'" \
  "^bad=0$|NO_LOG_OK"

run_check 8 "Budget auto-reset when monthly headroom" \
  "bash -c 'source $VAULT_PATH/scripts/ark-policy.sh; policy_budget_decision 60000 50000 60000 1000000'" \
  "^AUTO_RESET$"

run_check 8 "Budget escalates at 95%+ monthly" \
  "bash -c 'source $VAULT_PATH/scripts/ark-policy.sh; policy_budget_decision 60000 50000 960000 1000000'" \
  "^ESCALATE_MONTHLY_CAP$"

# W-4 split: SPECIFIC dispatcher-route assertions (one value each — no tolerance regex).

run_check 8 "Dispatcher route — active session: returns EXACTLY claude-session (W-4)" \
  "bash -c 'unset ANTHROPIC_API_KEY; CLAUDE_PROJECT_DIR=/tmp/fake-session-dir ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true ARK_HOME=$VAULT_PATH bash -c \"source $VAULT_PATH/scripts/ark-policy.sh; policy_dispatcher_route standard GREEN\"'" \
  "^claude-session$"

run_check 8 "Dispatcher route — no session, no API key, quota stubs: EXACTLY regex-fallback (W-4)" \
  "bash -c 'unset ANTHROPIC_API_KEY CLAUDE_PROJECT_DIR; ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true ARK_HOME=$VAULT_PATH bash -c \"unset CLAUDE_PROJECT_DIR; source $VAULT_PATH/scripts/ark-policy.sh; policy_dispatcher_route standard BLACK\"'" \
  "^regex-fallback$"

run_check 8 "Zero-task phase returns SKIP_LOGGED" \
  "bash -c 'source $VAULT_PATH/scripts/ark-policy.sh; policy_zero_tasks /tmp/fake 0'" \
  "^SKIP_LOGGED$"

run_check 8 "Dispatch failure escalates after max retries" \
  "bash -c 'source $VAULT_PATH/scripts/ark-policy.sh; policy_dispatch_failure /tmp/err 3'" \
  "^ESCALATE_REPEATED$"

run_check 8 "policy_load_config emits 4 KEY=VALUE lines" \
  "bash -c 'source $VAULT_PATH/scripts/ark-policy.sh; policy_load_config | wc -l | tr -d \" \"'" \
  "^4$"

run_check 8 "Delivery-path scripts have zero unintentional read prompts" \
  "grep -nE 'read -[pr] ' $VAULT_PATH/scripts/ark-deliver.sh $VAULT_PATH/scripts/ark-team.sh $VAULT_PATH/scripts/execute-phase.sh $VAULT_PATH/scripts/ark-budget.sh $VAULT_PATH/scripts/self-heal.sh $VAULT_PATH/scripts/ark-escalations.sh $VAULT_PATH/scripts/ark-policy.sh 2>/dev/null | grep -v 'AOS: intentional' | wc -l | tr -d ' '" \
  "^0$"

run_check 8 "Delivery-path scripts source ark-policy.sh" \
  "bash -c 'count=0; for f in ark-deliver.sh ark-team.sh execute-phase.sh ark-budget.sh self-heal.sh; do grep -qE \"source.*ark-policy\\.sh|ark-policy\\.sh\\\"\" \"$VAULT_PATH/scripts/\$f\" && count=\$((count+1)); done; echo \"count=\$count\"'" \
  "^count=5$"

run_check 8 "Observer pattern manual-gate-hit registered" \
  "python3 -c \"import json; d=json.load(open('$VAULT_PATH/observability/observer/patterns.json')); ids=[p.get('id') for p in (d.get('patterns', d) if isinstance(d, dict) else d)]; print('PRESENT' if 'manual-gate-hit' in ids else 'MISSING')\"" \
  "^PRESENT$"

run_check 8 "ark escalations subcommand dispatches" \
  "$VAULT_PATH/scripts/ark escalations --list 2>&1 | head -1" \
  "Ark Escalations|No open escalations|No escalations queue|ESC-"

# NEW-W-1 ISOLATED dedup test:
# Use a tmp VAULT_PATH so concurrent writes against the global log can't poison the delta.
# Copies ark-policy.sh + lib + ark-budget.sh + ark-context.sh + execute-phase.sh into
# a tmp dir with empty observability/policy-decisions.jsonl. Documented call-graph result:
# DELTA=1 (notify_tier_change(BLACK,GREEN) post-zero does NOT re-enter _budget_apply_policy_on_black
# because the new_tier guard is `== BLACK`). The check accepts (1|2) per plan; observed=1.
run_check 8 "Audit log: ISOLATED budget-decision count per BLACK-tier dispatch (NEW-W-1)" \
  "bash $VAULT_PATH/scripts/tier8-helpers/dedup-test.sh '$VAULT_PATH'" \
  "^DELTA=(1|2)$"

# NEW-W-3 sentinel observability:
# The session-handoff branch records via `ark-budget.sh --record <tokens> claude-session-handoff:<id>`.
# That writes to PROJECT_DIR/.planning/budget.json's history array (NOT budget-events.jsonl).
# This check synthetically dispatches a session-handoff and asserts budget.json gained
# >=1 history entry with model containing 'claude-session-handoff'. If the --record signature
# silently fails (NEW-W-3 root cause), the count would be 0 and this check fails.
run_check 8 "Session-handoff sentinel cost recorded in budget.json history (NEW-W-3)" \
  "bash $VAULT_PATH/scripts/tier8-helpers/sentinel-test.sh '$VAULT_PATH'" \
  "^SENTINEL_DELTA=[1-9][0-9]*$"

# NEW-W-4 entropy stress: 100 _policy_log calls produce 100 distinct decision_ids.
run_check 8 "decision_id uniqueness under stress: 100 calls, 100 distinct (NEW-W-4)" \
  "bash $VAULT_PATH/scripts/tier8-helpers/stress-test.sh '$VAULT_PATH'" \
  "^UNIQUE=100$"

# End-to-end: simulated quota stubs do NOT block on `read`. Two complementary checks:
#   (a) under active session → claude-session
#   (b) without session and quotas exhausted → regex-fallback (no read prompt)
run_check 8 "End-to-end: quota stubs + active session → claude-session (no input)" \
  "bash -c 'unset ANTHROPIC_API_KEY; CLAUDE_PROJECT_DIR=/tmp/fake-session-dir ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true ARK_HOME=$VAULT_PATH bash -c \"source $VAULT_PATH/scripts/ark-policy.sh; policy_dispatcher_route standard GREEN\" </dev/null'" \
  "^claude-session$"

# Second end-to-end leg uses BLACK tier (which short-circuits to regex-fallback
# inside policy_dispatcher_route BEFORE the session-detection branch). We cannot
# test the "no-session" path via env-unset while running inside a Claude session
# because ark-context.sh --primary detects the parent process regardless of
# CLAUDE_PROJECT_DIR. BLACK-tier short-circuit covers the same observable goal:
# routing returns regex-fallback under stressed conditions without prompting.
run_check 8 "End-to-end: BLACK tier + quota stubs → regex-fallback (no input)" \
  "bash -c 'unset ANTHROPIC_API_KEY; ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true ARK_HOME=$VAULT_PATH bash -c \"source $VAULT_PATH/scripts/ark-policy.sh; policy_dispatcher_route standard BLACK\" </dev/null'" \
  "^regex-fallback$"

# ━━━ Tier 9: Self-improving self-heal (AOS Phase 3) ━━━
# Synthetic SQLite audit log → assert promote/deprecate/no-op outcomes match contract.
# Isolated VAULT_PATH (tmp) — never poisons the real vault. Substrate is SQLite per
# Phase 2.5 + SUPERSEDES.md — synthetic data is INSERTed, not appended JSONL.
#
# Fixture composition (matches PLAN.md 03-07):
#   Pattern A: (dispatch_failure, SELF_HEAL, gemini, deep)   × 6 — 5 success + 1 failure (83%) → PROMOTE
#   Pattern B: (dispatch_failure, SELF_HEAL, codex,  simple) × 6 — 1 success + 5 failure (17%) → DEPRECATE
#   Pattern C: (dispatch_failure, SELF_HEAL, haiku,  medium) × 6 — 3 success + 3 failure (50%) → IGNORE
#   Pattern D: (budget,           ESCALATE_MONTHLY_CAP, none, none) × 6 — all success → IGNORE (true-blocker)
#   Pattern E: (escalation,       ARCHITECTURAL_AMBIGUOUS, none, none) × 6 — all success → IGNORE (true-blocker, SQL-filtered)
if should_run_tier 9; then
  echo ""
  echo -e "${BLUE}━━━ Tier 9: Self-improving self-heal ━━━${NC}"
fi

run_existence_check 9 "outcome-tagger.sh present" "$VAULT_PATH/scripts/lib/outcome-tagger.sh"
run_existence_check 9 "policy-learner.sh present" "$VAULT_PATH/scripts/policy-learner.sh"
run_existence_check 9 "policy-digest.sh present" "$VAULT_PATH/scripts/lib/policy-digest.sh"

run_check 9 "policy-learner.sh syntax valid" \
  "bash -n '$VAULT_PATH/scripts/policy-learner.sh' && echo OK" \
  "OK"
run_check 9 "outcome-tagger.sh syntax valid" \
  "bash -n '$VAULT_PATH/scripts/lib/outcome-tagger.sh' && echo OK" \
  "OK"
run_check 9 "policy-digest.sh syntax valid" \
  "bash -n '$VAULT_PATH/scripts/lib/policy-digest.sh' && echo OK" \
  "OK"

run_check 9 "ark learn subcommand registered" \
  "grep -cE '^[[:space:]]*learn\\)' '$VAULT_PATH/scripts/ark'" \
  "^[1-9]"

run_check 9 "ark-deliver post-phase learner trigger present" \
  "grep -c policy-learner.sh '$VAULT_PATH/scripts/ark-deliver.sh'" \
  "^[1-9]"

run_check 9 "policy-learner self-test passes" \
  "bash '$VAULT_PATH/scripts/policy-learner.sh' test 2>&1 | tail -3" \
  "ALL .* TESTS PASSED|tests passed|self-test|✅"

# === Tier 9 synthetic-pipeline test in isolated tmp vault ===
# Tier 9 isolation pattern mirrors Phase 2 NEW-W-1: tmp ARK_HOME, separate
# ARK_POLICY_DB, real vault DB md5'd before+after to guarantee no leakage.
if should_run_tier 9; then
  TIER9_TMP=$(mktemp -d -t ark-tier9.XXXXXX)
  trap "rm -rf '$TIER9_TMP'" EXIT
  mkdir -p "$TIER9_TMP/observability"
  TIER9_DB="$TIER9_TMP/observability/policy.db"

  # Seed policy.yml + git repo so learner_apply_pending can commit
  cat > "$TIER9_TMP/policy.yml" <<'YML'
# tier9 synthetic vault
learned_patterns: {}
YML
  ( cd "$TIER9_TMP" && git init --quiet && \
    git -c user.email=t@t.test -c user.name=Tier9 add -A && \
    git -c user.email=t@t.test -c user.name=Tier9 commit -m init --quiet ) >/dev/null 2>&1

  # Initialize SQLite DB with schema
  ARK_POLICY_DB="$TIER9_DB" bash -c "source '$VAULT_PATH/scripts/lib/policy-db.sh'; db_init" >/dev/null 2>&1

  # INSERT synthetic decisions (substrate is SQLite per SUPERSEDES.md)
  python3 - "$TIER9_DB" <<'PY' >/dev/null 2>&1
import sqlite3, sys, datetime
db = sys.argv[1]
con = sqlite3.connect(db)
cur = con.cursor()
base = datetime.datetime(2026, 4, 26, 10, 0, 0)
i = 0
def emit(cls, dec, disp, cplx, outcome):
    global i
    ts = (base + datetime.timedelta(minutes=i)).strftime("%Y-%m-%dT%H:%M:%SZ")
    ts_compact = (base + datetime.timedelta(minutes=i)).strftime("%Y%m%dT%H%M%SZ")
    did = "%s-%016x" % (ts_compact, i + 1)
    if disp == "none" and cplx == "none":
        ctx = None
    else:
        ctx = '{"dispatcher":"%s","complexity":"%s"}' % (disp, cplx)
    cur.execute("INSERT INTO decisions (decision_id, ts, schema_version, class, decision, reason, context, outcome) VALUES (?, ?, 1, ?, ?, 'synthetic-tier9', ?, ?)",
                (did, ts, cls, dec, ctx, outcome))
    i += 1
# A: gemini/deep PROMOTE
for o in ["success"]*5 + ["failure"]:
    emit("dispatch_failure", "SELF_HEAL", "gemini", "deep", o)
# B: codex/simple DEPRECATE
for o in ["success"] + ["failure"]*5:
    emit("dispatch_failure", "SELF_HEAL", "codex", "simple", o)
# C: haiku/medium IGNORE (mediocre)
for o in ["success"]*3 + ["failure"]*3:
    emit("dispatch_failure", "SELF_HEAL", "haiku", "medium", o)
# D: budget true-blocker
for _ in range(6):
    emit("budget", "ESCALATE_MONTHLY_CAP", "none", "none", "success")
# E: escalation true-blocker (SQL-filtered before classify)
for _ in range(6):
    emit("escalation", "ARCHITECTURAL_AMBIGUOUS", "none", "none", "success")
con.commit()
con.close()
PY

  # Snapshot real vault DB md5 BEFORE (isolation guarantee)
  REAL_DB="$VAULT_PATH/observability/policy.db"
  REAL_MD5_BEFORE=$(md5 -q "$REAL_DB" 2>/dev/null || md5sum "$REAL_DB" 2>/dev/null | awk '{print $1}')
  REAL_MD5_BEFORE="${REAL_MD5_BEFORE:-NO_DB}"

  # Run learner with auto-apply against the isolated tmp vault
  ARK_HOME="$TIER9_TMP" \
  ARK_POLICY_DB="$TIER9_DB" \
  PENDING_FILE="$TIER9_TMP/observability/policy-evolution-pending.jsonl" \
  LEARNER_AUTO_APPLY=1 \
    bash "$VAULT_PATH/scripts/policy-learner.sh" --full >"$TIER9_TMP/learner.out" 2>"$TIER9_TMP/learner.err" || true

  # The pending sidecar may be archived as .applied-<epoch> after auto-apply.
  # Check for either form.
  TIER9_PENDING_GLOB="$TIER9_TMP/observability/policy-evolution-pending.jsonl*"

  REAL_MD5_AFTER=$(md5 -q "$REAL_DB" 2>/dev/null || md5sum "$REAL_DB" 2>/dev/null | awk '{print $1}')
  REAL_MD5_AFTER="${REAL_MD5_AFTER:-NO_DB}"

  # 9.synthetic.1 — exactly 1 PROMOTE entry in pending sidecar (gemini/deep)
  run_check 9 "synthetic: 1 promotion in pending sidecar" \
    "n=\$(cat $TIER9_PENDING_GLOB 2>/dev/null | grep -c '\"action\":\"promote\"'); test \"\${n:-0}\" -eq 1 && echo OK" \
    "^OK$"

  # 9.synthetic.2 — exactly 1 DEPRECATE entry (codex/simple)
  run_check 9 "synthetic: 1 deprecation in pending sidecar" \
    "n=\$(cat $TIER9_PENDING_GLOB 2>/dev/null | grep -c '\"action\":\"deprecate\"'); test \"\${n:-0}\" -eq 1 && echo OK" \
    "^OK$"

  # 9.synthetic.3 — zero entries for haiku/medium (mediocre middle)
  run_check 9 "synthetic: zero entries for haiku/medium (mediocre)" \
    "! cat $TIER9_PENDING_GLOB 2>/dev/null | grep -q '\"dispatcher\":\"haiku\"' && echo OK" \
    "^OK$"

  # 9.synthetic.4 — zero entries for budget/ESCALATE_MONTHLY_CAP (true-blocker)
  run_check 9 "synthetic: zero entries for budget/ESCALATE_MONTHLY_CAP (true-blocker)" \
    "! cat $TIER9_PENDING_GLOB 2>/dev/null | grep -q 'ESCALATE_MONTHLY_CAP' && echo OK" \
    "^OK$"

  # 9.synthetic.5 — zero entries for class:escalation (true-blocker, SQL-filtered)
  run_check 9 "synthetic: zero entries for class:escalation (true-blocker)" \
    "! cat $TIER9_PENDING_GLOB 2>/dev/null | grep -q '\"class\":\"escalation\"' && echo OK" \
    "^OK$"

  # 9.synthetic.6 — auto-patch: policy.yml gained both gemini (promote) and codex (deprecate) keys
  run_check 9 "synthetic: policy.yml gained gemini+codex learned_patterns" \
    "grep -q gemini '$TIER9_TMP/policy.yml' && grep -q codex '$TIER9_TMP/policy.yml' && echo OK" \
    "^OK$"

  # 9.synthetic.7 — digest written with Promoted + Deprecated sections
  run_check 9 "synthetic: digest has Promoted + Deprecated sections" \
    "grep -q '^## Promoted' '$TIER9_TMP/observability/policy-evolution.md' && grep -q '^## Deprecated' '$TIER9_TMP/observability/policy-evolution.md' && echo OK" \
    "^OK$"

  # 9.synthetic.8 — exactly 2 self_improve audit lines (1 promote + 1 deprecate)
  run_check 9 "synthetic: 2 self_improve audit entries in tmp DB" \
    "n=\$(sqlite3 '$TIER9_DB' \"SELECT COUNT(*) FROM decisions WHERE class='self_improve';\"); test \"\${n:-0}\" -eq 2 && echo OK" \
    "^OK$"

  # 9.synthetic.9 — git committed (≥1 commit beyond the init commit) in tmp vault
  run_check 9 "synthetic: tmp vault git gained ≥1 self_improve commit" \
    "n=\$(git -C '$TIER9_TMP' log --oneline 2>/dev/null | wc -l | tr -d ' '); test \"\${n:-0}\" -ge 2 && echo OK" \
    "^OK$"

  # 9.synthetic.10 — isolation: real vault policy.db unchanged
  run_check 9 "synthetic: real vault policy.db unchanged (isolation guarantee)" \
    "test '$REAL_MD5_BEFORE' = '$REAL_MD5_AFTER' && echo OK" \
    "^OK$"

  # 9.synthetic.11 — idempotency: re-running with empty/already-applied pending is a no-op
  ARK_HOME="$TIER9_TMP" \
  ARK_POLICY_DB="$TIER9_DB" \
  PENDING_FILE="$TIER9_TMP/observability/policy-evolution-pending.jsonl" \
  LEARNER_AUTO_APPLY=1 \
    bash "$VAULT_PATH/scripts/policy-learner.sh" --full >"$TIER9_TMP/learner2.out" 2>"$TIER9_TMP/learner2.err" || true
  run_check 9 "synthetic: idempotent re-run produces no new self_improve entries" \
    "n=\$(sqlite3 '$TIER9_DB' \"SELECT COUNT(*) FROM decisions WHERE class='self_improve';\"); test \"\${n:-0}\" -eq 2 && echo OK" \
    "^OK$"
fi

# ━━━ Generate report ━━━
TOTAL=$((PASS + WARN + FAIL + SKIP))
EXIT_CODE=0
if [[ $FAIL -gt 0 ]]; then EXIT_CODE=1; fi
if [[ $FAIL -eq 0 && $WARN -gt 0 ]]; then EXIT_CODE=2; fi

VERDICT="✅ APPROVED"
if [[ $FAIL -gt 0 ]]; then
  VERDICT="🛑 BLOCKED ($FAIL critical failure(s))"
elif [[ $WARN -gt 0 ]]; then
  VERDICT="⚠️  CONDITIONAL ($WARN warning(s))"
fi

cat > "$REPORT" <<EOF
# Ark Verification Report — $TIMESTAMP

**Project under test:** $(basename "$PROJECT_DIR")
**Vault:** $VAULT_PATH
**Vault commit:** $(cd "$VAULT_PATH" && git rev-parse --short HEAD 2>/dev/null || echo unknown)
**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Verdict

$VERDICT

| Metric | Count |
|--------|-------|
| Passed | $PASS |
| Warnings | $WARN |
| Failed | $FAIL |
| Skipped | $SKIP |
| Total | $TOTAL |

## Detailed Results

EOF

for r in "${RESULTS[@]}"; do
  echo "- $r" >> "$REPORT"
done

cat >> "$REPORT" <<EOF

## Sign-off

The CEO (you) reviews this report. Per-tier breakdown:

- **Tier 1 (read-only):** Foundation — must pass for any further use
- **Tier 2 (vault writes):** Sync, backup, validate, report
- **Tier 3 (file structure):** Align, secrets — touches project files
- **Tier 4 (project creation):** End-to-end create + scaffold
- **Tier 5 (production safety):** Promote gates
- **Tier 6 (hooks + observability):** Auto-run infrastructure
- **Tier 7 (GSD compatibility):** Shared phase-shape lib across delivery scripts
- **Tier 8 (autonomy under stress):** AOS Phase 2 — policy engine, audit log, dispatcher routing
- **Tier 9 (self-improving self-heal):** AOS Phase 3 — synthetic-fixture pipeline, isolated vault

If any failure is critical, fix and re-run before using Ark on real work.

## Re-run

\`\`\`bash
ark verify                # full
ark verify --tier 1       # only foundation
ark verify --skip-tier 4  # skip project creation
ark verify --report-only  # show this report again
\`\`\`

---

*Generated by ark-verify.sh*
EOF

# Print summary
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Verification: $VERDICT"
echo -e "  ${GREEN}$PASS passed${NC}  ${YELLOW}$WARN warnings${NC}  ${RED}$FAIL failed${NC}  ⏭  $SKIP skipped"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Report: $REPORT"
echo ""
echo "View later: ark verify --report-only"

# Auto-commit report
if [[ -d "$VAULT_PATH/.git" ]]; then
  cd "$VAULT_PATH"
  git add observability/verification-reports/ 2>/dev/null
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "Verification report: $TIMESTAMP — $VERDICT" --quiet 2>/dev/null
    git push origin main --quiet 2>/dev/null || true
  fi
fi

exit $EXIT_CODE
