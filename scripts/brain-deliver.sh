#!/usr/bin/env bash
# brain deliver — autonomous project delivery from design to deployed
#
# Usage:
#   brain deliver                          # Run full delivery in current project
#   brain deliver --from-spec /path/spec   # Start from brainstorm output
#   brain deliver --phase N                # Run only phase N
#   brain deliver --resume                 # Continue from last successful phase
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

VAULT_PATH="${AUTOMATION_BRAIN_PATH:-$HOME/vaults/automation-brain}"
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
    log ERROR "No .parent-automation/ — run: brain init"
    exit 1
  fi

  # Must have a roadmap
  if [[ ! -f "$PROJECT_DIR/.planning/ROADMAP.md" ]]; then
    log ERROR "No .planning/ROADMAP.md — run: brain init or write a roadmap first"
    exit 1
  fi

  # Must be a git repo
  if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    log WARN "Not a git repo — initializing"
    git init "$PROJECT_DIR" --quiet
  fi

  # Sync brain to latest
  log INFO "Syncing brain..."
  bash "$VAULT_PATH/scripts/brain-sync.sh" "$PROJECT_DIR" >/dev/null 2>&1

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

# === Run a single phase ===
run_phase() {
  local phase_num="$1"
  log INFO "━━━ Running Phase $phase_num ━━━"

  # Check for GSD planning dir
  local phase_dir="$PROJECT_DIR/.planning/phase-$phase_num"

  # Step 1: Plan phase via gsd-plan-phase or AI dispatch
  if [[ ! -f "$phase_dir/PLAN.md" ]]; then
    log INFO "Planning phase $phase_num..."
    plan_phase "$phase_num"
  else
    log OK "Phase $phase_num already planned"
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
  bash "$VAULT_PATH/scripts/brain-team.sh" "$PROJECT_DIR" "$phase_num"
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

Generated by brain deliver
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
  brain deliver                  # Full autonomous delivery
  brain deliver --resume         # Continue from last successful phase
  brain deliver --phase N        # Run only phase N
  brain deliver --from-spec X    # Start from brainstorm spec file

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
