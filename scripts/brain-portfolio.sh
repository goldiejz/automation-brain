#!/usr/bin/env bash
# brain portfolio — CEO dashboard across all projects
#
# Usage:
#   brain portfolio                # all projects in ~/code/
#   brain portfolio /path/to/dir   # different parent dir
#   brain portfolio --watch        # auto-refresh

set -uo pipefail

SEARCH_DIR="${1:-$HOME/code}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "🧠 Brain Portfolio — CEO Dashboard"
echo "Scanning: $SEARCH_DIR"
echo ""

# Find all brain-integrated projects
PROJECTS=$(find "$SEARCH_DIR" -maxdepth 3 -type d -name ".parent-automation" 2>/dev/null | xargs -I{} dirname {} | sort)

if [[ -z "$PROJECTS" ]]; then
  echo "No brain-integrated projects found under $SEARCH_DIR"
  exit 0
fi

# Header
printf "%-30s %-12s %-12s %-12s %-15s %s\n" "PROJECT" "PHASE" "STATUS" "DECISIONS" "TOKENS" "LAST DELIVERY"
echo "─────────────────────────────────────────────────────────────────────────────────────────────────────────────"

while IFS= read -r project; do
  [[ -z "$project" ]] && continue

  name=$(basename "$project")

  # Get current phase from STATE.md
  phase=$(grep -oE "Phase [0-9]+" "$project/.planning/STATE.md" 2>/dev/null | head -1 || echo "?")

  # Get status
  status=$(grep -oE "Status:.*" "$project/.planning/STATE.md" 2>/dev/null | head -1 | sed 's/.*Status:[[:space:]]*//' | head -c 12 || echo "?")

  # Decision count
  decisions=$(wc -l < "$project/.planning/bootstrap-decisions.jsonl" 2>/dev/null | tr -d ' ' || echo 0)

  # Token usage
  tokens="-"
  if [[ -f "$project/.planning/budget.json" ]]; then
    tokens=$(python3 -c "
import json
with open('$project/.planning/budget.json') as f:
    b = json.load(f)
print(f\"{b.get('monthly_used', 0):,}\")
" 2>/dev/null || echo "-")
  fi

  # Last delivery from latest CEO report
  last_report=$(ls -t "$project/.planning/phase-"*-ceo-report.md 2>/dev/null | head -1)
  if [[ -n "$last_report" ]]; then
    last_delivery=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$last_report" 2>/dev/null || stat -c "%y" "$last_report" 2>/dev/null | head -c 16)
  else
    last_delivery="never"
  fi

  # Color status
  case "$status" in
    *complete*|*delivered*) status_color="$GREEN" ;;
    *blocked*) status_color="$RED" ;;
    *progress*|*in-progress*) status_color="$YELLOW" ;;
    *) status_color="$NC" ;;
  esac

  printf "%-30s %-12s ${status_color}%-12s${NC} %-12s %-15s %s\n" "$name" "$phase" "$status" "$decisions" "$tokens" "$last_delivery"
done <<< "$PROJECTS"

echo ""

# Summary stats
TOTAL_PROJECTS=$(echo "$PROJECTS" | grep -c .)
TOTAL_DECISIONS=0
TOTAL_TOKENS=0

while IFS= read -r project; do
  [[ -z "$project" ]] && continue
  d=$(wc -l < "$project/.planning/bootstrap-decisions.jsonl" 2>/dev/null | tr -d ' ' || echo 0)
  TOTAL_DECISIONS=$((TOTAL_DECISIONS + d))

  if [[ -f "$project/.planning/budget.json" ]]; then
    t=$(python3 -c "
import json
with open('$project/.planning/budget.json') as f:
    b = json.load(f)
print(b.get('monthly_used', 0))
" 2>/dev/null || echo 0)
    TOTAL_TOKENS=$((TOTAL_TOKENS + t))
  fi
done <<< "$PROJECTS"

echo "Summary:"
echo "  Total projects:  $TOTAL_PROJECTS"
echo "  Total decisions: $TOTAL_DECISIONS"
echo "  Total tokens:    $(printf "%'d" $TOTAL_TOKENS) (this month)"
echo ""

# Cross-project insights
VAULT_PATH="${AUTOMATION_BRAIN_PATH:-$HOME/vaults/automation-brain}"
if [[ -f "$VAULT_PATH/observability/cross-customer-insights.md" ]]; then
  echo "Latest cross-project insights (top 5):"
  grep -A1 "^### " "$VAULT_PATH/observability/cross-customer-insights.md" | head -10 | sed 's/^/  /'
fi
