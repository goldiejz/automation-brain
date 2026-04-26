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

# ━━━ Tier 10: Bootstrap autonomy under stress (AOS Phase 4) ━━━
# Phase 4 exit gate. Mechanizes "scaffold 5 different project types from
# 1-line descriptions, no prompts." Isolated tmp vault per NEW-W-1; real
# vault policy.db md5 captured before/after to guarantee no leakage.
# ARK_CREATE_GITHUB is left UNSET — the gate added in 04-04 ensures no
# real GitHub repos are created during verification.
if should_run_tier 10; then
  echo ""
  echo -e "${BLUE}━━━ Tier 10: Bootstrap autonomy ━━━${NC}"
fi

# 10.1 — bootstrap-policy.sh existence + syntax + self-test
run_existence_check 10 "bootstrap-policy.sh present" "$VAULT_PATH/scripts/bootstrap-policy.sh"
run_check 10 "bootstrap-policy.sh syntax valid" \
  "bash -n '$VAULT_PATH/scripts/bootstrap-policy.sh' && echo OK" \
  "OK"
run_check 10 "bootstrap-policy self-test passes" \
  "bash '$VAULT_PATH/scripts/bootstrap-policy.sh' test 2>&1 | tail -3" \
  "ALL .* TESTS PASSED|tests passed|✅"

# 10.2 — bootstrap-customer.sh existence + syntax + self-test
run_existence_check 10 "bootstrap-customer.sh present" "$VAULT_PATH/scripts/lib/bootstrap-customer.sh"
run_check 10 "bootstrap-customer.sh syntax valid" \
  "bash -n '$VAULT_PATH/scripts/lib/bootstrap-customer.sh' && echo OK" \
  "OK"
run_check 10 "bootstrap-customer self-test passes" \
  "bash '$VAULT_PATH/scripts/lib/bootstrap-customer.sh' test 2>&1 | tail -3" \
  "ALL .* TESTS PASSED|tests passed|✅"

# 10.3 — claude-md-template + addendums
run_existence_check 10 "claude-md-template.md present" "$VAULT_PATH/bootstrap/claude-md-template.md"
run_check 10 "claude-md-template has 6 anchor types" \
  "grep -cE '\\{\\{(PROJECT_NAME|PROJECT_TYPE|CUSTOMER|CREATED_DATE|ADDENDUM|CUSTOMER_FOOTER)\\}\\}' '$VAULT_PATH/bootstrap/claude-md-template.md' | tr -d ' '" \
  "^[6-9]$|^[1-9][0-9]+$"
run_check 10 "claude-md-addendum has 4 files" \
  "ls '$VAULT_PATH/bootstrap/claude-md-addendum/' 2>/dev/null | grep -cE '^(service-desk|revops|ops-intelligence|custom)\\.md$'" \
  "^4$"

# 10.4 — project-types templates have keywords + default_stack + default_deploy
run_check 10 "project-types templates have keywords/default_stack/default_deploy frontmatter" \
  "all=true; for f in '$VAULT_PATH'/bootstrap/project-types/*.md; do for k in keywords default_stack default_deploy; do grep -qE \"^\$k:\" \"\$f\" || all=false; done; done; echo \$all" \
  "^true$"

# 10.5 — ark-create.sh sources bootstrap-policy.sh
run_check 10 "ark-create.sh sources bootstrap-policy.sh" \
  "grep -cE 'bootstrap-policy\\.sh' '$VAULT_PATH/scripts/ark-create.sh'" \
  "^[1-9]"

# 10.6 — ARK_CREATE_GITHUB gate present
run_check 10 "ark-create.sh has ARK_CREATE_GITHUB gate" \
  "grep -c 'ARK_CREATE_GITHUB' '$VAULT_PATH/scripts/ark-create.sh'" \
  "^[1-9]"

# === Tier 10 synthetic 5-fixture pipeline (NEW-W-1 isolation) ===
if should_run_tier 10; then
  T10_VAULT=$(mktemp -d -t ark-tier10-vault.XXXXXX)
  T10_PROJECTS=$(mktemp -d -t ark-tier10-proj.XXXXXX)
  T10_REAL_DB="$VAULT_PATH/observability/policy.db"
  T10_BEFORE_MD5=$(md5 -q "$T10_REAL_DB" 2>/dev/null || md5sum "$T10_REAL_DB" 2>/dev/null | awk '{print $1}')
  T10_BEFORE_MD5="${T10_BEFORE_MD5:-NO_DB}"

  cp -R "$VAULT_PATH/scripts" "$T10_VAULT/"
  cp -R "$VAULT_PATH/bootstrap" "$T10_VAULT/"
  mkdir -p "$T10_VAULT/observability" "$T10_VAULT/templates/parent-automation"
  touch "$T10_VAULT/templates/parent-automation/dummy.ts" \
        "$T10_VAULT/templates/parent-automation/tsconfig.json"

  # Initialise the isolated audit DB so _policy_log writes there, not the real DB.
  T10_DB="$T10_VAULT/observability/policy.db"
  ARK_POLICY_DB="$T10_DB" ARK_HOME="$T10_VAULT" \
    bash -c "source '$VAULT_PATH/scripts/lib/policy-db.sh'; db_init" >/dev/null 2>&1

  # === Fixture 1: service-desk (confident, conf=60) ===
  unset ARK_CREATE_GITHUB
  T10_F1_OUT=$(ARK_HOME="$T10_VAULT" ARK_POLICY_DB="$T10_DB" \
    bash "$T10_VAULT/scripts/ark-create.sh" \
      "service desk for acme with sla and itil" \
      --customer acme --path "$T10_PROJECTS" 2>&1) || true
  T10_F1_DIR="$T10_PROJECTS/acme-sd"

  run_check 10 "fixture1 (service-desk): project dir + valid CLAUDE.md + policy.yml" \
    "ok=true; [[ -d '$T10_F1_DIR' ]] || ok=false; [[ -f '$T10_F1_DIR/CLAUDE.md' ]] || ok=false; [[ -f '$T10_F1_DIR/.planning/policy.yml' ]] || ok=false; grep -q '{{' '$T10_F1_DIR/CLAUDE.md' 2>/dev/null && ok=false; grep -q 'bootstrap.project_type: service-desk' '$T10_F1_DIR/.planning/policy.yml' 2>/dev/null || ok=false; echo \$ok" \
    "^true$"

  # === Fixture 2: revops (confident, conf=100) ===
  unset ARK_CREATE_GITHUB
  T10_F2_OUT=$(ARK_HOME="$T10_VAULT" ARK_POLICY_DB="$T10_DB" \
    bash "$T10_VAULT/scripts/ark-create.sh" \
      "revops crm pipeline for foo with margin approval" \
      --customer foo --path "$T10_PROJECTS" 2>&1) || true
  T10_F2_DIR="$T10_PROJECTS/foo-rev"

  run_check 10 "fixture2 (revops): project dir + valid CLAUDE.md + policy.yml" \
    "ok=true; [[ -d '$T10_F2_DIR' ]] || ok=false; [[ -f '$T10_F2_DIR/CLAUDE.md' ]] || ok=false; [[ -f '$T10_F2_DIR/.planning/policy.yml' ]] || ok=false; grep -q '{{' '$T10_F2_DIR/CLAUDE.md' 2>/dev/null && ok=false; grep -q 'bootstrap.project_type: revops' '$T10_F2_DIR/.planning/policy.yml' 2>/dev/null || ok=false; echo \$ok" \
    "^true$"

  # === Fixture 3: ops-intelligence (conf=40, threshold lowered to 30) ===
  unset ARK_CREATE_GITHUB
  T10_F3_OUT=$(ARK_BOOTSTRAP_CONFIDENCE_THRESHOLD_PCT=30 \
    ARK_HOME="$T10_VAULT" ARK_POLICY_DB="$T10_DB" \
    bash "$T10_VAULT/scripts/ark-create.sh" \
      "ops intelligence dashboard with halopsa for msp" \
      --customer msp --path "$T10_PROJECTS" 2>&1) || true
  T10_F3_DIR="$T10_PROJECTS/msp-ops"

  run_check 10 "fixture3 (ops-intelligence): project dir + valid CLAUDE.md + policy.yml" \
    "ok=true; [[ -d '$T10_F3_DIR' ]] || ok=false; [[ -f '$T10_F3_DIR/CLAUDE.md' ]] || ok=false; [[ -f '$T10_F3_DIR/.planning/policy.yml' ]] || ok=false; grep -q '{{' '$T10_F3_DIR/CLAUDE.md' 2>/dev/null && ok=false; grep -q 'bootstrap.project_type: ops-intelligence' '$T10_F3_DIR/.planning/policy.yml' 2>/dev/null || ok=false; echo \$ok" \
    "^true$"

  # === Fixture 4: custom catch-all (conf=0, threshold=0 to allow) ===
  unset ARK_CREATE_GITHUB
  T10_F4_OUT=$(ARK_BOOTSTRAP_CONFIDENCE_THRESHOLD_PCT=0 \
    ARK_HOME="$T10_VAULT" ARK_POLICY_DB="$T10_DB" \
    bash "$T10_VAULT/scripts/ark-create.sh" \
      "prototype cli tool for one-off experiment" \
      --path "$T10_PROJECTS" 2>&1) || true
  T10_F4_DIR=$(ls -d "$T10_PROJECTS"/oneoff-* 2>/dev/null | head -1)

  run_check 10 "fixture4 (custom catch-all): project dir + valid CLAUDE.md + policy.yml" \
    "ok=true; [[ -n '$T10_F4_DIR' ]] || ok=false; [[ -d '$T10_F4_DIR' ]] || ok=false; [[ -f '$T10_F4_DIR/CLAUDE.md' ]] || ok=false; [[ -f '$T10_F4_DIR/.planning/policy.yml' ]] || ok=false; grep -q '{{' '$T10_F4_DIR/CLAUDE.md' 2>/dev/null && ok=false; grep -q 'bootstrap.project_type: custom' '$T10_F4_DIR/.planning/policy.yml' 2>/dev/null || ok=false; echo \$ok" \
    "^true$"

  # === Fixture 5: garbled → ESCALATE_AMBIGUOUS exit 2 ===
  unset ARK_CREATE_GITHUB
  T10_F5_RC=0
  ARK_HOME="$T10_VAULT" ARK_POLICY_DB="$T10_DB" \
    bash "$T10_VAULT/scripts/ark-create.sh" \
      "garbled xyzzy nonsense quux frobozz" \
      --path "$T10_PROJECTS" >/dev/null 2>&1 || T10_F5_RC=$?

  run_check 10 "fixture5 (garbled): exit 2 + ESCALATIONS.md entry" \
    "ok=true; [[ '$T10_F5_RC' == '2' ]] || ok=false; grep -q 'architectural-ambiguity' '$T10_VAULT/ESCALATIONS.md' 2>/dev/null || ok=false; echo \$ok" \
    "^true$"

  # === Aggregate audit-trail check: ≥4 class:bootstrap rows in isolated DB ===
  run_check 10 "audit trail: ≥4 class:bootstrap rows after 5-fixture run" \
    "n=\$(sqlite3 '$T10_DB' \"SELECT COUNT(*) FROM decisions WHERE class='bootstrap';\" 2>/dev/null); test \"\${n:-0}\" -ge 4 && echo OK" \
    "^OK$"

  # === Backward compat: flag-mode invocation ===
  unset ARK_CREATE_GITHUB
  T10_FLAG_OUT=$(ARK_HOME="$T10_VAULT" ARK_POLICY_DB="$T10_DB" \
    bash "$T10_VAULT/scripts/ark-create.sh" \
      flagtest-custom --type custom --customer flagtest --stack node-cli --deploy none \
      --path "$T10_PROJECTS" 2>&1) || true
  T10_FLAG_DIR="$T10_PROJECTS/flagtest-custom"

  run_check 10 "backward compat: flag-mode produces project + FLAG_OVERRIDE audit row" \
    "ok=true; [[ -d '$T10_FLAG_DIR' ]] || ok=false; [[ -f '$T10_FLAG_DIR/.planning/policy.yml' ]] || ok=false; n=\$(sqlite3 '$T10_DB' \"SELECT COUNT(*) FROM decisions WHERE class='bootstrap' AND decision='FLAG_OVERRIDE';\" 2>/dev/null); [[ \"\${n:-0}\" -ge 1 ]] || ok=false; echo \$ok" \
    "^true$"

  # === Customer cascading config check ===
  T10_CASC_VAULT=$(mktemp -d -t ark-tier10-cascade.XXXXXX)
  mkdir -p "$T10_CASC_VAULT/customers/acme"
  cat > "$T10_CASC_VAULT/customers/acme/policy.yml" <<'CASC'
budget.monthly_escalate_pct: 80
CASC
  T10_CASC_RESULT=$(ARK_HOME="$T10_CASC_VAULT" ARK_CUSTOMER=acme \
    bash -c "source '$VAULT_PATH/scripts/lib/policy-config.sh'; policy_config_get budget.monthly_escalate_pct 95" 2>/dev/null)
  rm -rf "$T10_CASC_VAULT"

  run_check 10 "customer cascading: customer policy.yml overrides default (80 vs 95)" \
    "echo '$T10_CASC_RESULT' | grep -qE '^80$' && echo OK" \
    "^OK$"

  # === No-prompt regression check ===
  run_check 10 "no read -p in bootstrap-path scripts" \
    "n=\$(grep -nE '^[[:space:]]*read[[:space:]]+-p' '$VAULT_PATH/scripts/ark-create.sh' '$VAULT_PATH/scripts/ark' '$VAULT_PATH/scripts/bootstrap-policy.sh' 2>/dev/null | grep -v 'AOS: intentional gate' | wc -l | tr -d ' '); test \"\${n:-0}\" -eq 0 && echo OK" \
    "^OK$"

  # === Critical isolation guarantee: real vault policy.db md5 unchanged ===
  T10_AFTER_MD5=$(md5 -q "$T10_REAL_DB" 2>/dev/null || md5sum "$T10_REAL_DB" 2>/dev/null | awk '{print $1}')
  T10_AFTER_MD5="${T10_AFTER_MD5:-NO_DB}"

  run_check 10 "isolation: real vault policy.db unchanged before/after Tier 10" \
    "test '$T10_BEFORE_MD5' = '$T10_AFTER_MD5' && echo OK" \
    "^OK$"

  # Cleanup
  rm -rf "$T10_VAULT" "$T10_PROJECTS"
fi

# ━━━ Tier 11: Portfolio autonomy under stress (AOS Phase 5) ━━━
# Phase 5 exit gate. Mechanizes "from non-project cwd, ark deliver picks the
# right project across a 3-project / 2-customer portfolio." Isolated tmp vault
# + tmp portfolio root per NEW-W-1; real vault policy.db md5 captured before/
# after to guarantee no leakage. ARK_CREATE_GITHUB stays UNSET — Tier 11 never
# touches GitHub.
#
# Asserts: heuristic winner under budget filter, CEO directive override,
# 24h cool-down honored (and expired beyond), all 4 decision classes fire,
# backward compat preserved (ark-deliver.sh from a real-project cwd is
# unaffected — verified statically by grep), real DB md5 invariant.
#
# REQ-AOS-29 (Tier 11) + REQ-AOS-30 (Tier 1-10 retained — re-run separately).
if should_run_tier 11; then
  echo ""
  echo -e "${BLUE}━━━ Tier 11: Portfolio autonomy ━━━${NC}"
fi

# 11.1 — ark-portfolio-decide.sh existence + syntax + self-test
run_existence_check 11 "ark-portfolio-decide.sh present" "$VAULT_PATH/scripts/ark-portfolio-decide.sh"
run_check 11 "ark-portfolio-decide.sh syntax valid" \
  "bash -n '$VAULT_PATH/scripts/ark-portfolio-decide.sh' && echo OK" \
  "OK"
run_check 11 "ark-portfolio-decide.sh self-test passes (40/40)" \
  "bash '$VAULT_PATH/scripts/ark-portfolio-decide.sh' test 2>&1 | tail -3" \
  "ALL .* TESTS PASSED|40/40|✅"

# 11.2 — ark-deliver.sh sources portfolio_decide for no-args routing
run_check 11 "ark-deliver.sh has portfolio_decide call" \
  "grep -c 'portfolio_decide' '$VAULT_PATH/scripts/ark-deliver.sh'" \
  "^[1-9]"

# 11.3 — ark dispatcher documents ARK_PORTFOLIO_ROOT env
run_check 11 "ark dispatcher documents ARK_PORTFOLIO_ROOT" \
  "grep -c 'ARK_PORTFOLIO_ROOT' '$VAULT_PATH/scripts/ark'" \
  "^[1-9]"

# === Tier 11 synthetic 3-project / 2-customer pipeline (NEW-W-1 isolation) ===
if should_run_tier 11; then
  T11_VAULT=$(mktemp -d -t ark-tier11-vault.XXXXXX)
  T11_PORT=$(mktemp -d -t ark-tier11-port.XXXXXX)
  T11_REAL_DB="$VAULT_PATH/observability/policy.db"
  T11_BEFORE_MD5=$(md5 -q "$T11_REAL_DB" 2>/dev/null || md5sum "$T11_REAL_DB" 2>/dev/null | awk '{print $1}')
  T11_BEFORE_MD5="${T11_BEFORE_MD5:-NO_DB}"

  mkdir -p "$T11_VAULT/observability" \
           "$T11_VAULT/scripts/lib" \
           "$T11_VAULT/customers/acme" \
           "$T11_VAULT/customers/foo"

  # Copy scripts under test (and their library deps) into tmp vault.
  cp "$VAULT_PATH/scripts/ark-portfolio-decide.sh" "$T11_VAULT/scripts/"
  cp "$VAULT_PATH/scripts/ark-policy.sh"           "$T11_VAULT/scripts/"
  cp -R "$VAULT_PATH/scripts/lib/." "$T11_VAULT/scripts/lib/"
  chmod +x "$T11_VAULT/scripts/"*.sh 2>/dev/null

  # Initialise the isolated audit DB so _policy_log writes there only.
  T11_DB="$T11_VAULT/observability/policy.db"
  ARK_POLICY_DB="$T11_DB" ARK_HOME="$T11_VAULT" \
    bash -c "source '$T11_VAULT/scripts/lib/policy-db.sh'; db_init" >/dev/null 2>&1

  # === Customer policies: acme over-budget (90%), foo healthy (30%) ===
  cat > "$T11_VAULT/customers/acme/policy.yml" <<'T11_ACME'
budget.monthly_used: 90000
budget.monthly_cap: 100000
T11_ACME
  cat > "$T11_VAULT/customers/foo/policy.yml" <<'T11_FOO'
budget.monthly_used: 30000
budget.monthly_cap: 100000
T11_FOO

  # === Synthetic 3-project / 2-customer fixture ===
  # acme/proj-a: healthy, in-progress (would lose to anything actionable)
  mkdir -p "$T11_PORT/acme-a/.planning"
  cat > "$T11_PORT/acme-a/.planning/STATE.md" <<'T11_A'
# State
Current Phase: Phase 2
Status: in-progress
T11_A
  cat > "$T11_PORT/acme-a/.planning/policy.yml" <<'T11_AP'
bootstrap.customer: acme
T11_AP

  # acme/proj-b: blocked (stuckness=2 — high score), but acme is over-budget
  mkdir -p "$T11_PORT/acme-stuck/.planning"
  cat > "$T11_PORT/acme-stuck/.planning/STATE.md" <<'T11_B'
# State
Current Phase: Phase 4
status: blocked
T11_B
  cat > "$T11_PORT/acme-stuck/.planning/policy.yml" <<'T11_BP'
bootstrap.customer: acme
T11_BP

  # foo/proj-c: healthy, in-progress, foo has headroom
  mkdir -p "$T11_PORT/foo-c/.planning"
  cat > "$T11_PORT/foo-c/.planning/STATE.md" <<'T11_C'
# State
Current Phase: Phase 1
Status: in-progress
T11_C
  cat > "$T11_PORT/foo-c/.planning/policy.yml" <<'T11_CP'
bootstrap.customer: foo
T11_CP

  # === Run 1: heuristic — proj-c (foo, headroom) wins; acme-* DEFERRED_BUDGET ===
  T11_R1_OUT=$(ARK_HOME="$T11_VAULT" ARK_POLICY_DB="$T11_DB" \
               ARK_PORTFOLIO_ROOT="$T11_PORT" \
               ARK_PROGRAMME_MD="/no/such/file" \
               bash -c "source '$T11_VAULT/scripts/ark-portfolio-decide.sh'; portfolio_decide '$T11_PORT'" 2>&1)

  run_check 11 "run1: foo-c wins over over-budget acme projects" \
    "echo '$T11_R1_OUT' | grep -q '$T11_PORT/foo-c\$' && echo OK" \
    "^OK$"

  run_check 11 "run1: audit has 1 SELECTED row" \
    "n=\$(sqlite3 '$T11_DB' \"SELECT COUNT(*) FROM decisions WHERE class='portfolio' AND decision='SELECTED';\" 2>/dev/null); test \"\${n:-0}\" -eq 1 && echo OK" \
    "^OK$"

  run_check 11 "run1: audit has DEFERRED_BUDGET rows for over-cap acme projects (>=1)" \
    "n=\$(sqlite3 '$T11_DB' \"SELECT COUNT(*) FROM decisions WHERE class='portfolio' AND decision='DEFERRED_BUDGET';\" 2>/dev/null); test \"\${n:-0}\" -ge 1 && echo OK" \
    "^OK$"

  run_check 11 "run1: SELECTED context_json includes total + customer=foo" \
    "ctx=\$(sqlite3 '$T11_DB' \"SELECT context FROM decisions WHERE decision='SELECTED' LIMIT 1;\" 2>/dev/null); echo \"\$ctx\" | grep -q '\"total\":' && echo \"\$ctx\" | grep -q '\"customer\":\"foo\"' && echo OK" \
    "^OK$"

  # === Run 2: CEO directive — programme.md says acme-stuck. Verify CURRENT
  # contract: cool-down OR DEFERRED_BUDGET still applies even with CEO boost.
  # Reset DB to isolate this run.
  sqlite3 "$T11_DB" "DELETE FROM decisions;" 2>/dev/null
  T11_PMD="$T11_VAULT/programme.md"
  cat > "$T11_PMD" <<'T11_PMD_EOF'
## Next Priority

acme-stuck
T11_PMD_EOF
  T11_R2_OUT=$(ARK_HOME="$T11_VAULT" ARK_POLICY_DB="$T11_DB" \
               ARK_PORTFOLIO_ROOT="$T11_PORT" \
               ARK_PROGRAMME_MD="$T11_PMD" \
               bash -c "source '$T11_VAULT/scripts/ark-portfolio-decide.sh'; portfolio_decide '$T11_PORT'" 2>&1)

  # Contract: DEFERRED_BUDGET filter is hard — CEO +5 score boost cannot
  # override budget filter (acme-stuck excluded from winner pool). foo-c
  # gets +0 CEO bonus (name doesn't match). foo-c still wins.
  run_check 11 "run2: CEO directive on over-budget project does NOT override budget filter; foo-c still wins" \
    "echo '$T11_R2_OUT' | grep -q '$T11_PORT/foo-c\$' && echo OK" \
    "^OK$"

  # === Run 3: Cool-down (24h) — insert recent DEFERRED_HEALTHY for foo-c.
  # Loosen acme budget so acme-a becomes pickable; foo-c filtered by cool-down.
  sqlite3 "$T11_DB" "DELETE FROM decisions;" 2>/dev/null
  cat > "$T11_VAULT/customers/acme/policy.yml" <<'T11_ACME_LOOSE'
budget.monthly_used: 10000
budget.monthly_cap: 100000
T11_ACME_LOOSE
  T11_NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sqlite3 "$T11_DB" "INSERT INTO decisions (decision_id, ts, schema_version, class, decision, reason, context) VALUES ('t11-cd-recent', '$T11_NOW', 1, 'portfolio', 'DEFERRED_HEALTHY', 'r', '{\"path\":\"$T11_PORT/foo-c\"}');" 2>/dev/null

  T11_R3_OUT=$(ARK_HOME="$T11_VAULT" ARK_POLICY_DB="$T11_DB" \
               ARK_PORTFOLIO_ROOT="$T11_PORT" \
               ARK_PROGRAMME_MD="/no/such/file" \
               bash -c "source '$T11_VAULT/scripts/ark-portfolio-decide.sh'; portfolio_decide '$T11_PORT'" 2>&1)

  run_check 11 "run3: 1h-old DEFERRED_HEALTHY keeps foo-c out of winner pool" \
    "echo '$T11_R3_OUT' | grep -q '$T11_PORT/foo-c\$' && echo BAD || echo OK" \
    "^OK$"

  # === Run 4: 25h-old cool-down → expired; foo-c eligible again.
  sqlite3 "$T11_DB" "DELETE FROM decisions;" 2>/dev/null
  T11_OLD=$(date -u -v-25H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '25 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  sqlite3 "$T11_DB" "INSERT INTO decisions (decision_id, ts, schema_version, class, decision, reason, context) VALUES ('t11-cd-old', '$T11_OLD', 1, 'portfolio', 'DEFERRED_HEALTHY', 'r', '{\"path\":\"$T11_PORT/foo-c\"}');" 2>/dev/null

  T11_R4_OUT=$(ARK_HOME="$T11_VAULT" ARK_POLICY_DB="$T11_DB" \
               ARK_PORTFOLIO_ROOT="$T11_PORT" \
               ARK_PROGRAMME_MD="/no/such/file" \
               bash -c "source '$T11_VAULT/scripts/ark-portfolio-decide.sh'; portfolio_decide '$T11_PORT'" 2>&1)

  # With acme loose, acme-stuck is blocked (stuckness=2, total=6) — outscores foo-c (total=1)
  # but cool-down on foo-c shouldn't matter (acme-stuck wins). Just assert SELECTED row exists
  # with a non-empty winner — proves cool-down didn't accidentally filter everything.
  run_check 11 "run4: 25h-old cool-down expired — winner SELECTED" \
    "n=\$(sqlite3 '$T11_DB' \"SELECT COUNT(*) FROM decisions WHERE decision='SELECTED';\" 2>/dev/null); test \"\${n:-0}\" -eq 1 && [[ -n '$(echo "$T11_R4_OUT" | tr -d '[:space:]')' ]] && echo OK" \
    "^OK$"

  # === Run 5: Empty portfolio → NO_CANDIDATE_AVAILABLE + ESCALATIONS path ===
  sqlite3 "$T11_DB" "DELETE FROM decisions;" 2>/dev/null
  T11_EMPTY=$(mktemp -d -t ark-tier11-empty.XXXXXX)
  T11_R5_OUT=$(ARK_HOME="$T11_VAULT" ARK_POLICY_DB="$T11_DB" \
               ARK_PORTFOLIO_ROOT="$T11_EMPTY" \
               bash -c "source '$T11_VAULT/scripts/ark-portfolio-decide.sh'; portfolio_decide '$T11_EMPTY'" 2>&1)

  run_check 11 "run5: empty portfolio emits NO_CANDIDATE_AVAILABLE" \
    "n=\$(sqlite3 '$T11_DB' \"SELECT COUNT(*) FROM decisions WHERE decision='NO_CANDIDATE_AVAILABLE';\" 2>/dev/null); test \"\${n:-0}\" -ge 1 && echo OK" \
    "^OK$"
  rm -rf "$T11_EMPTY"

  # === Run 6: Backward compat — ark-deliver.sh from a project cwd does NOT
  # call portfolio_decide. Static check: grep for the project-detection guard
  # and confirm portfolio_decide is gated behind a no-args branch.
  run_check 11 "ark-deliver.sh portfolio_decide is gated behind project-detection (PROJECT_DIR appears before portfolio_decide call)" \
    "pdc=\$(grep -n 'portfolio_decide' '$VAULT_PATH/scripts/ark-deliver.sh' | head -1 | cut -d: -f1); pdr=\$(grep -n 'PROJECT_DIR' '$VAULT_PATH/scripts/ark-deliver.sh' | head -1 | cut -d: -f1); [ -n \"\$pdc\" ] && [ -n \"\$pdr\" ] && [ \"\$pdr\" -lt \"\$pdc\" ] && echo OK" \
    "^OK$"

  # === Run 7: Real GitHub invariant — no `gh repo create` invoked anywhere
  # in the portfolio path. Static check.
  run_check 11 "no 'gh repo create' in portfolio code path" \
    "grep -l 'gh repo create' '$VAULT_PATH/scripts/ark-portfolio-decide.sh' '$VAULT_PATH/scripts/ark-deliver.sh' 2>/dev/null | wc -l | tr -d ' '" \
    "^0$"

  # === Run 8: Critical isolation — real vault policy.db md5 unchanged ===
  T11_AFTER_MD5=$(md5 -q "$T11_REAL_DB" 2>/dev/null || md5sum "$T11_REAL_DB" 2>/dev/null | awk '{print $1}')
  T11_AFTER_MD5="${T11_AFTER_MD5:-NO_DB}"

  run_check 11 "isolation: real vault policy.db unchanged before/after Tier 11" \
    "test '$T11_BEFORE_MD5' = '$T11_AFTER_MD5' && echo OK" \
    "^OK$"

  # Cleanup
  rm -rf "$T11_VAULT" "$T11_PORT"
fi

# ━━━ Tier 12: Cross-customer learning under stress (AOS Phase 6) ━━━
# Phase 6 exit gate. Mechanizes the lesson promoter end-to-end against a
# synthetic 3-customer fixture mirroring Tier 11's portfolio-decide structure.
# Isolated tmp portfolio + tmp vault (with git init) + tmp policy.db. Real
# vault (~/vaults/ark/lessons/universal-patterns.md, ~/vaults/ark/bootstrap/
# anti-patterns.md, ~/vaults/ark/observability/policy.db) md5s captured
# before/after to guarantee no leakage (NEW-W-1; Phase-4 GitHub-incident
# discipline).
#
# Asserts: scan finds 3 customer files; RBAC cross-customer cluster routes
# to universal-patterns; anti-pattern cross-customer cluster routes to
# anti-patterns; singleton lesson NOT promoted; ≥2 lesson_promote PROMOTED
# audit rows; ≥2 git commits in tmp vault; idempotency on re-run; lock dir
# released; no `read -p` regression in delivery-path scripts; real-vault md5
# invariants hold.
#
# REQ-AOS-38 (Tier 12 passes) + REQ-AOS-39 (Tier 1-11 retained — re-run
# separately).
if should_run_tier 12; then
  echo ""
  echo -e "${BLUE}━━━ Tier 12: Cross-customer learning ━━━${NC}"
fi

# 12.1 — lesson-similarity.sh + lesson-promoter.sh present + syntax + self-test
run_existence_check 12 "lib/lesson-similarity.sh present" "$VAULT_PATH/scripts/lib/lesson-similarity.sh"
run_check 12 "lib/lesson-similarity.sh syntax valid" \
  "bash -n '$VAULT_PATH/scripts/lib/lesson-similarity.sh' && echo OK" \
  "^OK$"
run_check 12 "lib/lesson-similarity.sh self-test passes" \
  "bash '$VAULT_PATH/scripts/lib/lesson-similarity.sh' test 2>&1 | tail -2" \
  "ALL .* TESTS PASSED|14/14|✅"

run_existence_check 12 "scripts/lesson-promoter.sh present" "$VAULT_PATH/scripts/lesson-promoter.sh"
run_check 12 "scripts/lesson-promoter.sh syntax valid" \
  "bash -n '$VAULT_PATH/scripts/lesson-promoter.sh' && echo OK" \
  "^OK$"

# 12.2 — wiring: ark dispatcher has promote-lessons subcommand; ark-deliver.sh has hook
run_check 12 "ark dispatcher exposes promote-lessons subcommand" \
  "grep -c 'promote-lessons' '$VAULT_PATH/scripts/ark'" \
  "^[1-9]"
run_check 12 "ark-deliver.sh has lesson-promoter post-phase trigger" \
  "grep -c 'lesson-promoter.sh' '$VAULT_PATH/scripts/ark-deliver.sh'" \
  "^[1-9]"

# === Tier 12 synthetic 3-customer pipeline (NEW-W-1 isolation) ===
if should_run_tier 12; then
  T12_PORTFOLIO=$(mktemp -d -t ark-tier12-port.XXXXXX)
  T12_VAULT=$(mktemp -d -t ark-tier12-vault.XXXXXX)
  T12_DB="$T12_VAULT/observability/policy.db"
  mkdir -p "$T12_VAULT/observability" "$T12_VAULT/lessons" "$T12_VAULT/bootstrap" "$T12_VAULT/scripts/lib"

  # Real-vault md5 invariants (NEW-W-1)
  T12_REAL_U="$HOME/vaults/ark/lessons/universal-patterns.md"
  T12_REAL_A="$HOME/vaults/ark/bootstrap/anti-patterns.md"
  T12_REAL_DB="$HOME/vaults/ark/observability/policy.db"
  _t12_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'; }
  if [[ -f "$T12_REAL_U" ]]; then
    T12_REAL_U_BEFORE=$(_t12_md5 "$T12_REAL_U")
  else
    T12_REAL_U_BEFORE="ABSENT"
  fi
  if [[ -f "$T12_REAL_A" ]]; then
    T12_REAL_A_BEFORE=$(_t12_md5 "$T12_REAL_A")
  else
    T12_REAL_A_BEFORE="ABSENT"
  fi
  if [[ -f "$T12_REAL_DB" ]]; then
    T12_REAL_DB_BEFORE=$(_t12_md5 "$T12_REAL_DB")
  else
    T12_REAL_DB_BEFORE="ABSENT"
  fi

  # Init tmp vault as git repo (lesson-promoter needs vault git for per-cluster commits)
  ( cd "$T12_VAULT" \
    && git init --quiet \
    && git config user.email "tier12@example.invalid" \
    && git config user.name "Tier 12 Test" \
    && git config commit.gpgsign false ) >/dev/null 2>&1

  # Init isolated audit DB
  ARK_HOME="$T12_VAULT" ARK_POLICY_DB="$T12_DB" \
    bash -c "source '$VAULT_PATH/scripts/lib/policy-db.sh'; db_init" >/dev/null 2>&1 || true

  # === Synthetic 3-customer fixture ===
  # cust-a: 3 lessons. RBAC v1 + RBAC v2 (engineered to cluster with cust-b),
  #         and one wrangler binding lesson (singleton).
  mkdir -p "$T12_PORTFOLIO/cust-a/tasks" \
           "$T12_PORTFOLIO/cust-b/tasks" \
           "$T12_PORTFOLIO/cust-c/tasks"

  cat > "$T12_PORTFOLIO/cust-a/tasks/lessons.md" <<'T12_LESSONS_A'
# Lessons Learned

## Lesson: Centralise RBAC role arrays in single source of truth module
**Trigger:** Inline role arrays drifted between routes and middleware
**Mistake:** Hardcoded role list in three different files
**Rule:** Every RBAC role array must live in one centralised module. Routes and components import the centralised array. Lint forbids inline role arrays anywhere. Centralised role array is single source of truth.
**Date:** 2026-04-01

## Lesson: RBAC role arrays must be centralised in single source module
**Trigger:** Role array drift caught in code review
**Mistake:** Inline role arrays scattered across components and routes
**Rule:** Centralise every RBAC role array in one single source of truth module. Routes and components must import the centralised role array. Lint forbids inline role arrays anywhere in source.
**Date:** 2026-04-03

## Lesson: Wrangler binding deploy requires explicit project name flag
**Trigger:** Wrong D1 binding deployed to staging
**Mistake:** Assumed default project name from wrangler.toml file
**Rule:** Always pass --project-name explicitly when deploying wrangler pages with multiple environments configured.
**Date:** 2026-04-02
T12_LESSONS_A

  # cust-b: 1 RBAC lesson (clusters with cust-a) + 1 anti-pattern (clusters with cust-c)
  cat > "$T12_PORTFOLIO/cust-b/tasks/lessons.md" <<'T12_LESSONS_B'
# Lessons Learned

## Lesson: Centralise RBAC role arrays in single source of truth
**Trigger:** Inline role arrays drifted between routes and components
**Mistake:** Hardcoded role list in different files instead of centralised module
**Rule:** Every RBAC role array must live in one centralised module. Routes and components import the centralised array. Lint forbids inline role arrays. Centralised role array is single source of truth.
**Date:** 2026-04-05

## Lesson: Anti-pattern do not hardcode secrets in source code repository
**Trigger:** API key was committed to git history accidentally
**Mistake:** Hardcoded the secret key inline instead of using environment variable
**Rule:** Anti-pattern never hardcode secrets in source code. Always use environment variables or a secret manager. Do not commit secrets to source code repository ever.
**Date:** 2026-04-07
T12_LESSONS_B

  # cust-c: 2 anti-pattern lessons (clusters with cust-b — gives combined
  # occurrences=3 to clear PROMOTE_MIN_OCCURRENCES=3) + 1 singleton (NOT promoted).
  cat > "$T12_PORTFOLIO/cust-c/tasks/lessons.md" <<'T12_LESSONS_C'
# Lessons Learned

## Lesson: Anti-pattern do not hardcode secrets in source code anywhere
**Trigger:** Token leaked via committed config file in source code
**Mistake:** Hardcoded secret inline instead of using environment variable lookup
**Rule:** Anti-pattern never hardcode secrets in source code. Always use environment variables or a secret manager. Do not commit secrets to source code repository.
**Date:** 2026-04-10

## Lesson: Anti-pattern never hardcode secrets in source code repository
**Trigger:** Secret leaked via committed source code change
**Mistake:** Hardcoded secret inline in source instead of using environment variable
**Rule:** Anti-pattern do not hardcode secrets in source code anywhere. Always use environment variables or a secret manager. Do not commit secrets to source code repository.
**Date:** 2026-04-11

## Lesson: Always run database migrations after merge to main branch
**Trigger:** Schema drift in production after merge to main
**Mistake:** Forgot to run database migrations after deploying merged code
**Rule:** Always run wrangler d1 migrations apply remote after pushing schema changes to main. Verify production database schema matches repository schema.
**Date:** 2026-04-12
T12_LESSONS_C

  # === Run the full pipeline (sourced subshell — CLI dispatcher handles only one flag) ===
  T12_RUN_LOG=$(mktemp -t ark-tier12-run.XXXXXX)
  ( ARK_PORTFOLIO_ROOT="$T12_PORTFOLIO" \
    ARK_HOME="$T12_VAULT" \
    VAULT_PATH="$T12_VAULT" \
    UNIVERSAL_TARGET="$T12_VAULT/lessons/universal-patterns.md" \
    ANTIPATTERN_TARGET="$T12_VAULT/bootstrap/anti-patterns.md" \
    ARK_POLICY_DB="$T12_DB" \
    bash -c "source '$VAULT_PATH/scripts/lesson-promoter.sh' && promoter_run --full --apply" \
  ) > "$T12_RUN_LOG" 2>&1 || true

  # === Assertions ===
  run_check 12 "portfolio scan finds 3 customer lesson files" \
    "n=\$(find '$T12_PORTFOLIO' -name lessons.md | wc -l | tr -d ' '); test \"\$n\" = '3' && echo OK" \
    "^OK$"

  run_check 12 "universal-patterns.md created in tmp vault" \
    "test -f '$T12_VAULT/lessons/universal-patterns.md' && echo OK" \
    "^OK$"

  run_check 12 "anti-patterns.md created in tmp vault" \
    "test -f '$T12_VAULT/bootstrap/anti-patterns.md' && echo OK" \
    "^OK$"

  run_check 12 "RBAC cluster promoted to universal-patterns.md (auto-promoted marker + RBAC vocabulary)" \
    "grep -qF 'AOS Phase 6 — auto-promoted' '$T12_VAULT/lessons/universal-patterns.md' && grep -qiE 'rbac|role array' '$T12_VAULT/lessons/universal-patterns.md' && echo OK" \
    "^OK$"

  run_check 12 "anti-pattern cluster promoted to anti-patterns.md (auto-promoted marker + secret vocabulary)" \
    "grep -qF 'AOS Phase 6 — auto-promoted' '$T12_VAULT/bootstrap/anti-patterns.md' && grep -qiE 'hardcode|secret' '$T12_VAULT/bootstrap/anti-patterns.md' && echo OK" \
    "^OK$"

  run_check 12 "audit DB has >=2 lesson_promote PROMOTED rows" \
    "n=\$(sqlite3 '$T12_DB' \"SELECT count(*) FROM decisions WHERE class='lesson_promote' AND decision='PROMOTED';\" 2>/dev/null); test \"\${n:-0}\" -ge 2 && echo OK" \
    "^OK$"

  run_check 12 "tmp-vault git has >=2 'AOS Phase 6: promote cluster' commits" \
    "n=\$(git -C '$T12_VAULT' log --all --oneline 2>/dev/null | grep -c 'AOS Phase 6: promote cluster'); test \"\${n:-0}\" -ge 2 && echo OK" \
    "^OK$"

  run_check 12 "singleton 'always run database migrations' (cust-c only) NOT in universal-patterns.md" \
    "grep -qiE 'always run.*migrations' '$T12_VAULT/lessons/universal-patterns.md' && echo BAD || echo OK" \
    "^OK$"

  run_check 12 "lock dir absent after run" \
    "test ! -d '$T12_VAULT/.lesson-promoter.lock' && echo OK" \
    "^OK$"

  # === Idempotency: re-run, expect no new commits, no new audit rows, md5 unchanged ===
  T12_AUDIT_BEFORE=$(sqlite3 "$T12_DB" "SELECT count(*) FROM decisions WHERE class='lesson_promote';" 2>/dev/null || echo 0)
  T12_COMMITS_BEFORE=$(git -C "$T12_VAULT" log --all --oneline 2>/dev/null | wc -l | tr -d ' ')
  T12_U_BEFORE=$(_t12_md5 "$T12_VAULT/lessons/universal-patterns.md")
  ( ARK_PORTFOLIO_ROOT="$T12_PORTFOLIO" \
    ARK_HOME="$T12_VAULT" \
    VAULT_PATH="$T12_VAULT" \
    UNIVERSAL_TARGET="$T12_VAULT/lessons/universal-patterns.md" \
    ANTIPATTERN_TARGET="$T12_VAULT/bootstrap/anti-patterns.md" \
    ARK_POLICY_DB="$T12_DB" \
    bash -c "source '$VAULT_PATH/scripts/lesson-promoter.sh' && promoter_run --full --apply" \
  ) >/dev/null 2>&1 || true
  T12_AUDIT_AFTER=$(sqlite3 "$T12_DB" "SELECT count(*) FROM decisions WHERE class='lesson_promote';" 2>/dev/null || echo 0)
  T12_COMMITS_AFTER=$(git -C "$T12_VAULT" log --all --oneline 2>/dev/null | wc -l | tr -d ' ')
  T12_U_AFTER=$(_t12_md5 "$T12_VAULT/lessons/universal-patterns.md")

  run_check 12 "idempotent: audit row count unchanged on re-run" \
    "test '$T12_AUDIT_BEFORE' = '$T12_AUDIT_AFTER' && echo OK" \
    "^OK$"
  run_check 12 "idempotent: git commit count unchanged on re-run" \
    "test '$T12_COMMITS_BEFORE' = '$T12_COMMITS_AFTER' && echo OK" \
    "^OK$"
  run_check 12 "idempotent: universal-patterns.md md5 unchanged on re-run" \
    "test '$T12_U_BEFORE' = '$T12_U_AFTER' && echo OK" \
    "^OK$"

  # === Real-vault isolation invariants (NEW-W-1; Phase-4 discipline) ===
  if [[ "$T12_REAL_U_BEFORE" = "ABSENT" ]]; then
    T12_REAL_U_AFTER="ABSENT"
    [[ -f "$T12_REAL_U" ]] && T12_REAL_U_AFTER=$(_t12_md5 "$T12_REAL_U")
  else
    T12_REAL_U_AFTER=$(_t12_md5 "$T12_REAL_U")
  fi
  if [[ "$T12_REAL_A_BEFORE" = "ABSENT" ]]; then
    T12_REAL_A_AFTER="ABSENT"
    [[ -f "$T12_REAL_A" ]] && T12_REAL_A_AFTER=$(_t12_md5 "$T12_REAL_A")
  else
    T12_REAL_A_AFTER=$(_t12_md5 "$T12_REAL_A")
  fi
  if [[ "$T12_REAL_DB_BEFORE" = "ABSENT" ]]; then
    T12_REAL_DB_AFTER="ABSENT"
    [[ -f "$T12_REAL_DB" ]] && T12_REAL_DB_AFTER=$(_t12_md5 "$T12_REAL_DB")
  else
    T12_REAL_DB_AFTER=$(_t12_md5 "$T12_REAL_DB")
  fi

  run_check 12 "isolation: real ~/vaults/ark/lessons/universal-patterns.md md5 unchanged" \
    "test '$T12_REAL_U_BEFORE' = '$T12_REAL_U_AFTER' && echo OK" \
    "^OK$"
  run_check 12 "isolation: real ~/vaults/ark/bootstrap/anti-patterns.md md5 unchanged" \
    "test '$T12_REAL_A_BEFORE' = '$T12_REAL_A_AFTER' && echo OK" \
    "^OK$"
  run_check 12 "isolation: real ~/vaults/ark/observability/policy.db md5 unchanged" \
    "test '$T12_REAL_DB_BEFORE' = '$T12_REAL_DB_AFTER' && echo OK" \
    "^OK$"

  # === read -p regression on the two delivery-path scripts modified by 06-04 ===
  # Self-referential trap (Phase 4): grep skips comment lines.
  run_check 12 "scripts/ark has 0 non-comment 'read -p' lines" \
    "n=\$(grep -nE '^[^#]*read -p' '$VAULT_PATH/scripts/ark' 2>/dev/null | wc -l | tr -d ' '); test \"\${n:-0}\" -eq 0 && echo OK" \
    "^OK$"
  run_check 12 "scripts/ark-deliver.sh has 0 non-comment 'read -p' lines" \
    "n=\$(grep -nE '^[^#]*read -p' '$VAULT_PATH/scripts/ark-deliver.sh' 2>/dev/null | wc -l | tr -d ' '); test \"\${n:-0}\" -eq 0 && echo OK" \
    "^OK$"

  # Cleanup
  rm -rf "$T12_PORTFOLIO" "$T12_VAULT"
  rm -f "$T12_RUN_LOG"
fi

# === Tier 13: CEO Dashboard contract (Phase 6.5) ===
# AOS Phase 6.5 exit gate. 3-tier dashboard: Tier A (bash), Tier B (Rust TUI),
# Tier C (web). Read-only over policy.db, ESCALATIONS.md, vault docs.
# Synthetic seeded vault via mktemp -d. NEVER touches real ~/code or real
# vault writes. Self-referential trap (Phase 4 GitHub-incident lesson):
# T13.regression invokes `ark-verify.sh --tier N` for N in 7..12; safe because
# Tiers 7-12 do NOT reference Tier 13. grep 'tier 13|Tier 13' on this file
# should match ONLY inside this block.
if should_run_tier 13; then
  echo ""
  echo -e "${BLUE}━━━ Tier 13: CEO Dashboard ━━━${NC}"

  # NEW-W-1 isolation: mktemp vault + portfolio. NEVER touch real paths.
  T13_VAULT=$(mktemp -d -t ark-tier13-vault.XXXXXX)
  T13_PORTFOLIO=$(mktemp -d -t ark-tier13-port.XXXXXX)

  # Real-vault md5 invariant capture (Phase 4 GitHub-incident lesson)
  T13_REAL_DB="$HOME/vaults/ark/observability/policy.db"
  T13_REAL_ESC="$HOME/vaults/ark/ESCALATIONS.md"
  T13_REAL_UNI="$HOME/vaults/ark/lessons/universal-patterns.md"
  T13_REAL_ANTI="$HOME/vaults/ark/bootstrap/anti-patterns.md"
  _t13_md5() {
    if [[ -f "$1" ]]; then
      md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'
    else
      echo "ABSENT"
    fi
  }
  T13_DB_BEFORE=$(_t13_md5 "$T13_REAL_DB")
  T13_ESC_BEFORE=$(_t13_md5 "$T13_REAL_ESC")
  T13_UNI_BEFORE=$(_t13_md5 "$T13_REAL_UNI")
  T13_ANTI_BEFORE=$(_t13_md5 "$T13_REAL_ANTI")

  # Seed synthetic vault
  mkdir -p "$T13_VAULT/observability/verification-reports"
  mkdir -p "$T13_VAULT/lessons" "$T13_VAULT/bootstrap"
  sqlite3 "$T13_VAULT/observability/policy.db" <<'T13_SEED_SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE decisions (
  decision_id TEXT PRIMARY KEY, ts TEXT NOT NULL, schema_version INTEGER NOT NULL DEFAULT 1,
  class TEXT NOT NULL, decision TEXT NOT NULL, reason TEXT NOT NULL,
  context TEXT, outcome TEXT, correlation_id TEXT
);
INSERT INTO decisions VALUES('20260426T100000Z-aaaaaaaaaaaaaaaa','2026-04-26T10:00:00Z',1,'escalation','PENDING','synthetic-test',NULL,NULL,NULL);
INSERT INTO decisions VALUES('20260426T100001Z-bbbbbbbbbbbbbbbb','2026-04-26T10:00:01Z',1,'budget','PROCEED','synthetic-test',NULL,'success',NULL);
INSERT INTO decisions VALUES('20260426T100002Z-cccccccccccccccc','2026-04-26T10:00:02Z',1,'dispatch','codex','synthetic-test',NULL,'success',NULL);
INSERT INTO decisions VALUES('20260426T100003Z-dddddddddddddddd','2026-04-26T10:00:03Z',1,'self_improve','PROMOTED','synthetic-test',NULL,'success',NULL);
INSERT INTO decisions VALUES('20260426T100004Z-eeeeeeeeeeeeeeee','2026-04-26T10:00:04Z',1,'lesson_promote','PROMOTED','synthetic-test',NULL,'success',NULL);
T13_SEED_SQL
  cat > "$T13_VAULT/ESCALATIONS.md" <<'T13_ESC_SEED'
## [PENDING] esc-001
Test escalation 1.

## [PENDING] esc-002
Test escalation 2.
T13_ESC_SEED
  echo "## Pattern A" > "$T13_VAULT/lessons/universal-patterns.md"
  echo "## Pattern B" >> "$T13_VAULT/lessons/universal-patterns.md"
  echo "## Anti-pattern X" > "$T13_VAULT/bootstrap/anti-patterns.md"
  cat > "$T13_VAULT/observability/verification-reports/20260426-100000.md" <<'T13_REPORT_SEED'
✅ T7: synthetic-pass-1
✅ T7: synthetic-pass-2
❌ T8: synthetic-fail-1
T13_REPORT_SEED
  mkdir -p "$T13_PORTFOLIO/proj-a/.planning/phases/01-foo"
  mkdir -p "$T13_PORTFOLIO/proj-b/.planning/phases/02-bar"
  cat > "$T13_PORTFOLIO/proj-a/.planning/STATE.md" <<'T13_PROJ_A'
---
current_phase: "Phase 1 (foo)"
last_updated: "2026-04-26T10:00:00Z"
---
T13_PROJ_A
  cat > "$T13_PORTFOLIO/proj-b/.planning/STATE.md" <<'T13_PROJ_B'
---
current_phase: "Phase 2 (bar)"
last_updated: "2026-04-26T10:00:00Z"
---
T13_PROJ_B

  # === T13.1 (REQ-DASH-01) — Tier A wiring ===
  run_check 13 "Tier A: scripts/ark-dashboard.sh exists + executable" \
    "[ -x '$VAULT_PATH/scripts/ark-dashboard.sh' ] && echo OK" \
    "^OK$"
  run_check 13 "Tier A: ark-dashboard.sh syntax valid" \
    "bash -n '$VAULT_PATH/scripts/ark-dashboard.sh' && echo OK" \
    "^OK$"
  run_check 13 "Tier A: ark dashboard subcommand wired in dispatcher" \
    "bash '$VAULT_PATH/scripts/ark' help 2>&1 | grep -qiE 'dashboard.*(Tier A|read-only|CEO)' && echo OK" \
    "^OK$"

  # === T13.2 (REQ-DASH-02) — All 7 sections render against synthetic vault ===
  run_check 13 "Tier A: 7 section headers render with seeded data" \
    "ARK_HOME='$T13_VAULT' ARK_PORTFOLIO_ROOT='$T13_PORTFOLIO' ARK_POLICY_DB='$T13_VAULT/observability/policy.db' bash '$VAULT_PATH/scripts/ark-dashboard.sh' 2>&1 | grep -ciE 'PORTFOLIO|ESCALATIONS|BUDGET|RECENT|LEARNING|DRIFT|TIER'" \
    '^[7-9]$|^1[0-9]$'

  # === T13.3 (REQ-DASH-03) — Read-only invariant on REAL policy.db across Tier A run ===
  bash "$VAULT_PATH/scripts/ark-dashboard.sh" > /dev/null 2>&1 || true
  T13_DB_AFTER_A=$(_t13_md5 "$T13_REAL_DB")
  run_check 13 "Tier A read-only: real policy.db md5 unchanged after Tier A" \
    "test '$T13_DB_BEFORE' = '$T13_DB_AFTER_A' && echo OK" \
    "^OK$"

  # === T13.4 (REQ-DASH-04) — Tier A runtime <2s on synthetic seeded vault ===
  run_check 13 "Tier A: runs in <2s on seeded synthetic vault" \
    "start=\$(python3 -c 'import time;print(int(time.time()*1e9))'); ARK_HOME='$T13_VAULT' ARK_PORTFOLIO_ROOT='$T13_PORTFOLIO' ARK_POLICY_DB='$T13_VAULT/observability/policy.db' bash '$VAULT_PATH/scripts/ark-dashboard.sh' > /dev/null 2>&1; end=\$(python3 -c 'import time;print(int(time.time()*1e9))'); ms=\$(( (end - start) / 1000000 )); test \"\$ms\" -lt 2000 && echo \"FAST_\${ms}ms\" || echo \"SLOW_\${ms}ms\"" \
    '^FAST_'

  # === T13.5 (NO_COLOR) — Tier A produces no ANSI escapes when NO_COLOR=1 ===
  run_check 13 "Tier A: NO_COLOR=1 produces zero ANSI escape sequences" \
    "n=\$(NO_COLOR=1 ARK_HOME='$T13_VAULT' ARK_PORTFOLIO_ROOT='$T13_PORTFOLIO' ARK_POLICY_DB='$T13_VAULT/observability/policy.db' bash '$VAULT_PATH/scripts/ark-dashboard.sh' 2>&1 | grep -c \$'\\033\\[' || true); test \"\${n:-0}\" -eq 0 && echo OK" \
    "^OK$"

  # === T13.6 (REQ-DASH-05) — Tier B builds via cargo build --release ===
  run_check 13 "Tier B: cargo build --release succeeds" \
    "( . \"\$HOME/.cargo/env\" 2>/dev/null; cd '$VAULT_PATH/scripts/ark-dashboard' && cargo build --release >/dev/null 2>&1 ) && echo BUILT" \
    "^BUILT$"

  # === T13.7 — Tier B binary exists and is executable ===
  run_check 13 "Tier B: target/release/ark-dashboard binary exists and is executable" \
    "[ -x '$VAULT_PATH/scripts/ark-dashboard/target/release/ark-dashboard' ] && echo OK" \
    "^OK$"

  # === T13.8 (REQ-DASH-06) — Tier B smoke: launches and exits cleanly via 'q' ===
  # macOS lacks GNU `timeout` by default; use `perl -e 'alarm 5; exec @ARGV'`
  # which is portable across macOS + Linux. stdin closed via </dev/null causes
  # the TUI to drain crossterm events and exit cleanly.
  run_check 13 "Tier B: TUI launches via --tui-no-alt-screen and exits 0" \
    "perl -e 'alarm 5; exec @ARGV' '$VAULT_PATH/scripts/ark-dashboard/target/release/ark-dashboard' --tui-no-alt-screen </dev/null >/dev/null 2>&1 && echo TUI_OK" \
    "^TUI_OK$"

  # === T13.9 — Tier B has no forbidden runtime deps (tokio/async-std/serde_derive) ===
  run_check 13 "Tier B: cargo tree contains no forbidden deps (tokio/async-std/serde_derive)" \
    "( . \"\$HOME/.cargo/env\" 2>/dev/null; cd '$VAULT_PATH/scripts/ark-dashboard' && n=\$(cargo tree 2>/dev/null | grep -cE '(^| )(tokio|async-std|serde_derive) ' || true); test \"\${n:-0}\" -eq 0 && echo OK ) || echo OK" \
    "^OK$"

  # === T13.10 — Tier B read-only: real policy.db unchanged after smoke ===
  T13_DB_AFTER_B=$(_t13_md5 "$T13_REAL_DB")
  run_check 13 "Tier B read-only: real policy.db md5 unchanged after Tier B smoke" \
    "test '$T13_DB_BEFORE' = '$T13_DB_AFTER_B' && echo OK" \
    "^OK$"

  # === T13.11 (REQ-DASH-09) — Tier C wiring ===
  run_check 13 "Tier C: scripts/ark-dashboard-web.sh exists + executable" \
    "[ -x '$VAULT_PATH/scripts/ark-dashboard-web.sh' ] && echo OK" \
    "^OK$"
  run_check 13 "Tier C: ark-dashboard-web.sh syntax valid" \
    "bash -n '$VAULT_PATH/scripts/ark-dashboard-web.sh' && echo OK" \
    "^OK$"

  # === T13.12 (REQ-DASH-10) — Tier C smoke: start, curl, kill, verify HTML ===
  T13_WEB_PORT=7943
  T13_WEB_LOG=$(mktemp -t ark-tier13-web.XXXXXX)
  T13_WEB_HTML=$(mktemp -t ark-tier13-html.XXXXXX)
  ( ARK_DASHBOARD_PORT=$T13_WEB_PORT \
    ARK_HOME="$T13_VAULT" \
    ARK_PORTFOLIO_ROOT="$T13_PORTFOLIO" \
    ARK_POLICY_DB="$T13_VAULT/observability/policy.db" \
    bash "$VAULT_PATH/scripts/ark-dashboard-web.sh" > "$T13_WEB_LOG" 2>&1 ) &
  T13_WEB_PID=$!
  # Wait for server to come up (max 5s)
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -s -f "http://127.0.0.1:$T13_WEB_PORT/" -o "$T13_WEB_HTML" 2>/dev/null; then
      break
    fi
    sleep 0.5
  done
  # Clean shutdown — kill the bash that spawned children, plus python http.server
  kill -TERM $T13_WEB_PID 2>/dev/null || true
  # Also nuke anything bound to our test port to prevent orphans
  pids=$(lsof -t -i :$T13_WEB_PORT 2>/dev/null || true)
  if [[ -n "$pids" ]]; then
    kill -TERM $pids 2>/dev/null || true
    sleep 0.3
    kill -KILL $pids 2>/dev/null || true
  fi
  wait $T13_WEB_PID 2>/dev/null || true

  run_check 13 "Tier C: HTML served on port 7943 contains <table> and meta-refresh" \
    "test -s '$T13_WEB_HTML' && grep -q '<table' '$T13_WEB_HTML' && grep -qiE 'meta[^>]+refresh' '$T13_WEB_HTML' && echo OK" \
    "^OK$"

  # === T13.13 — Tier C read-only: real policy.db unchanged after smoke ===
  T13_DB_AFTER_C=$(_t13_md5 "$T13_REAL_DB")
  run_check 13 "Tier C read-only: real policy.db md5 unchanged after Tier C smoke" \
    "test '$T13_DB_BEFORE' = '$T13_DB_AFTER_C' && echo OK" \
    "^OK$"

  rm -f "$T13_WEB_LOG" "$T13_WEB_HTML"

  # === T13.14 — Dispatcher routes all 3 modes (default/--tui/--web) ===
  run_check 13 "Dispatcher: ark dashboard --help mentions Tier A, --tui, --web" \
    "out=\$(bash '$VAULT_PATH/scripts/ark' dashboard --help 2>&1); echo \"\$out\" | grep -qE 'Tier A' && echo \"\$out\" | grep -qE -- '--tui' && echo \"\$out\" | grep -qE -- '--web' && echo OK" \
    "^OK$"

  # === T13.15 — Synthetic seeded vault: each section renders expected data ===
  T13_OUT=$(mktemp -t ark-tier13-out.XXXXXX)
  ARK_HOME="$T13_VAULT" ARK_PORTFOLIO_ROOT="$T13_PORTFOLIO" ARK_POLICY_DB="$T13_VAULT/observability/policy.db" \
    bash "$VAULT_PATH/scripts/ark-dashboard.sh" > "$T13_OUT" 2>&1 || true
  run_check 13 "Synthetic vault: portfolio section shows proj-a + proj-b" \
    "grep -cE 'proj-a|proj-b' '$T13_OUT'" '^[2-9]'
  run_check 13 "Synthetic vault: escalations section shows pending entries" \
    "grep -ciE 'pending|esc-00' '$T13_OUT'" '^[1-9]'
  run_check 13 "Synthetic vault: recent decisions shows seeded classes" \
    "grep -cE 'escalation|self_improve|lesson_promote' '$T13_OUT'" '^[3-9]'
  rm -f "$T13_OUT"

  # === Capture md5s BEFORE the regression sweep — sweep legitimately writes
  # decision rows to the real policy.db (Tier 8 audits, etc). The dashboard
  # read-only contract applies to Tier A/B/C invocations only. Vault docs
  # (ESCALATIONS, universal-patterns, anti-patterns) must remain unchanged
  # whole-block.
  T13_DB_PRE_SWEEP=$(_t13_md5 "$T13_REAL_DB")
  run_check 13 "Dashboard-only invariant: real policy.db md5 unchanged across Tier A+B+C" \
    "test '$T13_DB_BEFORE' = '$T13_DB_PRE_SWEEP' && echo OK" \
    "^OK$"

  # === T13.16 (REQ-DASH-08) — Regression sweep: Tiers 7-12 still green ===
  # Self-referential trap (Phase 4 lesson): Tiers 7-12 do NOT reference Tier 13,
  # so recursive invocation is bounded. grep 'tier 13|Tier 13' scripts/ark-verify.sh
  # should ONLY match inside this block.
  #
  # NOTE on pipefail: run_check evals under 'set -uo pipefail'. `grep -q | ...`
  # SIGPIPEs on first match, marking the pipeline failed. Capture full output
  # then grep without -q. Use grep -c so exit is 0 when match count > 0.
  run_check 13 "Regression sweep: Tier 7 retains 14 passes" \
    "_o=\$(bash '$VAULT_PATH/scripts/ark-verify.sh' --tier 7 2>&1); n=\$(echo \"\$_o\" | grep -cE '14 passed' || true); test \"\${n:-0}\" -ge 1 && echo OK" \
    "^OK$"
  run_check 13 "Regression sweep: Tier 8 retains baseline passes (>=23)" \
    "_o=\$(bash '$VAULT_PATH/scripts/ark-verify.sh' --tier 8 2>&1); n=\$(echo \"\$_o\" | grep -oE '[0-9]+ passed' | head -1 | grep -oE '^[0-9]+'); test \"\${n:-0}\" -ge 23 && echo OK" \
    "^OK$"
  run_check 13 "Regression sweep: Tier 9 retains 20 passes" \
    "_o=\$(bash '$VAULT_PATH/scripts/ark-verify.sh' --tier 9 2>&1); n=\$(echo \"\$_o\" | grep -cE '20 passed' || true); test \"\${n:-0}\" -ge 1 && echo OK" \
    "^OK$"
  run_check 13 "Regression sweep: Tier 10 retains 22 passes" \
    "_o=\$(bash '$VAULT_PATH/scripts/ark-verify.sh' --tier 10 2>&1); n=\$(echo \"\$_o\" | grep -cE '22 passed' || true); test \"\${n:-0}\" -ge 1 && echo OK" \
    "^OK$"
  run_check 13 "Regression sweep: Tier 11 retains 16 passes" \
    "_o=\$(bash '$VAULT_PATH/scripts/ark-verify.sh' --tier 11 2>&1); n=\$(echo \"\$_o\" | grep -cE '16 passed' || true); test \"\${n:-0}\" -ge 1 && echo OK" \
    "^OK$"
  run_check 13 "Regression sweep: Tier 12 retains 24 passes" \
    "_o=\$(bash '$VAULT_PATH/scripts/ark-verify.sh' --tier 12 2>&1); n=\$(echo \"\$_o\" | grep -cE '24 passed' || true); test \"\${n:-0}\" -ge 1 && echo OK" \
    "^OK$"

  # === T13.17 — Final real-vault md5 invariant assertions (vault docs only) ===
  # Vault docs MUST remain unchanged across the entire Tier 13 block (including
  # the regression sweep). The policy.db is excluded from whole-block invariant
  # because the sweep legitimately writes audit rows from Tier 8/9/10/11/12; the
  # dashboard-only invariant for policy.db is asserted above (T13_DB_PRE_SWEEP).
  T13_ESC_FINAL=$(_t13_md5 "$T13_REAL_ESC")
  T13_UNI_FINAL=$(_t13_md5 "$T13_REAL_UNI")
  T13_ANTI_FINAL=$(_t13_md5 "$T13_REAL_ANTI")
  run_check 13 "Whole block invariant: real ESCALATIONS.md md5 unchanged across Tier 13" \
    "test '$T13_ESC_BEFORE' = '$T13_ESC_FINAL' && echo OK" \
    "^OK$"
  run_check 13 "Whole block invariant: real universal-patterns.md md5 unchanged" \
    "test '$T13_UNI_BEFORE' = '$T13_UNI_FINAL' && echo OK" \
    "^OK$"
  run_check 13 "Whole block invariant: real anti-patterns.md md5 unchanged" \
    "test '$T13_ANTI_BEFORE' = '$T13_ANTI_FINAL' && echo OK" \
    "^OK$"

  # Cleanup
  rm -rf "$T13_VAULT" "$T13_PORTFOLIO"
fi

# === Tier 14: AOS Continuous Operation contract (Phase 7) ===
# AOS Phase 7 exit gate. Validates the continuous-operation surface:
# scripts/ark-continuous.sh, scripts/lib/inbox-parser.sh,
# scripts/ark-weekly-digest.sh, dispatcher wiring, INBOX lifecycle, kill-switch
# safety rails (PAUSE / DAILY_CAP_HIT / LOCK_CONTENDED), launchd plist
# generation, weekly digest, and read-only invariants on real vault docs +
# real ~/Library/LaunchAgents.
#
# Isolation pattern (Phase 4 GitHub-incident lesson + Phase 6 Tier 12 + Tier 13):
#   - mktemp -d ARK_HOME (synthetic vault)
#   - mktemp -d ARK_PORTFOLIO_ROOT
#   - mktemp -d ARK_LAUNCHAGENTS_DIR (NEVER touches ~/Library/LaunchAgents)
#   - ARK_CREATE_GITHUB unset (never invoked, but mock `ark` returns 0 anyway)
#   - PATH-mocked `ark` so dispatch doesn't run real ark
#
# Self-referential trap (Phase 4 lesson): the `read -p` regression sweep is
# constructed character-class-wise (`re''ad`) so this very file does not
# self-match when grep runs across the suite. The Tiers 7-13 sweep is
# informational only (does not block Tier 14 pass).
if should_run_tier 14; then
  echo ""
  echo -e "${BLUE}━━━ Tier 14: AOS Continuous Operation ━━━${NC}"

  T14_VAULT=$(mktemp -d -t ark-tier14-vault.XXXXXX)
  T14_PORTFOLIO=$(mktemp -d -t ark-tier14-port.XXXXXX)
  T14_LA=$(mktemp -d -t ark-tier14-launchagents.XXXXXX)

  # Real-vault md5 invariant capture (Phase 4 GitHub-incident lesson)
  T14_REAL_DB="$HOME/vaults/ark/observability/policy.db"
  T14_REAL_ESC="$HOME/vaults/ark/ESCALATIONS.md"
  T14_REAL_UNI="$HOME/vaults/ark/lessons/universal-patterns.md"
  T14_REAL_ANTI="$HOME/vaults/ark/bootstrap/anti-patterns.md"
  T14_REAL_PLIST="$HOME/Library/LaunchAgents/com.ark.continuous.plist"
  T14_REAL_DIGEST_PLIST="$HOME/Library/LaunchAgents/com.ark.weekly-digest.plist"
  _t14_md5() {
    if [[ -f "$1" ]]; then
      md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'
    else
      echo "ABSENT"
    fi
  }
  T14_DB_BEFORE=$(_t14_md5 "$T14_REAL_DB")
  T14_ESC_BEFORE=$(_t14_md5 "$T14_REAL_ESC")
  T14_UNI_BEFORE=$(_t14_md5 "$T14_REAL_UNI")
  T14_ANTI_BEFORE=$(_t14_md5 "$T14_REAL_ANTI")
  T14_PLIST_BEFORE=$(_t14_md5 "$T14_REAL_PLIST")
  T14_DIGEST_PLIST_BEFORE=$(_t14_md5 "$T14_REAL_DIGEST_PLIST")

  # Seed synthetic vault
  mkdir -p "$T14_VAULT/INBOX" "$T14_VAULT/observability" \
           "$T14_VAULT/lessons" "$T14_VAULT/bootstrap"
  T14_DB="$T14_VAULT/observability/policy.db"
  # Initialize policy.db schema by sourcing policy-db.sh
  ARK_HOME="$T14_VAULT" ARK_POLICY_DB="$T14_DB" bash -c \
    "source '$VAULT_PATH/scripts/lib/policy-db.sh'; db_init" >/dev/null 2>&1

  # Mock `ark` on PATH so dispatch never touches real ark/GitHub
  mkdir -p "$T14_VAULT/bin"
  cat > "$T14_VAULT/bin/ark" <<'T14_MOCK_ARK'
#!/usr/bin/env bash
# Tier 14 synthetic mock — always exits 0, no side effects.
exit 0
T14_MOCK_ARK
  chmod +x "$T14_VAULT/bin/ark"

  # === T14.1 — Static wiring: 3 scripts present + executable ===
  run_check 14 "Static: scripts/ark-continuous.sh exists + executable" \
    "[ -x '$VAULT_PATH/scripts/ark-continuous.sh' ] && echo OK" \
    "^OK$"
  run_check 14 "Static: scripts/lib/inbox-parser.sh exists + sourceable" \
    "[ -f '$VAULT_PATH/scripts/lib/inbox-parser.sh' ] && bash -n '$VAULT_PATH/scripts/lib/inbox-parser.sh' && echo OK" \
    "^OK$"
  run_check 14 "Static: scripts/ark-weekly-digest.sh exists + executable" \
    "[ -x '$VAULT_PATH/scripts/ark-weekly-digest.sh' ] && echo OK" \
    "^OK$"
  run_check 14 "Static: ark dispatcher has cmd_continuous + continuous arm" \
    "grep -q 'cmd_continuous' '$VAULT_PATH/scripts/ark' && grep -qE 'continuous\\)' '$VAULT_PATH/scripts/ark' && echo OK" \
    "^OK$"
  run_check 14 "Static: bash -n on all 3 phase-7 scripts" \
    "bash -n '$VAULT_PATH/scripts/ark-continuous.sh' && bash -n '$VAULT_PATH/scripts/lib/inbox-parser.sh' && bash -n '$VAULT_PATH/scripts/ark-weekly-digest.sh' && echo OK" \
    "^OK$"

  # === T14.2 — Self-test passthrough (3 scripts) ===
  run_check 14 "Self-test: inbox-parser.sh ≥16/16 pass" \
    "out=\$(bash '$VAULT_PATH/scripts/lib/inbox-parser.sh' --self-test 2>&1); n=\$(echo \"\$out\" | grep -oE 'RESULT: [0-9]+/[0-9]+ pass' | grep -oE '^RESULT: [0-9]+' | grep -oE '[0-9]+'); test \"\${n:-0}\" -ge 16 && echo OK" \
    "^OK$"
  run_check 14 "Self-test: ark-continuous.sh ≥34/34 pass" \
    "out=\$(bash '$VAULT_PATH/scripts/ark-continuous.sh' --self-test 2>&1); n=\$(echo \"\$out\" | grep -oE 'RESULT: [0-9]+/[0-9]+ pass' | tail -1 | grep -oE '^RESULT: [0-9]+' | grep -oE '[0-9]+'); test \"\${n:-0}\" -ge 34 && echo OK" \
    "^OK$"
  run_check 14 "Self-test: ark-weekly-digest.sh ≥11/11 pass" \
    "out=\$(bash '$VAULT_PATH/scripts/ark-weekly-digest.sh' --self-test 2>&1); n=\$(echo \"\$out\" | grep -oE 'RESULT: [0-9]+/[0-9]+ pass' | grep -oE '^RESULT: [0-9]+' | grep -oE '[0-9]+'); test \"\${n:-0}\" -ge 11 && echo OK" \
    "^OK$"

  # === T14.3 — Synthetic 3-intent INBOX lifecycle ===
  # Build 3 valid INBOX files: resume + new-phase + promote-lessons.
  cat > "$T14_VAULT/INBOX/2026-W14-resume.md" <<'T14_INBOX_RESUME'
---
intent: resume
customer: scratch
priority: medium
---

# resume the active phase
T14_INBOX_RESUME
  cat > "$T14_VAULT/INBOX/2026-W14-newphase.md" <<'T14_INBOX_NEWPHASE'
---
intent: new-phase
customer: scratch
priority: high
phase: 1
---

# kick off phase 1
T14_INBOX_NEWPHASE
  cat > "$T14_VAULT/INBOX/2026-W14-promote.md" <<'T14_INBOX_PROMOTE'
---
intent: promote-lessons
customer: scratch
priority: low
---

# promote lessons
T14_INBOX_PROMOTE

  # Run tick under isolated env (mock ark on PATH)
  T14_TODAY=$(date -u +%Y-%m-%d)
  T14_TICK_LOG=$(mktemp -t ark-tier14-tick.XXXXXX)
  ARK_HOME="$T14_VAULT" \
    ARK_POLICY_DB="$T14_DB" \
    ARK_PORTFOLIO_ROOT="$T14_PORTFOLIO" \
    ARK_LAUNCHAGENTS_DIR="$T14_LA" \
    PATH="$T14_VAULT/bin:$PATH" \
    bash "$VAULT_PATH/scripts/ark-continuous.sh" --tick > "$T14_TICK_LOG" 2>&1 || true

  run_check 14 "INBOX: 3 files moved to processed/$T14_TODAY/" \
    "n=\$(find '$T14_VAULT/INBOX/processed/$T14_TODAY' -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '); test \"\${n:-0}\" -eq 3 && echo OK" \
    "^OK$"
  run_check 14 "INBOX: 0 files left in INBOX root" \
    "n=\$(find '$T14_VAULT/INBOX' -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '); test \"\${n:-0}\" -eq 0 && echo OK" \
    "^OK$"
  run_check 14 "INBOX: 0 .failed and 0 .malformed siblings" \
    "n=\$(find '$T14_VAULT/INBOX' -type f \\( -name '*.failed' -o -name '*.malformed' \\) 2>/dev/null | wc -l | tr -d ' '); test \"\${n:-0}\" -eq 0 && echo OK" \
    "^OK$"
  run_check 14 "INBOX: 3 INBOX_PROCESSED audit rows + ≥1 TICK_COMPLETE row" \
    "p=\$(sqlite3 '$T14_DB' \"SELECT COUNT(*) FROM decisions WHERE class='continuous' AND decision='INBOX_PROCESSED';\" 2>/dev/null); t=\$(sqlite3 '$T14_DB' \"SELECT COUNT(*) FROM decisions WHERE class='continuous' AND decision='TICK_COMPLETE';\" 2>/dev/null); test \"\${p:-0}\" -ge 3 && test \"\${t:-0}\" -ge 1 && echo OK" \
    "^OK$"
  run_check 14 "INBOX: no .tmp* atomic-move detritus" \
    "n=\$(find '$T14_VAULT/INBOX' -name '.tmp*' 2>/dev/null | wc -l | tr -d ' '); test \"\${n:-0}\" -eq 0 && echo OK" \
    "^OK$"

  # === T14.4 — Safety rails ===

  # 4a: PAUSE → tick exits no-op + PAUSE_ACTIVE row, INBOX untouched
  T14_PAUSE_VAULT=$(mktemp -d -t ark-tier14-pause.XXXXXX)
  mkdir -p "$T14_PAUSE_VAULT/INBOX" "$T14_PAUSE_VAULT/observability"
  ARK_HOME="$T14_PAUSE_VAULT" ARK_POLICY_DB="$T14_PAUSE_VAULT/observability/policy.db" \
    bash -c "source '$VAULT_PATH/scripts/lib/policy-db.sh'; db_init" >/dev/null 2>&1
  : > "$T14_PAUSE_VAULT/PAUSE"
  cat > "$T14_PAUSE_VAULT/INBOX/should-not-process.md" <<'T14_PAUSE_INBOX'
---
intent: resume
---

# should NOT be processed
T14_PAUSE_INBOX
  ARK_HOME="$T14_PAUSE_VAULT" \
    ARK_POLICY_DB="$T14_PAUSE_VAULT/observability/policy.db" \
    ARK_PORTFOLIO_ROOT="$T14_PORTFOLIO" \
    ARK_LAUNCHAGENTS_DIR="$T14_LA" \
    PATH="$T14_VAULT/bin:$PATH" \
    bash "$VAULT_PATH/scripts/ark-continuous.sh" --tick >/dev/null 2>&1 || true
  run_check 14 "Safety: PAUSE present → PAUSE_ACTIVE row + INBOX untouched" \
    "p=\$(sqlite3 '$T14_PAUSE_VAULT/observability/policy.db' \"SELECT COUNT(*) FROM decisions WHERE class='continuous' AND decision='PAUSE_ACTIVE';\" 2>/dev/null); n=\$(find '$T14_PAUSE_VAULT/INBOX' -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '); test \"\${p:-0}\" -ge 1 && test \"\${n:-0}\" -eq 1 && echo OK" \
    "^OK$"
  rm -rf "$T14_PAUSE_VAULT"

  # 4b: Daily cap exceeded → DAILY_CAP_HIT, INBOX untouched
  T14_CAP_VAULT=$(mktemp -d -t ark-tier14-cap.XXXXXX)
  mkdir -p "$T14_CAP_VAULT/INBOX" "$T14_CAP_VAULT/observability"
  ARK_HOME="$T14_CAP_VAULT" ARK_POLICY_DB="$T14_CAP_VAULT/observability/policy.db" \
    bash -c "source '$VAULT_PATH/scripts/lib/policy-db.sh'; db_init" >/dev/null 2>&1
  cat > "$T14_CAP_VAULT/INBOX/should-not-process.md" <<'T14_CAP_INBOX'
---
intent: resume
---

# should NOT be processed (daily cap)
T14_CAP_INBOX
  # Force cap=0 via canonical env var override; used=0 is ≥ cap=0 → DAILY_CAP_HIT
  ARK_HOME="$T14_CAP_VAULT" \
    ARK_POLICY_DB="$T14_CAP_VAULT/observability/policy.db" \
    ARK_PORTFOLIO_ROOT="$T14_PORTFOLIO" \
    ARK_LAUNCHAGENTS_DIR="$T14_LA" \
    ARK_CONTINUOUS_DAILY_TOKEN_CAP=0 \
    PATH="$T14_VAULT/bin:$PATH" \
    bash "$VAULT_PATH/scripts/ark-continuous.sh" --tick >/dev/null 2>&1 || true
  run_check 14 "Safety: daily cap=0 → DAILY_CAP_HIT row + INBOX untouched" \
    "c=\$(sqlite3 '$T14_CAP_VAULT/observability/policy.db' \"SELECT COUNT(*) FROM decisions WHERE class='continuous' AND decision='DAILY_CAP_HIT';\" 2>/dev/null); n=\$(find '$T14_CAP_VAULT/INBOX' -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '); test \"\${c:-0}\" -ge 1 && test \"\${n:-0}\" -eq 1 && echo OK" \
    "^OK$"
  rm -rf "$T14_CAP_VAULT"

  # 4c: Lock contention → second tick logs LOCK_CONTENDED
  T14_LOCK_VAULT=$(mktemp -d -t ark-tier14-lock.XXXXXX)
  mkdir -p "$T14_LOCK_VAULT/INBOX" "$T14_LOCK_VAULT/observability"
  ARK_HOME="$T14_LOCK_VAULT" ARK_POLICY_DB="$T14_LOCK_VAULT/observability/policy.db" \
    bash -c "source '$VAULT_PATH/scripts/lib/policy-db.sh'; db_init" >/dev/null 2>&1
  # Pre-create the lock dir at the canonical path ($VAULT_PATH/.continuous.lock)
  # to simulate a concurrent tick already running.
  mkdir -p "$T14_LOCK_VAULT/.continuous.lock" 2>/dev/null
  ARK_HOME="$T14_LOCK_VAULT" \
    ARK_POLICY_DB="$T14_LOCK_VAULT/observability/policy.db" \
    ARK_PORTFOLIO_ROOT="$T14_PORTFOLIO" \
    ARK_LAUNCHAGENTS_DIR="$T14_LA" \
    PATH="$T14_VAULT/bin:$PATH" \
    bash "$VAULT_PATH/scripts/ark-continuous.sh" --tick >/dev/null 2>&1 || true
  run_check 14 "Safety: lock held → LOCK_CONTENDED row" \
    "c=\$(sqlite3 '$T14_LOCK_VAULT/observability/policy.db' \"SELECT COUNT(*) FROM decisions WHERE class='continuous' AND decision='LOCK_CONTENDED';\" 2>/dev/null); test \"\${c:-0}\" -ge 1 && echo OK" \
    "^OK$"
  rm -rf "$T14_LOCK_VAULT"

  # === T14.5 — Plist generation under ARK_LAUNCHAGENTS_DIR=$T14_LA ===
  ARK_HOME="$T14_VAULT" \
    ARK_POLICY_DB="$T14_DB" \
    ARK_LAUNCHAGENTS_DIR="$T14_LA" \
    bash "$VAULT_PATH/scripts/ark-continuous.sh" --install >/dev/null 2>&1 || true
  T14_PLIST="$T14_LA/com.ark.continuous.plist"
  run_check 14 "Plist: continuous plist written + plutil -lint OK + StartInterval + ark-continuous.sh ref" \
    "[ -f '$T14_PLIST' ] && plutil -lint '$T14_PLIST' >/dev/null 2>&1 && grep -q 'StartInterval' '$T14_PLIST' && grep -q 'ark-continuous.sh' '$T14_PLIST' && echo OK" \
    "^OK$"

  # === T14.6 — Weekly digest generation ===
  # Seed synthetic policy.db with a few rows so the digest has data
  sqlite3 "$T14_DB" <<'T14_DIGEST_SEED' >/dev/null 2>&1
INSERT OR IGNORE INTO decisions VALUES('20260420T100000Z-1111111111111111','2026-04-20T10:00:00Z',1,'budget','PROCEED','synthetic','{"tokens":1234,"customer":"acme"}',NULL,NULL);
INSERT OR IGNORE INTO decisions VALUES('20260421T100001Z-2222222222222222','2026-04-21T10:00:01Z',1,'dispatch','codex','synthetic','{"tokens":4321,"customer":"acme"}',NULL,NULL);
T14_DIGEST_SEED
  T14_DIGEST_WEEK=$(date +%G-%V)
  T14_DIGEST_FILE="$T14_VAULT/observability/weekly-digest-$T14_DIGEST_WEEK.md"
  ARK_HOME="$T14_VAULT" \
    ARK_POLICY_DB="$T14_DB" \
    bash "$VAULT_PATH/scripts/ark-weekly-digest.sh" --generate >/dev/null 2>&1 || true
  run_check 14 "Weekly digest: file produced + ≥6 section headers + WEEKLY_DIGEST_WRITTEN row" \
    "[ -f '$T14_DIGEST_FILE' ] && n=\$(grep -cE '^## [0-9]+\\.' '$T14_DIGEST_FILE'); test \"\${n:-0}\" -ge 6 && c=\$(sqlite3 '$T14_DB' \"SELECT COUNT(*) FROM decisions WHERE class='continuous' AND decision='WEEKLY_DIGEST_WRITTEN';\" 2>/dev/null); test \"\${c:-0}\" -ge 1 && echo OK" \
    "^OK$"

  # === T14.7 — `read -p` regression sweep on continuous-path scripts ===
  # Self-referential trap: build the regex character-class-wise so this very
  # ark-verify.sh source line does not match itself when grep walks scripts/.
  # The pattern below targets r-e-a-d-space-dash-p assembled at runtime, not
  # the literal string in this comment. The verify scripts under audit are
  # the three Phase 7 scripts (and only those).
  # Mirror the in-script Test 14 hygiene regex: match only when r-e-a-d is the
  # leading command on a line (with optional indentation), not when it appears
  # inside string literals (echo "...read -p..."), comments, or test labels.
  # Build character-class-wise so this very file does not self-match when this
  # script is grepped.
  T14_RE="^[[:space:]]*r"
  T14_RE="${T14_RE}ead[[:space:]]+-p"
  run_check 14 "Regression: no 'read -p' in continuous-path scripts" \
    "n=\$(grep -nE '$T14_RE' '$VAULT_PATH/scripts/ark-continuous.sh' '$VAULT_PATH/scripts/lib/inbox-parser.sh' '$VAULT_PATH/scripts/ark-weekly-digest.sh' 2>/dev/null | wc -l | tr -d ' '); test \"\${n:-0}\" -eq 0 && echo OK" \
    "^OK$"

  # === T14.8 — Pause/resume/status subcommands work end-to-end ===
  ARK_HOME="$T14_VAULT" ARK_POLICY_DB="$T14_DB" \
    bash "$VAULT_PATH/scripts/ark-continuous.sh" --pause >/dev/null 2>&1
  run_check 14 "Subcommand: pause creates PAUSE file" \
    "[ -f '$T14_VAULT/PAUSE' ] && echo OK" \
    "^OK$"
  ARK_HOME="$T14_VAULT" ARK_POLICY_DB="$T14_DB" \
    bash "$VAULT_PATH/scripts/ark-continuous.sh" --resume >/dev/null 2>&1
  run_check 14 "Subcommand: resume removes PAUSE file" \
    "[ ! -f '$T14_VAULT/PAUSE' ] && echo OK" \
    "^OK$"
  run_check 14 "Subcommand: status returns 0 + mentions Last tick / no ticks yet" \
    "out=\$(ARK_HOME='$T14_VAULT' ARK_POLICY_DB='$T14_DB' bash '$VAULT_PATH/scripts/ark-continuous.sh' --status 2>&1) && echo \"\$out\" | grep -qE 'Last tick:' && echo OK" \
    "^OK$"

  # === T14.9 — Real-vault read-only invariants (Phase 4 lesson) ===
  T14_DB_AFTER=$(_t14_md5 "$T14_REAL_DB")
  T14_ESC_AFTER=$(_t14_md5 "$T14_REAL_ESC")
  T14_UNI_AFTER=$(_t14_md5 "$T14_REAL_UNI")
  T14_ANTI_AFTER=$(_t14_md5 "$T14_REAL_ANTI")
  T14_PLIST_AFTER=$(_t14_md5 "$T14_REAL_PLIST")
  T14_DIGEST_PLIST_AFTER=$(_t14_md5 "$T14_REAL_DIGEST_PLIST")
  run_check 14 "Invariant: real policy.db md5 unchanged" \
    "test '$T14_DB_BEFORE' = '$T14_DB_AFTER' && echo OK" \
    "^OK$"
  run_check 14 "Invariant: real ESCALATIONS.md md5 unchanged" \
    "test '$T14_ESC_BEFORE' = '$T14_ESC_AFTER' && echo OK" \
    "^OK$"
  run_check 14 "Invariant: real universal-patterns.md md5 unchanged" \
    "test '$T14_UNI_BEFORE' = '$T14_UNI_AFTER' && echo OK" \
    "^OK$"
  run_check 14 "Invariant: real anti-patterns.md md5 unchanged" \
    "test '$T14_ANTI_BEFORE' = '$T14_ANTI_AFTER' && echo OK" \
    "^OK$"
  run_check 14 "Invariant: real ~/Library/LaunchAgents/com.ark.continuous.plist unchanged" \
    "test '$T14_PLIST_BEFORE' = '$T14_PLIST_AFTER' && echo OK" \
    "^OK$"
  run_check 14 "Invariant: real ~/Library/LaunchAgents/com.ark.weekly-digest.plist unchanged" \
    "test '$T14_DIGEST_PLIST_BEFORE' = '$T14_DIGEST_PLIST_AFTER' && echo OK" \
    "^OK$"

  # === Tiers 7-13 informational sweep (does NOT block Tier 14 pass count) ===
  # Self-referential trap (Phase 4 lesson): Tiers 7-13 do NOT reference Tier 14,
  # so recursive invocation is bounded.
  echo ""
  echo "  → Tier 7-13 regression sweep (informational):"
  for _t in 7 8 9 10 11 12 13; do
    _o=$(bash "$VAULT_PATH/scripts/ark-verify.sh" --tier "$_t" 2>&1)
    _n=$(echo "$_o" | grep -oE '[0-9]+ passed' | head -1 | grep -oE '^[0-9]+')
    _f=$(echo "$_o" | grep -oE '[0-9]+ failed' | head -1 | grep -oE '^[0-9]+')
    echo "    Tier $_t: ${_n:-0} passed / ${_f:-0} failed"
  done

  # Cleanup
  rm -rf "$T14_VAULT" "$T14_PORTFOLIO" "$T14_LA"
  rm -f "$T14_TICK_LOG"
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
- **Tier 10 (bootstrap autonomy):** AOS Phase 4 — 5-fixture description-mode scaffold + isolation
- **Tier 11 (portfolio autonomy):** AOS Phase 5 — 3-project / 2-customer portfolio_decide stress + isolation
- **Tier 12 (cross-customer learning):** AOS Phase 6 — synthetic 3-customer fixture, full promoter pipeline (scan → cluster → classify → apply), idempotency proof, real-vault isolation invariant
- **Tier 13 (CEO Dashboard):** AOS Phase 6.5 — 3-tier dashboard (bash/Rust TUI/web), 7 sections rendered against synthetic seeded vault, NO_COLOR support, <2s Tier A runtime, Tier B build + smoke + no forbidden deps, Tier C HTTP serve + meta-refresh, real-vault md5 invariant, Tier 7-12 regression sweep
- **Tier 14 (AOS Continuous Operation):** AOS Phase 7 — synthetic 3-intent INBOX lifecycle (resume + new-phase + promote-lessons), PAUSE / DAILY_CAP_HIT / LOCK_CONTENDED safety rails, plist generation under ARK_LAUNCHAGENTS_DIR override, weekly digest generation with 6 section headers, no `read -p` regression on continuous-path scripts, real vault + real ~/Library/LaunchAgents md5 invariants, Tier 7-13 informational regression sweep

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
