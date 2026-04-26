#!/usr/bin/env bash
# brain team v2 — real subagent dispatch via Claude Code Agent tool
#
# Where v1 used the same Codex with role prompts (shared blind spots),
# v2 dispatches each role to its specialized subagent for true diversity:
#
#   Architect → Claude architect subagent (deep reasoning)
#   Engineer  → Codex CLI (fast code generation)
#   QC        → typescript-reviewer / python-reviewer subagent
#   Security  → security-reviewer subagent
#   QA        → npm test + tsc (objective signal)
#   PM        → Aggregator (no AI, just rules)
#
# This script generates a Claude Code dispatch plan that the user invokes
# from inside Claude Code via /ark deliver, since shell can't directly
# call Agent tool — it requires Claude Code session context.

set -uo pipefail

PROJECT_DIR="${1:?project dir required}"
PHASE_NUM="${2:?phase number required}"

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
PHASE_DIR="$PROJECT_DIR/.planning/phase-$PHASE_NUM"
TEAM_DIR="$PHASE_DIR/team"
mkdir -p "$TEAM_DIR"

# Generate dispatch plan that Claude Code skill reads
cat > "$PHASE_DIR/team-dispatch-plan.md" <<EOF
# Team Dispatch Plan — Phase $PHASE_NUM

## Project
$(basename "$PROJECT_DIR")

## Phase Plan
$(cat "$PHASE_DIR/PLAN.md" 2>/dev/null || echo "[No PLAN.md found]")

## Dispatch Sequence

When the brain skill executes this plan, it should:

### 1. ARCHITECT (use Agent tool with subagent_type=architect)
- description: "Design phase $PHASE_NUM approach"
- prompt: "Read PLAN.md at $PHASE_DIR/PLAN.md and CLAUDE.md at $PROJECT_DIR/CLAUDE.md.
  Design the implementation approach. Output: files to create/modify, key decisions, risks.
  Do not write code. Output to $TEAM_DIR/architect-design.md."

### 2. ENGINEERS (use bash to run execute-phase.sh)
- After architect approves, dispatch engineering layer
- Bash: bash $VAULT_PATH/scripts/execute-phase.sh "$PROJECT_DIR" "$PHASE_NUM"

### 3. QC (use Agent tool with subagent_type=typescript-reviewer or python-reviewer)
- description: "Review code changes for Phase $PHASE_NUM"
- prompt: "Run git diff HEAD~5..HEAD in $PROJECT_DIR. Review changes for:
  - Type safety
  - Idiomatic patterns
  - RBAC centralization (apply L-018)
  - Currency suffix discipline
  - Tenant scoping
  Output verdict: APPROVE | REJECT | CHANGES_REQUESTED. Save to $TEAM_DIR/qc-review.md."

### 4. SECURITY (use Agent tool with subagent_type=security-reviewer)
- description: "Security audit Phase $PHASE_NUM"
- prompt: "Audit recent changes in $PROJECT_DIR for security issues:
  - Hardcoded secrets
  - SSRF, XSS, SQL injection
  - Path traversal
  - Auth/RBAC gaps
  Output verdict to $TEAM_DIR/security-audit.md."

### 5. QA (objective tests)
- Bash: cd $PROJECT_DIR && npm test 2>&1 > $TEAM_DIR/qa-tests.log
- Bash: cd $PROJECT_DIR && npx tsc --noEmit 2>&1 > $TEAM_DIR/qa-tsc.log

### 6. PM (aggregation, no AI)
- Bash: bash $VAULT_PATH/scripts/ark-pm-signoff.sh "$PROJECT_DIR" "$PHASE_NUM"
- Reads all team artifacts, computes verdict
- Generates CEO report

## Sign-off Gate
ALL of: Architect designed, Engineers committed, QC approved, Security cleared, QA tests pass.
Any rejection blocks phase. PM cannot override individual rejections.
EOF

echo "✅ Dispatch plan: $PHASE_DIR/team-dispatch-plan.md"
echo ""
echo "To execute via Claude Code subagents:"
echo "  /ark deliver --phase $PHASE_NUM"
echo ""
echo "(The brain skill in Claude Code reads this plan and dispatches to real subagents)"
