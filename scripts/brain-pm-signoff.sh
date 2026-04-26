#!/usr/bin/env bash
# brain-pm-signoff — aggregate team reports and gate sign-off
#
# Pure aggregator — no AI calls. Reads YAML/markdown verdicts from team
# members and produces final PM decision + CEO report.

set -uo pipefail

PROJECT_DIR="${1:?project dir required}"
PHASE_NUM="${2:?phase number required}"

PHASE_DIR="$PROJECT_DIR/.planning/phase-$PHASE_NUM"
TEAM_DIR="$PHASE_DIR/team"

# Determine each role's verdict
ARCH_STATUS="UNKNOWN"
[[ -f "$TEAM_DIR/architect-design.md" ]] && ARCH_STATUS="DESIGNED"

QC_STATUS="UNKNOWN"
if [[ -f "$TEAM_DIR/qc-review.md" ]]; then
  if grep -qiE "verdict:\s*APPROVE|^APPROVE$|^Approved" "$TEAM_DIR/qc-review.md"; then
    QC_STATUS="APPROVED"
  elif grep -qiE "verdict:\s*REJECT|^REJECT$|^Rejected" "$TEAM_DIR/qc-review.md"; then
    QC_STATUS="REJECTED"
  else
    QC_STATUS="CHANGES_REQUESTED"
  fi
fi

SEC_STATUS="UNKNOWN"
if [[ -f "$TEAM_DIR/security-audit.md" ]]; then
  if grep -qiE "verdict:\s*APPROVE|no.*critical|no.*high" "$TEAM_DIR/security-audit.md"; then
    SEC_STATUS="APPROVED"
  else
    SEC_STATUS="REJECTED"
  fi
fi

QA_STATUS="UNKNOWN"
if [[ -f "$TEAM_DIR/qa-tests.log" ]]; then
  if grep -qE "passed|all tests pass|0 failed" "$TEAM_DIR/qa-tests.log"; then
    QA_STATUS="APPROVED"
  elif grep -qE "no test files|N/A" "$TEAM_DIR/qa-tests.log"; then
    QA_STATUS="N/A"
  else
    QA_STATUS="REJECTED"
  fi
fi

ENG_STATUS="UNKNOWN"
if [[ -f "$TEAM_DIR/engineers-execution.log" ]]; then
  if grep -qE "Task .* complete" "$TEAM_DIR/engineers-execution.log"; then
    ENG_STATUS="COMPLETED"
  fi
fi

# PM verdict: ALL must approve (or N/A)
PM_VERDICT="REJECTED"
if [[ "$ENG_STATUS" == "COMPLETED" ]] && \
   [[ "$QC_STATUS" == "APPROVED" ]] && \
   [[ "$SEC_STATUS" == "APPROVED" ]] && \
   ([[ "$QA_STATUS" == "APPROVED" ]] || [[ "$QA_STATUS" == "N/A" ]]); then
  PM_VERDICT="APPROVED"
fi

# Generate PM sign-off
cat > "$TEAM_DIR/pm-signoff.md" <<EOF
# Phase $PHASE_NUM — PM Sign-off

**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Verdict:** $PM_VERDICT

## Team Reports

| Role | Status | Source |
|------|--------|--------|
| Architect | $ARCH_STATUS | team/architect-design.md |
| Engineers | $ENG_STATUS | team/engineers-execution.log |
| QC | $QC_STATUS | team/qc-review.md |
| QA | $QA_STATUS | team/qa-tests.log |
| Security | $SEC_STATUS | team/security-audit.md |

## Decision

EOF

if [[ "$PM_VERDICT" == "APPROVED" ]]; then
  echo "✅ All team members approve. Phase signed off." >> "$TEAM_DIR/pm-signoff.md"
else
  cat >> "$TEAM_DIR/pm-signoff.md" <<EOF
🛑 Phase blocked. Required actions:

EOF
  [[ "$ENG_STATUS" != "COMPLETED" ]] && echo "- Engineering not complete — see engineers-execution.log" >> "$TEAM_DIR/pm-signoff.md"
  [[ "$QC_STATUS" != "APPROVED" ]] && echo "- Address QC issues — see qc-review.md" >> "$TEAM_DIR/pm-signoff.md"
  [[ "$SEC_STATUS" != "APPROVED" ]] && echo "- Resolve security findings — see security-audit.md" >> "$TEAM_DIR/pm-signoff.md"
  [[ "$QA_STATUS" == "REJECTED" ]] && echo "- Fix failing tests — see qa-tests.log" >> "$TEAM_DIR/pm-signoff.md"
fi

# Generate CEO report
cat > "$PROJECT_DIR/.planning/phase-$PHASE_NUM-ceo-report.md" <<EOF
# CEO Report — Phase $PHASE_NUM

**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Project:** $(basename "$PROJECT_DIR")
**Status:** $([ "$PM_VERDICT" == "APPROVED" ] && echo "✅ DELIVERED" || echo "🛑 BLOCKED")

## Team Sign-offs
| Role | Status |
|------|--------|
| Architect | $ARCH_STATUS |
| Engineers | $ENG_STATUS |
| QC | $QC_STATUS |
| QA | $QA_STATUS |
| Security | $SEC_STATUS |
| PM | $PM_VERDICT |

## Next Step
$([ "$PM_VERDICT" == "APPROVED" ] && echo "Run \`brain deliver --phase $((PHASE_NUM + 1))\`" || echo "Address blockers in team/pm-signoff.md, then retry")

## Detailed Reports
.planning/phase-$PHASE_NUM/team/*.md
EOF

echo "✅ PM sign-off: $TEAM_DIR/pm-signoff.md"
echo "✅ CEO report: .planning/phase-$PHASE_NUM-ceo-report.md"
echo "Verdict: $PM_VERDICT"

[[ "$PM_VERDICT" == "APPROVED" ]] && exit 0 || exit 1
