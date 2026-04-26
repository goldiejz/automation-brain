#!/usr/bin/env bash
# ark doctor — comprehensive health check
#
# Verifies:
# - Vault exists and is git-tracked
# - All hook scripts present and executable
# - Hooks registered in settings.json
# - Skill installed
# - CLI tools available (codex, gemini, ts-node)
# - GitHub remote reachable
# - Phase 6 daemon runs without errors
# - Recent activity (lessons captured, decisions logged)

set -uo pipefail

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

check() {
  local name="$1"
  local cmd="$2"
  local mode="${3:-fail}"  # fail or warn

  if eval "$cmd" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✅${NC} $name"
    PASS=$((PASS+1))
    return 0
  else
    if [[ "$mode" == "warn" ]]; then
      echo -e "  ${YELLOW}⚠️${NC}  $name"
      WARN=$((WARN+1))
    else
      echo -e "  ${RED}❌${NC} $name"
      FAIL=$((FAIL+1))
    fi
    return 1
  fi
}

echo "🩺 Ark Doctor — Health Check"
echo ""

# === Vault checks ===
echo "Vault:"
check "Vault directory exists" "[[ -d '$VAULT_PATH' ]]"
check "Vault is git repo" "[[ -d '$VAULT_PATH/.git' ]]"
check "GitHub remote configured" "git -C '$VAULT_PATH' remote -v | grep -q origin"
check "GitHub remote reachable" "git -C '$VAULT_PATH' ls-remote origin HEAD" warn
check "STRUCTURE.md present" "[[ -f '$VAULT_PATH/STRUCTURE.md' ]]"
check "package.json + tsconfig.json" "[[ -f '$VAULT_PATH/package.json' ]] && [[ -f '$VAULT_PATH/tsconfig.json' ]]"
check "Lessons directory" "[[ -d '$VAULT_PATH/lessons' ]]"
check "Cache directory" "[[ -d '$VAULT_PATH/cache' ]]"
check "Templates directory" "[[ -d '$VAULT_PATH/templates/parent-automation' ]]"

# === Scripts ===
echo ""
echo "CLI scripts:"
for script in brain ark-sync.sh ark-align.sh extract-learnings.sh self-heal.sh; do
  check "$script executable" "[[ -x '$VAULT_PATH/scripts/$script' ]]"
done

# === Hooks ===
echo ""
echo "Hooks:"
for hook in ark-session-start.sh ark-session-end.sh ark-extract-learnings.sh ark-error-monitor.sh; do
  check "$hook in ~/.claude/hooks/" "[[ -x \"\$HOME/.claude/hooks/$hook\" ]]"
done

# Hook registration
echo ""
echo "Hook registration in settings.json:"
SETTINGS="$HOME/.claude/settings.json"
check "settings.json exists" "[[ -f '$SETTINGS' ]]"
check "SessionStart hook registered" "grep -q brain-session-start '$SETTINGS'"
check "Stop hook (extract) registered" "grep -q brain-extract-learnings '$SETTINGS'"
check "Stop hook (error monitor) registered" "grep -q brain-error-monitor '$SETTINGS'"

# === Skill ===
echo ""
echo "Skill:"
check "Ark skill installed" "[[ -f \"\$HOME/.claude/skills/brain/SKILL.md\" ]]"

# === CLI tools ===
echo ""
echo "AI CLI tools (for auto-extraction + self-heal):"
check "codex CLI" "command -v codex" warn
check "gemini CLI" "command -v gemini" warn
check "node + ts-node" "command -v node && [[ -d '$VAULT_PATH/node_modules/ts-node' ]]" warn
check "ANTHROPIC_API_KEY set" "[[ -n \"\${ANTHROPIC_API_KEY:-}\" ]]" warn

# === Phase 6 sanity check ===
echo ""
echo "Phase 6 daemon:"
if cd "$VAULT_PATH" && npx ts-node observability/phase-6-daemon.ts >/dev/null 2>&1; then
  echo -e "  ${GREEN}✅${NC} Phase 6 daemon runs without errors"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌${NC} Phase 6 daemon failed"
  FAIL=$((FAIL+1))
fi

# === Recent activity ===
echo ""
echo "Recent activity:"
LESSON_COUNT=$(find "$VAULT_PATH/lessons/auto-captured" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
HEAL_COUNT=$(find "$VAULT_PATH/self-healing/proposed" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
TOTAL_LESSONS=$(find "$VAULT_PATH/lessons" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
LAST_COMMIT=$(cd "$VAULT_PATH" && git log -1 --format='%cr' 2>/dev/null || echo "unknown")

echo "  Total lessons:           $TOTAL_LESSONS"
echo "  Auto-captured (recent):  $LESSON_COUNT"
echo "  Self-heal proposals:     $HEAL_COUNT"
echo "  Last vault commit:       $LAST_COMMIT"

# === Project integration check ===
echo ""
echo "Project integration (current dir: $(pwd)):"
PROJECT_DIR="$(pwd)"
if [[ -d "$PROJECT_DIR/.parent-automation" ]]; then
  check "Ark integrated in this project" "[[ -d '$PROJECT_DIR/.parent-automation' ]]"
  check "Snapshot present" "[[ -d '$PROJECT_DIR/.parent-automation/brain-snapshot' ]]"
  check "Decision log writable" "[[ -w '$PROJECT_DIR/.planning/bootstrap-decisions.jsonl' ]]" warn
  DECISIONS=$(wc -l < "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl" 2>/dev/null | tr -d ' ' || echo 0)
  echo "  Decisions in this project: $DECISIONS"
else
  echo -e "  ${YELLOW}⚠️${NC}  Not integrated. Run: ark init"
fi

# === Summary ===
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Summary: ${GREEN}$PASS passed${NC} · ${YELLOW}$WARN warnings${NC} · ${RED}$FAIL failed${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "🛠️  To repair: review failures above, or check ~/vaults/ark/self-healing/"
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo ""
  echo "⚠️  Some optional features unavailable. Ark will use fallbacks."
  exit 0
else
  echo ""
  echo "✅ All systems operational."
  exit 0
fi
