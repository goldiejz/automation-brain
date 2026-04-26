#!/usr/bin/env bash
# ark deliver — autonomous project delivery from design to deployed
#
# Usage:
#   ark deliver                          # Run full delivery in current project
#   ark deliver --from-spec /path/spec   # Start from brainstorm output
#   ark deliver --phase N                # Run only phase N
#   ark deliver --resume                 # Continue from last successful phase
#
# What it does:
# 1. Reads .planning/PROJECT.md + ROADMAP.md (must exist)
# 2. For each phase in ROADMAP:
#    a. /gsd-plan-phase via Codex/Claude
#    b. /gsd-execute-phase (writes code, tests, runs verification)
#    c. brain commit (atomic per task)
#    d. brain deploy (if deployable)
#    e. brain verify (smoke tests)
#    f. Updates STATE.md
#    g. If failure → self-heal → retry once → escalate to human if still failing
# 3. Logs everything to vault for cross-project learning
# 4. Pushes continuously to GitHub
#
# Cost-aware: dispatches to Codex (free) for code, Haiku for review,
# Sonnet for architecture decisions, Opus for novel problems only.

set -uo pipefail

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"

# === Source policy + escalations libs (graceful degradation if missing) ===
# shellcheck disable=SC1091
if [[ -f "$VAULT_PATH/scripts/ark-policy.sh" ]]; then source "$VAULT_PATH/scripts/ark-policy.sh"; fi
# shellcheck disable=SC1091
if [[ -f "$VAULT_PATH/scripts/ark-escalations.sh" ]]; then source "$VAULT_PATH/scripts/ark-escalations.sh"; fi

PROJECT_DIR="$(pwd)"
MODE="full"
FROM_SPEC=""
PHASE_NUM=""
RESUME=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-spec) FROM_SPEC="$2"; MODE="from-spec"; shift 2 ;;
    --phase) PHASE_NUM="$2"; MODE="single-phase"; shift 2 ;;
    --resume) RESUME=true; shift ;;
    --help) MODE="help"; shift ;;
    *) shift ;;
  esac
done

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}🚀 BRAIN DELIVER — Autonomous Project Pipeline${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo "  Project: $(basename "$PROJECT_DIR")"
  echo "  Mode: $MODE"
  echo "  Vault: $VAULT_PATH"
  echo ""
}

log() {
  local level="$1"
  local msg="$2"
  local color
  case "$level" in
    INFO) color="$BLUE" ;;
    OK) color="$GREEN" ;;
    WARN) color="$YELLOW" ;;
    ERROR) color="$RED" ;;
    *) color="$NC" ;;
  esac
  echo -e "${color}[${level}]${NC} $msg"

  # Also append to delivery log
  local log_dir="$PROJECT_DIR/.planning/delivery-logs"
  mkdir -p "$log_dir" 2>/dev/null
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$level] $msg" >> "$log_dir/$(date +%Y%m%d).log"
}

# === Pre-flight checks ===
preflight() {
  log INFO "Running pre-flight checks..."

  # Must have a brain integration
  if [[ ! -d "$PROJECT_DIR/.parent-automation" ]]; then
    log ERROR "No .parent-automation/ — run: ark init"
    exit 1
  fi

  # Must have a roadmap
  if [[ ! -f "$PROJECT_DIR/.planning/ROADMAP.md" ]]; then
    log ERROR "No .planning/ROADMAP.md — run: ark init or write a roadmap first"
    exit 1
  fi

  # Must be a git repo
  if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    log WARN "Not a git repo — initializing"
    git init "$PROJECT_DIR" --quiet
  fi

  # Sync brain to latest
  log INFO "Syncing brain..."
  bash "$VAULT_PATH/scripts/ark-sync.sh" "$PROJECT_DIR" >/dev/null 2>&1

  log OK "Pre-flight passed"
}

# === Parse phases from ROADMAP.md ===
get_phases() {
  # Extract phase headers like "## Phase 1 — ...", "## Phase 0 — ..."
  grep -E "^## Phase [0-9]+" "$PROJECT_DIR/.planning/ROADMAP.md" 2>/dev/null | head -20
}

# === Get current phase from STATE.md ===
get_current_phase() {
  if [[ -f "$PROJECT_DIR/.planning/STATE.md" ]]; then
    grep -oE "Phase [0-9]+" "$PROJECT_DIR/.planning/STATE.md" | head -1 | grep -oE "[0-9]+"
  else
    echo "0"
  fi
}

# === Check if a phase is already shipped per STATE.md ===
is_phase_complete() {
  local phase_num="$1"
  local state_file="$PROJECT_DIR/.planning/STATE.md"

  [[ ! -f "$state_file" ]] && return 1

  # Look for explicit completion markers:
  # "Phase N: complete" or "Phase N — complete" or "[x] Phase N" or "Status: complete" near "Phase N"
  if grep -qiE "(^|[^a-z])phase[ -]+$phase_num[: -]+(complete|delivered|shipped|done)" "$state_file"; then
    return 0
  fi

  # Check ROADMAP for [x] checkboxes on Phase N tasks (all done)
  local roadmap="$PROJECT_DIR/.planning/ROADMAP.md"
  if [[ -f "$roadmap" ]]; then
    # Extract Phase N block, count [ ] vs [x]
    local phase_block
    phase_block=$(awk "/^## Phase $phase_num /,/^## Phase [0-9]+/" "$roadmap" | head -n -1)
    local pending=$(echo "$phase_block" | grep -cE "^- \[ \]" || echo 0)
    local done_count=$(echo "$phase_block" | grep -cE "^- \[x\]" || echo 0)
    # All tasks checked AND at least 1 task = phase complete
    if [[ $pending -eq 0 ]] && [[ $done_count -gt 0 ]]; then
      return 0
    fi
  fi

  return 1
}

# === Detect AI quota errors in team artifacts (don't mistake for verdicts) ===
artifact_has_real_content() {
  local artifact="$1"
  [[ ! -f "$artifact" ]] && return 1
  # Reject if file is just a quota/error blob
  if grep -qiE "QUOTA_EXHAUSTED|TerminalQuotaError|hit your usage limit|Plan.*limit|capacity.*reset" "$artifact" 2>/dev/null; then
    return 1
  fi
  # Must have actual content (not just whitespace)
  [[ $(wc -l < "$artifact" 2>/dev/null | tr -d ' ') -gt 3 ]]
}

# === GSD-shape resolution: delegated to shared lib ===
source "$VAULT_PATH/scripts/lib/gsd-shape.sh"

is_gsd_project()      { gsd_is_gsd_project "$@"; }
normalize_phase_num() { gsd_normalize_phase_num "$@"; }
resolve_phase_dir()   { gsd_resolve_phase_dir "$@"; }
find_plan_files()     { gsd_find_plan_files "$@"; }

# === Helper: route zero-task phases via policy (Phase 2 Plan 02-05) ===
# Args: phase_num phase_dir plan_count
# Always returns 0 — the pipeline never halts on zero-task phases.
_deliver_handle_zero_tasks() {
  local _phase="$1" _phase_dir="$2" _plan_count_raw="$3"
  # Sanitize plan_count: pre-existing upstream code can yield "0\n0" from chained
  # `grep -c ... || echo 0` pipelines on bash 3 (macOS). Reduce to a single integer.
  local _plan_count
  # Take only the first line, then extract leading integer.
  _plan_count=$(printf '%s\n' "$_plan_count_raw" | head -n1 | tr -dc '0-9')
  [[ -z "$_plan_count" ]] && _plan_count=0
  # Strip any leading zeros to keep JSON numeric ("0" stays "0").
  _plan_count=$(printf '%d' "$_plan_count" 2>/dev/null || echo 0)
  local _decision="SKIP_LOGGED"
  if type policy_zero_tasks >/dev/null 2>&1; then
    _decision=$(policy_zero_tasks "$_phase_dir" "$_plan_count")
  fi
  case "$_decision" in
    ESCALATE_AMBIGUOUS)
      if type ark_escalate >/dev/null 2>&1; then
        ark_escalate architectural-ambiguity \
          "Phase $_phase: zero actionable tasks" \
          "phase_dir: $_phase_dir | plan_count: $_plan_count" >/dev/null 2>&1 || true
      fi
      log WARN "Phase $_phase: zero tasks → escalated (architectural-ambiguity)"
      update_state "$_phase" "escalated (no tasks)"
      ;;
    *)
      log INFO "Phase $_phase: zero tasks → SKIP_LOGGED (audit-logged via policy_zero_tasks)"
      update_state "$_phase" "complete (no tasks)"
      ;;
  esac
  return 0
}

# === Run a single phase ===
run_phase() {
  local phase_num="$1"
  log INFO "━━━ Running Phase $phase_num ━━━"

  # NEW: Skip if already complete (per STATE.md or ROADMAP checkboxes)
  if is_phase_complete "$phase_num"; then
    log OK "Phase $phase_num already complete (per STATE.md/ROADMAP) — skipping"
    return 0
  fi

  # NEW: resolve phase dir respecting GSD shape (decimal, slugged, etc.)
  local phase_dir
  phase_dir=$(resolve_phase_dir "$phase_num")
  local existed=$?

  if [[ $existed -eq 0 ]]; then
    log INFO "Found existing phase dir: ${phase_dir#$PROJECT_DIR/}"
  else
    log INFO "No existing phase dir; will create $phase_dir if work needed"
  fi

  # Step 1: Find existing plan files (GSD has multiple per phase, Ark has single PLAN.md)
  local plan_files
  plan_files=$(find_plan_files "$phase_dir")
  local plan_count
  plan_count=$(echo "$plan_files" | grep -cE "PLAN\.md$" 2>/dev/null || echo 0)

  if [[ $plan_count -eq 0 ]]; then
    # No plans exist
    if [[ $existed -eq 0 ]]; then
      _deliver_handle_zero_tasks "$phase_num" "$phase_dir" 0
      return 0
    fi
    log INFO "Planning phase $phase_num..."
    mkdir -p "$phase_dir"
    plan_phase "$phase_num"
    plan_files=$(find_plan_files "$phase_dir")
    plan_count=$(echo "$plan_files" | grep -cE "PLAN\.md$" 2>/dev/null || echo 0)
  else
    log OK "Phase $phase_num: $plan_count existing plan file(s) found"
  fi

  # NEW: Validate plans have actual tasks before dispatching
  local total_tasks=0
  if [[ $plan_count -gt 0 ]]; then
    while IFS= read -r pf; do  # AOS: intentional gate (loop iterator over heredoc, not user-input prompt)
      [[ -z "$pf" ]] && continue
      local c
      c=$(grep -cE '^[[:space:]]*-[[:space:]]+\[[[:space:]xX]\]' "$pf" 2>/dev/null || echo 0)
      total_tasks=$((total_tasks + c))
    done <<< "$plan_files"
    log INFO "Phase $phase_num: $total_tasks total task checkboxes across $plan_count plan(s)"
  fi

  if [[ $total_tasks -eq 0 ]]; then
    _deliver_handle_zero_tasks "$phase_num" "$phase_dir" "$plan_count"
    return 0
  fi

  # Legacy fallback: if old single-plan path exists, keep that variable
  if [[ -f "$phase_dir/PLAN.md" ]]; then
    local task_count=$total_tasks
    task_count=$(grep -cE "^[[:space:]]*-[[:space:]]+\[[[:space:]]\]" "$phase_dir/PLAN.md" 2>/dev/null || echo 0)
    if [[ $task_count -eq 0 ]]; then
      _deliver_handle_zero_tasks "$phase_num" "$phase_dir" "${plan_count:-1}"
      return 0
    fi
    log INFO "Phase $phase_num plan: $task_count tasks to execute"
  fi

  # Step 2: Execute plan
  log INFO "Executing phase $phase_num..."
  execute_phase "$phase_num"
  local exec_status=$?

  if [[ $exec_status -ne 0 ]]; then
    log ERROR "Phase $phase_num execution failed"
    return $exec_status
  fi

  # Step 3: Verify
  log INFO "Verifying phase $phase_num..."
  verify_phase "$phase_num"
  local verify_status=$?

  if [[ $verify_status -ne 0 ]]; then
    log WARN "Phase $phase_num verification failed — running self-heal"
    self_heal_phase "$phase_num"
    # Re-verify
    verify_phase "$phase_num" || {
      log ERROR "Phase $phase_num still failing after self-heal — escalating"
      record_decision "$phase_num" "failed" "self-heal-exhausted"
      return 1
    }
  fi

  # Step 4: Deploy if deployable
  if has_deploy_target; then
    log INFO "Deploying phase $phase_num..."
    deploy_phase "$phase_num" || log WARN "Deploy failed (non-fatal)"
  fi

  # Step 5: Commit + push
  log INFO "Committing phase $phase_num..."
  commit_and_push "$phase_num"

  # Step 6: Update STATE.md
  update_state "$phase_num" "complete"

  # === Phase 3 (Plan 03-05): post-phase learner trigger ===
  # Run the policy-learner over decisions from this phase. Non-fatal:
  # learning is observability, not delivery. If the script is missing
  # (deployment skew), warn and continue.
  local _learner="$PROJECT_DIR/scripts/policy-learner.sh"
  if [[ -x "$_learner" ]]; then
    local _phase_started_at
    _phase_started_at=$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u +%Y-%m-%dT%H:%M:%SZ)
    log INFO "Phase $phase_num: triggering policy-learner (--since $_phase_started_at)"
    mkdir -p "$PROJECT_DIR/.planning/delivery-logs"
    bash "$_learner" --since "$_phase_started_at" \
      >>"$PROJECT_DIR/.planning/delivery-logs/learner-phase-${phase_num}.log" 2>&1 \
      || log WARN "policy-learner returned non-zero (non-fatal)"
  else
    log INFO "policy-learner.sh not present; skipping learning pass"
  fi

  # Step 7: Record decision for brain learning
  record_decision "$phase_num" "complete" "success"

  log OK "Phase $phase_num complete"
}

# === Plan a phase via AI cascade ===
plan_phase() {
  local phase_num="$1"
  local phase_dir="$PROJECT_DIR/.planning/phase-$phase_num"
  mkdir -p "$phase_dir"

  # Extract phase requirements from ROADMAP
  local phase_block=$(awk "/^## Phase $phase_num /,/^## Phase [0-9]+ |^---$/" "$PROJECT_DIR/.planning/ROADMAP.md" 2>/dev/null)

  # Try Codex first for plan generation (free)
  local plan=""
  if command -v codex >/dev/null 2>&1; then
    plan=$(echo -e "Generate a detailed implementation plan for this phase. Output as PLAN.md with: Goals, Tasks (numbered), Files to create/modify, Tests required, Verification criteria.\n\nPhase content:\n$phase_block\n\nProject context: $(head -30 "$PROJECT_DIR/.planning/PROJECT.md" 2>/dev/null)" | \
      codex exec - 2>/dev/null </dev/null || echo "")
  fi

  # Fall back to Gemini
  if [[ -z "$plan" ]] && command -v gemini >/dev/null 2>&1; then
    plan=$(echo -e "Generate a detailed implementation plan...\n$phase_block" | gemini -p - 2>/dev/null || echo "")
  fi

  # Fall back to template
  if [[ -z "$plan" ]]; then
    plan="# Phase $phase_num Plan

## Goals
[Extracted from ROADMAP]
$phase_block

## Tasks
- [ ] Task 1: Define
- [ ] Task 2: Implement
- [ ] Task 3: Test
- [ ] Task 4: Verify

## Verification
- All tests pass
- Deploys cleanly
- STATE.md updated"
  fi

  echo "$plan" > "$phase_dir/PLAN.md"
  log OK "Plan written: $phase_dir/PLAN.md"
}

# === Execute a phase plan via TEAM (Architect → Engineers → QC/QA/Security → PM) ===
execute_phase() {
  local phase_num="$1"

  log INFO "Dispatching team for Phase $phase_num..."

  # Team orchestrator: architect designs, engineers implement,
  # QC/QA/Security validate, PM gates sign-off
  bash "$VAULT_PATH/scripts/ark-team.sh" "$PROJECT_DIR" "$phase_num"
  local team_result=$?

  if [[ $team_result -eq 0 ]]; then
    log OK "Team approved phase $phase_num"
  else
    log WARN "Team blocked phase $phase_num — see CEO report"
  fi

  return $team_result
}

# === Verify phase ===
verify_phase() {
  local phase_num="$1"

  # Ensure dependencies installed first
  if [[ -f "$PROJECT_DIR/package.json" ]] && [[ ! -d "$PROJECT_DIR/node_modules" ]]; then
    log INFO "Installing npm dependencies (first run)..."
    cd "$PROJECT_DIR" && npm install --silent 2>&1 | tail -3
  fi

  # Run tests if package.json has test script
  if [[ -f "$PROJECT_DIR/package.json" ]] && grep -q '"test"' "$PROJECT_DIR/package.json" 2>/dev/null; then
    # Skip tests if no test files exist yet (Phase 0 has no implementation)
    local has_test_files=false
    if [[ -d "$PROJECT_DIR/test" ]] || [[ -d "$PROJECT_DIR/tests" ]] || \
       find "$PROJECT_DIR/src" -name "*.test.ts" -o -name "*.spec.ts" 2>/dev/null | head -1 | grep -q .; then
      has_test_files=true
    fi

    if [[ "$has_test_files" == "true" ]]; then
      log INFO "Running npm test..."
      cd "$PROJECT_DIR" && npm test --silent 2>&1 | tail -10
      return $?
    else
      log INFO "No test files yet — skipping test run for Phase $phase_num"
    fi
  fi

  # Run TypeScript check if applicable
  if [[ -f "$PROJECT_DIR/tsconfig.json" ]]; then
    cd "$PROJECT_DIR" && npx tsc --noEmit 2>&1 | tail -5
  fi

  return 0
}

# === Self-heal phase failure ===
self_heal_phase() {
  local phase_num="$1"
  local error_log="/tmp/brain-deliver-error-$phase_num-$$.log"

  # Capture recent error context
  cd "$PROJECT_DIR" && (npm test 2>&1 || true) | tail -50 > "$error_log"

  # Dispatch self-heal
  bash "$VAULT_PATH/scripts/self-heal.sh" "$error_log" "phase-$phase_num-failure" 2>&1
}

# === Deploy ===
has_deploy_target() {
  [[ -f "$PROJECT_DIR/wrangler.toml" ]] || [[ -f "$PROJECT_DIR/wrangler.jsonc" ]] || \
  grep -q '"deploy"' "$PROJECT_DIR/package.json" 2>/dev/null
}

deploy_phase() {
  local phase_num="$1"
  cd "$PROJECT_DIR"

  if [[ -f "wrangler.toml" ]] || [[ -f "wrangler.jsonc" ]]; then
    log INFO "Deploying via wrangler..."
    npx wrangler deploy --env staging 2>&1 | tail -10
  elif grep -q '"deploy"' "package.json" 2>/dev/null; then
    log INFO "Running npm run deploy..."
    npm run deploy --silent 2>&1 | tail -10
  fi
}

# === Commit + push ===
commit_and_push() {
  local phase_num="$1"
  cd "$PROJECT_DIR"

  if git diff --quiet && git diff --cached --quiet; then
    log INFO "No changes to commit"
    return 0
  fi

  git add -A
  git commit -m "Phase $phase_num: autonomous delivery

Generated by ark deliver
$(date -u +%Y-%m-%dT%H:%M:%SZ)" --quiet 2>/dev/null

  if git remote get-url origin >/dev/null 2>&1; then
    git push origin HEAD --quiet 2>/dev/null || log WARN "Push failed"
  fi
}

# === Update STATE.md ===
update_state() {
  local phase_num="$1"
  local status="$2"
  local state_file="$PROJECT_DIR/.planning/STATE.md"

  if [[ ! -f "$state_file" ]]; then
    cat > "$state_file" <<EOF
# Implementation State

**Last updated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Current Phase:** Phase $phase_num
**Status:** $status
EOF
  else
    # Update existing state
    sed -i.bak "s/^\*\*Current Phase:\*\*.*/\*\*Current Phase:\*\* Phase $phase_num/" "$state_file"
    sed -i.bak "s/^\*\*Status:\*\*.*/\*\*Status:\*\* $status/" "$state_file"
    sed -i.bak "s/^\*\*Last updated:\*\*.*/\*\*Last updated:\*\* $(date -u +%Y-%m-%dT%H:%M:%SZ)/" "$state_file"
    rm -f "$state_file.bak"
  fi
}

# === Record decision for brain ===
record_decision() {
  local phase_num="$1"
  local outcome="$2"
  local detail="$3"

  local log_path="$PROJECT_DIR/.planning/bootstrap-decisions.jsonl"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"projectType\":\"deliver\",\"customer\":\"$(basename "$PROJECT_DIR" | cut -d- -f1)\",\"projectName\":\"$(basename "$PROJECT_DIR")\",\"decisionsApplied\":[\"phase-$phase_num-$outcome\"],\"contradictionsResolved\":[],\"lessonsUsed\":[],\"timeMs\":0,\"tokenEstimate\":0,\"phaseDetail\":\"$detail\"}" >> "$log_path"

  # Trigger Phase 6 immediately to learn
  (nohup npx ts-node "$VAULT_PATH/observability/phase-6-daemon.ts" > /dev/null 2>&1 &) 2>/dev/null
}

# === Main loop ===
main() {
  print_header

  if [[ "$MODE" == "help" ]]; then
    cat <<EOF
Usage:
  ark deliver                  # Full autonomous delivery
  ark deliver --resume         # Continue from last successful phase
  ark deliver --phase N        # Run only phase N
  ark deliver --from-spec X    # Start from brainstorm spec file

What happens:
  1. Reads .planning/ROADMAP.md
  2. For each phase: plan → execute → verify → deploy → commit
  3. Self-heals on failure
  4. Updates STATE.md continuously
  5. Pushes to GitHub atomically per phase
  6. Records decisions for brain learning

Integrates with:
  /superpowers:brainstorming  → captures spec for --from-spec
  /gsd-new-project            → generates ROADMAP.md
  /gsd-plan-phase             → planned via Codex if available
  /gsd-execute-phase          → executed via Claude Code or Codex
  /gsd-verify-work            → invoked at verify step
EOF
    exit 0
  fi

  preflight

  if [[ "$MODE" == "single-phase" ]]; then
    run_phase "$PHASE_NUM"
    exit $?
  fi

  if [[ "$MODE" == "from-spec" ]]; then
    log INFO "Loading spec: $FROM_SPEC"
    if [[ ! -f "$FROM_SPEC" ]]; then
      log ERROR "Spec not found: $FROM_SPEC"
      exit 1
    fi
    # Convert spec to PROJECT.md + ROADMAP.md (placeholder — would dispatch to Codex)
    log INFO "Converting spec to project structure..."
    cp "$FROM_SPEC" "$PROJECT_DIR/.planning/PROJECT.md"
    log OK "Spec loaded. Generate ROADMAP.md manually or via /gsd-new-project, then re-run."
    exit 0
  fi

  # Full mode: iterate all phases
  local phases=$(get_phases)
  local current=$(get_current_phase)

  if [[ -z "$phases" ]]; then
    log ERROR "No phases found in ROADMAP.md. Format: '## Phase N — Title'"
    exit 1
  fi

  log INFO "Found phases:"
  echo "$phases" | sed 's/^/  /'
  echo ""

  if $RESUME; then
    log INFO "Resuming from phase $((current + 1))"
    local start_phase=$((current + 1))
  else
    local start_phase=0
  fi

  # Execute each phase
  echo "$phases" | grep -oE "^## Phase [0-9]+" | grep -oE "[0-9]+" | while read phase_num; do
    if [[ "$phase_num" -lt "$start_phase" ]]; then
      log INFO "Skipping completed phase $phase_num"
      continue
    fi

    if ! run_phase "$phase_num"; then
      log ERROR "Phase $phase_num failed — stopping pipeline"
      exit 1
    fi
  done

  log OK "All phases complete. Project delivered."
}

main "$@"
