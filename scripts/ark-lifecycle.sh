#!/usr/bin/env bash
# ark lifecycle — project lifecycle management
#
# Usage:
#   ark lifecycle status              # show current lifecycle stage
#   ark lifecycle archive             # archive completed project
#   ark lifecycle maintain            # switch to maintenance mode
#   ark lifecycle sunset              # mark for shutdown
#   ark lifecycle revive              # bring back from archive

set -uo pipefail

PROJECT_DIR="$(pwd)"
ACTION="${1:-status}"
LIFECYCLE_FILE="$PROJECT_DIR/.planning/lifecycle.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize if missing
if [[ ! -f "$LIFECYCLE_FILE" ]]; then
  mkdir -p "$(dirname "$LIFECYCLE_FILE")"
  cat > "$LIFECYCLE_FILE" <<EOF
{
  "stage": "active",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "history": []
}
EOF
fi

transition() {
  local new_stage="$1"
  local reason="$2"

  python3 -c "
import json, datetime
with open('$LIFECYCLE_FILE') as f:
    l = json.load(f)
old_stage = l['stage']
l['stage'] = '$new_stage'
l['history'].append({
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'from': old_stage,
    'to': '$new_stage',
    'reason': '$reason'
})
l['last_transition'] = l['history'][-1]['timestamp']
with open('$LIFECYCLE_FILE', 'w') as f:
    json.dump(l, f, indent=2)
print(f'✅ Transitioned: {old_stage} → $new_stage')
"
}

case "$ACTION" in
  status)
    python3 -c "
import json
with open('$LIFECYCLE_FILE') as f:
    l = json.load(f)

stage = l['stage']
emoji = {
    'active': '🟢',
    'maintenance': '🟡',
    'archived': '⚫',
    'sunset': '🔴'
}.get(stage, '?')

print(f'{emoji} Lifecycle: {stage}')
print(f'   Created: {l[\"created\"]}')
if 'last_transition' in l:
    print(f'   Last transition: {l[\"last_transition\"]}')
print(f'   History: {len(l[\"history\"])} transitions')
"
    ;;

  archive)
    transition "archived" "Archived via ark lifecycle"
    # Update STATE.md
    if [[ -f "$PROJECT_DIR/.planning/STATE.md" ]]; then
      sed -i.bak "s/^\*\*Status:\*\*.*/\*\*Status:\*\* archived/" "$PROJECT_DIR/.planning/STATE.md"
      rm -f "$PROJECT_DIR/.planning/STATE.md.bak"
    fi

    # Disable hooks for this project (won't trigger brain auto-extract anymore)
    touch "$PROJECT_DIR/.parent-automation/.archived"

    echo ""
    echo -e "${YELLOW}Project archived${NC}"
    echo "  - Ark hooks disabled for this project"
    echo "  - STATE.md updated"
    echo "  - To revive: ark lifecycle revive"
    ;;

  maintain)
    transition "maintenance" "Switched to maintenance mode"
    if [[ -f "$PROJECT_DIR/.planning/STATE.md" ]]; then
      sed -i.bak "s/^\*\*Status:\*\*.*/\*\*Status:\*\* maintenance/" "$PROJECT_DIR/.planning/STATE.md"
      rm -f "$PROJECT_DIR/.planning/STATE.md.bak"
    fi
    echo ""
    echo -e "${YELLOW}Maintenance mode${NC}"
    echo "  - Only bug fixes and security updates"
    echo "  - No new features"
    echo "  - Ark deliver will refuse new phases"
    ;;

  sunset)
    transition "sunset" "Marked for shutdown"
    if [[ -f "$PROJECT_DIR/.planning/STATE.md" ]]; then
      sed -i.bak "s/^\*\*Status:\*\*.*/\*\*Status:\*\* sunset/" "$PROJECT_DIR/.planning/STATE.md"
      rm -f "$PROJECT_DIR/.planning/STATE.md.bak"
    fi
    echo ""
    echo -e "${RED}Project marked for sunset${NC}"
    echo "  - Plan deprecation timeline"
    echo "  - Migrate users/data"
    echo "  - Final shutdown date in PROJECT.md"
    ;;

  revive)
    transition "active" "Revived from archive"
    rm -f "$PROJECT_DIR/.parent-automation/.archived"
    if [[ -f "$PROJECT_DIR/.planning/STATE.md" ]]; then
      sed -i.bak "s/^\*\*Status:\*\*.*/\*\*Status:\*\* active/" "$PROJECT_DIR/.planning/STATE.md"
      rm -f "$PROJECT_DIR/.planning/STATE.md.bak"
    fi
    echo ""
    echo -e "${GREEN}Project revived${NC}"
    echo "  - Ark hooks re-enabled"
    echo "  - Run: ark sync"
    ;;
esac
