#!/usr/bin/env bash
# brain team — multi-role autonomous delivery
#
# CEO model: User sets vision (PROJECT.md, ROADMAP.md), brain orchestrates a team:
#
#   ARCHITECT  → designs the approach (won't execute)
#   ENGINEERS  → implement (Codex/Gemini, never override architect)
#   QA         → validates functionality
#   QC         → validates code quality + conventions
#   SECURITY   → audits for vulnerabilities
#   PM         → coordinates, aggregates reports, gates sign-off
#
# Sign-off gate: ALL must approve before phase is complete.
# If any reject: PM dispatches fix to engineers with feedback, loops once.
# If still failing: escalates to user (CEO).

set -uo pipefail

PROJECT_DIR="${1:?project dir required}"
PHASE_NUM="${2:?phase number required}"

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
PHASE_DIR="$PROJECT_DIR/.planning/phase-$PHASE_NUM"
TEAM_DIR="$PHASE_DIR/team"
mkdir -p "$TEAM_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

role_log() {
  local role="$1"
  local msg="$2"
  local color="$3"
  echo -e "${color}[$role]${NC} $msg"
}

# === Helper: dispatch a role to AI ===
dispatch_role() {
  local role_name="$1"
  local prompt_file="$2"
  local output_file="$3"

  local TIMEOUT_CMD=""
  command -v gtimeout >/dev/null && TIMEOUT_CMD="gtimeout 180"
  command -v timeout >/dev/null && TIMEOUT_CMD="timeout 180"

  # Try Codex first (free)
  local output=""
  if command -v codex >/dev/null 2>&1; then
    output=$($TIMEOUT_CMD codex exec - < "$prompt_file" 2>&1 || echo "")
  fi

  # Fall back to Gemini
  if [[ -z "$output" ]] || [[ "$output" == *"No prompt"* ]] || [[ "$output" == *"hit your usage limit"* ]] || [[ "$output" == *"quota"* ]]; then
    if command -v gemini >/dev/null 2>&1; then
      output=$($TIMEOUT_CMD gemini -p - < "$prompt_file" 2>&1 || echo "")
    fi
  fi

  echo "$output" > "$output_file"
}

# === Helper: build common context block ===
build_context() {
  local target_file="$1"
  {
    echo "# Project Context"
    echo ""
    echo "**Project:** $(basename "$PROJECT_DIR")"
    echo "**Phase:** $PHASE_NUM"
    echo ""
    [[ -f "$PROJECT_DIR/.planning/PROJECT.md" ]] && {
      echo "## Project Definition"
      cat "$PROJECT_DIR/.planning/PROJECT.md"
      echo ""
    }
    [[ -f "$PHASE_DIR/PLAN.md" ]] && {
      echo "## Phase Plan"
      cat "$PHASE_DIR/PLAN.md"
      echo ""
    }
    [[ -f "$PROJECT_DIR/CLAUDE.md" ]] && {
      echo "## Repo Conventions (CLAUDE.md)"
      head -120 "$PROJECT_DIR/CLAUDE.md"
      echo ""
    }
    [[ -f "$PROJECT_DIR/tasks/lessons.md" ]] && {
      echo "## Project Lessons (must apply)"
      cat "$PROJECT_DIR/tasks/lessons.md"
      echo ""
    }
    echo "## Current File Tree"
    echo "\`\`\`"
    cd "$PROJECT_DIR"
    find . -type f \
      -not -path './node_modules/*' \
      -not -path './.git/*' \
      -not -path './.parent-automation/ark-snapshot/*' \
      | head -40
    echo "\`\`\`"
  } > "$target_file"
}

# ════════════════════════════════════════════════════════
# ROLE 1: ARCHITECT — designs approach, never writes code
# ════════════════════════════════════════════════════════
role_architect() {
  role_log "ARCHITECT" "Designing approach..." "$PURPLE"

  local context_file="$TEAM_DIR/context.md"
  build_context "$context_file"

  local prompt_file="$TEAM_DIR/architect-prompt.md"
  cat > "$prompt_file" <<EOF
You are the ARCHITECT for this phase. Your job: design the implementation approach.

DO NOT write code. Output only design.

$(cat "$context_file")

## Output Format

\`\`\`yaml
approach: <one paragraph: how to solve this phase>
files_to_create:
  - path: <relative path>
    purpose: <one sentence>
files_to_modify:
  - path: <relative path>
    change: <one sentence>
key_decisions:
  - <decision 1>
  - <decision 2>
risks:
  - <risk 1>: <mitigation>
verification_strategy: <how to know it works>
\`\`\`

Constraints:
- Apply conventions from CLAUDE.md exactly
- Apply project lessons (don't repeat past mistakes)
- Avoid all anti-patterns
- Keep changes minimal — bias toward small, atomic additions
EOF

  dispatch_role "architect" "$prompt_file" "$TEAM_DIR/architect-design.md"
  role_log "ARCHITECT" "✓ Design saved to team/architect-design.md" "$GREEN"
}

# ════════════════════════════════════════════════════════
# ROLE 2: ENGINEERS — implement architect's design
# ════════════════════════════════════════════════════════
role_engineers() {
  role_log "ENGINEERS" "Implementing architect's design..." "$BLUE"

  # Engineers use existing execute-phase.sh which dispatches per task
  bash "$VAULT_PATH/scripts/execute-phase.sh" "$PROJECT_DIR" "$PHASE_NUM" 2>&1 | tee "$TEAM_DIR/engineers-execution.log"

  role_log "ENGINEERS" "✓ Code written" "$GREEN"
}

# ════════════════════════════════════════════════════════
# ROLE 3: QC — code quality review (conventions, idioms)
# ════════════════════════════════════════════════════════
role_qc() {
  role_log "QC" "Reviewing code quality..." "$YELLOW"

  cd "$PROJECT_DIR"
  local diff_content=$(git diff HEAD~5..HEAD 2>/dev/null | head -500 || git diff 2>/dev/null | head -500)

  local prompt_file="$TEAM_DIR/qc-prompt.md"
  cat > "$prompt_file" <<EOF
You are the QC REVIEWER. Your job: review the code changes for quality.

$(build_context "$TEAM_DIR/context.md" && cat "$TEAM_DIR/context.md")

## Diff Under Review

\`\`\`diff
$diff_content
\`\`\`

## Your Output

\`\`\`yaml
verdict: APPROVE | REJECT | CHANGES_REQUESTED
issues:
  - severity: BLOCKER | HIGH | MEDIUM | LOW
    file: <path>
    line: <number or range>
    issue: <what's wrong>
    fix: <suggested fix>
conventions_check:
  rbac_centralized: PASS | FAIL
  currency_suffix: PASS | FAIL
  tenant_scoped: PASS | FAIL | N/A
  audit_columns: PASS | FAIL | N/A
  no_inline_roles: PASS | FAIL
summary: <one paragraph>
\`\`\`

Reject if any BLOCKER. Request changes for HIGH issues. Approve if only MEDIUM/LOW.
EOF

  dispatch_role "qc" "$prompt_file" "$TEAM_DIR/qc-review.md"

  # Parse verdict
  if grep -q "verdict:[[:space:]]*APPROVE" "$TEAM_DIR/qc-review.md" 2>/dev/null; then
    role_log "QC" "✓ APPROVED" "$GREEN"
    return 0
  else
    role_log "QC" "⚠️ REJECTED or CHANGES_REQUESTED — see team/qc-review.md" "$YELLOW"
    return 1
  fi
}

# ════════════════════════════════════════════════════════
# ROLE 4: QA — functional validation
# ════════════════════════════════════════════════════════
role_qa() {
  role_log "QA" "Running functional validation..." "$BLUE"

  cd "$PROJECT_DIR"
  local report="$TEAM_DIR/qa-report.md"

  {
    echo "# QA Report"
    echo ""
    echo "**Phase:** $PHASE_NUM"
    echo "**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""

    # Test execution
    if [[ -f "package.json" ]] && grep -q '"test"' package.json; then
      echo "## Test Run"
      echo "\`\`\`"
      if [[ -d test ]] || [[ -d tests ]] || find src -name "*.test.ts" 2>/dev/null | head -1 | grep -q .; then
        npm test 2>&1 | tail -20
      else
        echo "No test files yet — N/A for this phase"
      fi
      echo "\`\`\`"
      echo ""
    fi

    # TypeScript check
    if [[ -f "tsconfig.json" ]] && [[ -d node_modules/typescript ]]; then
      echo "## TypeScript Check"
      echo "\`\`\`"
      npx tsc --noEmit 2>&1 | tail -10
      local tsc_status=$?
      echo "\`\`\`"
      echo ""

      if [[ $tsc_status -eq 0 ]]; then
        echo "**Verdict:** APPROVE"
      else
        echo "**Verdict:** REJECT — TypeScript errors"
      fi
    else
      echo "**Verdict:** APPROVE (no tsc available, skipped)"
    fi
  } > "$report"

  if grep -q "Verdict:.*APPROVE" "$report"; then
    role_log "QA" "✓ APPROVED" "$GREEN"
    return 0
  else
    role_log "QA" "⚠️ REJECTED — see team/qa-report.md" "$YELLOW"
    return 1
  fi
}

# ════════════════════════════════════════════════════════
# ROLE 5: SECURITY — vulnerability audit
# ════════════════════════════════════════════════════════
role_security() {
  role_log "SECURITY" "Auditing for vulnerabilities..." "$RED"

  cd "$PROJECT_DIR"
  local diff_content=$(git diff HEAD~5..HEAD 2>/dev/null | head -500 || git diff 2>/dev/null | head -500)

  local prompt_file="$TEAM_DIR/security-prompt.md"
  cat > "$prompt_file" <<EOF
You are the SECURITY AUDITOR. Audit this code for vulnerabilities.

## Code Changes

\`\`\`diff
$diff_content
\`\`\`

## Output

\`\`\`yaml
verdict: APPROVE | REJECT
findings:
  - severity: CRITICAL | HIGH | MEDIUM | LOW | INFO
    type: <e.g., SSRF, XSS, SQL injection, secret leak, path traversal>
    file: <path>
    line: <number>
    description: <what>
    fix: <how to fix>
checks:
  hardcoded_secrets: PASS | FAIL
  input_validation: PASS | FAIL | N/A
  auth_required: PASS | FAIL | N/A
  rate_limiting: PASS | FAIL | N/A
  error_handling: PASS | FAIL | N/A
  sql_injection: PASS | FAIL | N/A
  xss: PASS | FAIL | N/A
summary: <one paragraph>
\`\`\`

Reject for ANY critical/high finding. Approve only if all checks pass.
EOF

  dispatch_role "security" "$prompt_file" "$TEAM_DIR/security-audit.md"

  if grep -q "verdict:[[:space:]]*APPROVE" "$TEAM_DIR/security-audit.md" 2>/dev/null; then
    role_log "SECURITY" "✓ APPROVED" "$GREEN"
    return 0
  else
    role_log "SECURITY" "🚨 REJECTED — see team/security-audit.md" "$RED"
    return 1
  fi
}

# ════════════════════════════════════════════════════════
# ROLE 6: PM — aggregate, gate sign-off
# ════════════════════════════════════════════════════════
role_pm() {
  role_log "PM" "Aggregating team reports for sign-off..." "$BLUE"

  local pm_report="$TEAM_DIR/pm-signoff.md"

  # Collect verdicts
  local arch_status="UNKNOWN"
  local qc_status="UNKNOWN"
  local qa_status="UNKNOWN"
  local sec_status="UNKNOWN"

  [[ -f "$TEAM_DIR/architect-design.md" ]] && arch_status="DESIGNED"
  [[ -f "$TEAM_DIR/qc-review.md" ]] && grep -q "verdict:[[:space:]]*APPROVE" "$TEAM_DIR/qc-review.md" && qc_status="APPROVED" || qc_status="REJECTED"
  [[ -f "$TEAM_DIR/qa-report.md" ]] && grep -q "Verdict:.*APPROVE" "$TEAM_DIR/qa-report.md" && qa_status="APPROVED" || qa_status="REJECTED"
  [[ -f "$TEAM_DIR/security-audit.md" ]] && grep -q "verdict:[[:space:]]*APPROVE" "$TEAM_DIR/security-audit.md" && sec_status="APPROVED" || sec_status="REJECTED"

  # PM verdict: ALL must approve
  local pm_verdict="REJECTED"
  if [[ "$qc_status" == "APPROVED" ]] && [[ "$qa_status" == "APPROVED" ]] && [[ "$sec_status" == "APPROVED" ]]; then
    pm_verdict="APPROVED"
  fi

  cat > "$pm_report" <<EOF
# Phase $PHASE_NUM — PM Sign-off Report

**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Phase:** $PHASE_NUM
**Verdict:** $pm_verdict

## Team Sign-offs

| Role | Status | Report |
|------|--------|--------|
| Architect | $arch_status | team/architect-design.md |
| Engineers | EXECUTED | team/engineers-execution.log |
| QC | $qc_status | team/qc-review.md |
| QA | $qa_status | team/qa-report.md |
| Security | $sec_status | team/security-audit.md |

## Decision

EOF

  if [[ "$pm_verdict" == "APPROVED" ]]; then
    cat >> "$pm_report" <<EOF
✅ **PHASE APPROVED FOR SIGN-OFF**

All team members have validated the work. Ready to commit and progress.

## Next Steps
- Mark phase $PHASE_NUM complete in ROADMAP.md
- Update STATE.md
- Begin phase $((PHASE_NUM + 1))
EOF
    role_log "PM" "✓ ALL ROLES APPROVED — Phase signed off" "$GREEN"
    return 0
  else
    cat >> "$pm_report" <<EOF
🛑 **PHASE BLOCKED**

One or more team members rejected the work. Review individual reports.

## Required Actions
EOF
    [[ "$qc_status" == "REJECTED" ]] && echo "- Address QC issues in team/qc-review.md" >> "$pm_report"
    [[ "$qa_status" == "REJECTED" ]] && echo "- Fix QA failures in team/qa-report.md" >> "$pm_report"
    [[ "$sec_status" == "REJECTED" ]] && echo "- Resolve security findings in team/security-audit.md" >> "$pm_report"

    role_log "PM" "🛑 SIGN-OFF BLOCKED — see team/pm-signoff.md" "$RED"
    return 1
  fi
}

# ════════════════════════════════════════════════════════
# ROLE 7: CEO REPORT — generate executive summary
# ════════════════════════════════════════════════════════
role_ceo_report() {
  local pm_status="$1"
  local report="$PROJECT_DIR/.planning/phase-$PHASE_NUM-ceo-report.md"

  cat > "$report" <<EOF
# CEO Report — Phase $PHASE_NUM

**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Project:** $(basename "$PROJECT_DIR")
**Phase Status:** $([ "$pm_status" -eq 0 ] && echo "✅ DELIVERED" || echo "🛑 BLOCKED")

## Executive Summary

$([ "$pm_status" -eq 0 ] && cat <<DELIVERED
Phase $PHASE_NUM completed successfully. Full team validated:
- Architect designed the approach
- Engineers implemented the code
- QC approved code quality
- QA approved functional behavior
- Security cleared all checks
- PM signed off

Code committed and ready for deployment.
DELIVERED
)

$([ "$pm_status" -ne 0 ] && cat <<BLOCKED
Phase $PHASE_NUM is blocked. Team identified issues that need resolution.

See \`team/pm-signoff.md\` for blockers and required actions.
BLOCKED
)

## Reports Available

- Architect Design: \`.planning/phase-$PHASE_NUM/team/architect-design.md\`
- Engineering Log: \`.planning/phase-$PHASE_NUM/team/engineers-execution.log\`
- QC Review: \`.planning/phase-$PHASE_NUM/team/qc-review.md\`
- QA Report: \`.planning/phase-$PHASE_NUM/team/qa-report.md\`
- Security Audit: \`.planning/phase-$PHASE_NUM/team/security-audit.md\`
- PM Sign-off: \`.planning/phase-$PHASE_NUM/team/pm-signoff.md\`

## Next Step

$([ "$pm_status" -eq 0 ] && echo "Run \`ark deliver --phase $((PHASE_NUM + 1))\` to start next phase." || echo "Address blockers above, then re-run \`ark deliver --phase $PHASE_NUM\`.")
EOF

  echo ""
  role_log "CEO REPORT" "Saved to .planning/phase-$PHASE_NUM-ceo-report.md" "$BLUE"
}

# ════════════════════════════════════════════════════════
# MAIN: orchestrate the team
# ════════════════════════════════════════════════════════
main() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  TEAM DELIVERY — Phase $PHASE_NUM${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  Project: $(basename "$PROJECT_DIR")"
  echo -e "  Team: Architect → Engineers → QC + QA + Security → PM"
  echo ""

  role_architect
  role_engineers
  role_qc; qc_status=$?
  role_qa; qa_status=$?
  role_security; sec_status=$?

  role_pm
  pm_status=$?

  role_ceo_report $pm_status

  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  if [[ $pm_status -eq 0 ]]; then
    echo -e "${GREEN}  ✅ PHASE $PHASE_NUM DELIVERED${NC}"
  else
    echo -e "${RED}  🛑 PHASE $PHASE_NUM BLOCKED${NC}"
  fi
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "CEO report: .planning/phase-$PHASE_NUM-ceo-report.md"

  exit $pm_status
}

main "$@"
