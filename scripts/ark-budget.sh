#!/usr/bin/env bash
# ark budget — tiered token tracking with auto-swap notifications
#
# Tiers (auto-applied based on usage %):
#   GREEN   (0-50%)   → all models available (Opus, Sonnet, Haiku, Codex, Gemini)
#   YELLOW  (50-70%)  → demote Opus to Sonnet
#   ORANGE  (70-85%)  → use only free tier (Codex, Gemini)
#   RED     (85-95%)  → fallback only (regex, cached templates)
#   BLACK   (95-100%) → hard stop
#
# Usage:
#   ark budget                          # show state + tier
#   ark budget --set-cap 50000          # phase cap
#   ark budget --set-monthly 1000000    # monthly cap
#   ark budget --record <tokens> <model># log API call
#   ark budget --check                  # exit 1 if BLACK tier
#   ark budget --tier                   # output current tier (for agents to read)
#   ark budget --route <task>           # output recommended model for current tier
#   ark budget --watch                  # monitor and notify on tier changes

set -uo pipefail

PROJECT_DIR="$(pwd)"
BUDGET_FILE="$PROJECT_DIR/.planning/budget.json"
TIER_FILE="$PROJECT_DIR/.planning/budget-tier.txt"
EVENTS_LOG="${ARK_HOME:-$HOME/vaults/ark}/observability/budget-events.jsonl"
ACTION=""

# AOS policy integration (graceful degradation if missing)
VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
if [[ -f "$VAULT_PATH/scripts/ark-policy.sh" ]]; then
  # shellcheck disable=SC1091
  source "$VAULT_PATH/scripts/ark-policy.sh"
fi
if [[ -f "$VAULT_PATH/scripts/ark-escalations.sh" ]]; then
  # shellcheck disable=SC1091
  source "$VAULT_PATH/scripts/ark-escalations.sh"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --set-cap) ACTION="set-cap"; CAP="$2"; shift 2 ;;
    --set-monthly) ACTION="set-monthly"; MONTHLY="$2"; shift 2 ;;
    --record) ACTION="record"; TOKENS="$2"; MODEL="$3"; shift 3 ;;
    --check) ACTION="check"; shift ;;
    --tier) ACTION="tier"; shift ;;
    --route) ACTION="route"; TASK="${2:-default}"; shift 2 ;;
    --watch) ACTION="watch"; shift ;;
    --reset) ACTION="reset"; shift ;;
    *) shift ;;
  esac
done

# Initialize budget file
if [[ ! -f "$BUDGET_FILE" ]]; then
  mkdir -p "$(dirname "$BUDGET_FILE")"
  cat > "$BUDGET_FILE" <<EOF
{
  "phase_cap_tokens": 50000,
  "monthly_cap_tokens": 1000000,
  "monthly_period": "$(date +%Y-%m)",
  "monthly_used": 0,
  "phase_used": 0,
  "current_tier": "GREEN",
  "last_notification_tier": "GREEN",
  "history": [],
  "tier_history": []
}
EOF
fi

mkdir -p "$(dirname "$EVENTS_LOG")" 2>/dev/null

# === Compute current tier from usage ===
compute_tier() {
  python3 -c "
import json
with open('$BUDGET_FILE') as f:
    b = json.load(f)
phase_pct = (b['phase_used'] / b['phase_cap_tokens']) * 100 if b['phase_cap_tokens'] else 0
monthly_pct = (b['monthly_used'] / b['monthly_cap_tokens']) * 100 if b['monthly_cap_tokens'] else 0
worst = max(phase_pct, monthly_pct)

if worst >= 95: print('BLACK')
elif worst >= 85: print('RED')
elif worst >= 70: print('ORANGE')
elif worst >= 50: print('YELLOW')
else: print('GREEN')
"
}

# === Notify on tier change ===
notify_tier_change() {
  local old_tier="$1"
  local new_tier="$2"

  # Write tier file (other agents poll this)
  echo "$new_tier" > "$TIER_FILE"

  # Append to events log (audit + cross-project view)
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"project\":\"$(basename "$PROJECT_DIR")\",\"old_tier\":\"$old_tier\",\"new_tier\":\"$new_tier\",\"event\":\"tier_change\"}" >> "$EVENTS_LOG"

  # Update budget file
  python3 -c "
import json, datetime
with open('$BUDGET_FILE') as f:
    b = json.load(f)
b['current_tier'] = '$new_tier'
b['last_notification_tier'] = '$new_tier'
b['tier_history'].append({
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'from': '$old_tier',
    'to': '$new_tier'
})
b['tier_history'] = b['tier_history'][-50:]
with open('$BUDGET_FILE', 'w') as f:
    json.dump(b, f, indent=2)
"

  # Visual notification
  case "$new_tier" in
    YELLOW)
      echo "🟡 BUDGET TIER: YELLOW (50%+) — Opus demoted to Sonnet"
      ;;
    ORANGE)
      echo "🟠 BUDGET TIER: ORANGE (70%+) — Free tier only (Codex, Gemini)"
      ;;
    RED)
      echo "🔴 BUDGET TIER: RED (85%+) — Fallback only (regex, cached)"
      ;;
    BLACK)
      echo "⚫ BUDGET TIER: BLACK (95%+) — Hard stop. New phases blocked."
      ;;
    GREEN)
      echo "🟢 BUDGET TIER: GREEN (<50%) — All models available"
      ;;
  esac

  # System notification on macOS (Linux: notify-send)
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"Tier: $old_tier → $new_tier\" with title \"Ark Budget\" sound name \"Glass\"" 2>/dev/null || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "Ark Budget" "Tier: $old_tier → $new_tier" 2>/dev/null || true
  fi

  # Compute messages outside the heredoc to avoid bash case-in-heredoc issues
  local meaning=""
  local recommendation=""
  case "$new_tier" in
    GREEN)  meaning="Normal operation. All models available."
            recommendation="Continue normal work." ;;
    YELLOW) meaning="50% budget used. Routing demotes Opus → Sonnet to extend runway."
            recommendation="Continue normal work." ;;
    ORANGE) meaning="70% budget used. Free tier only (Codex, Gemini). Paid models suspended."
            recommendation="Consider raising cap if phase needs paid tier: ark budget --set-cap <bigger>" ;;
    RED)    meaning="85% budget used. Critical — fallback to regex extraction and cached templates."
            recommendation="Phase will run with degraded quality. Review carefully before signing off." ;;
    BLACK)  meaning="Budget exhausted. New AI dispatches BLOCKED."
            recommendation="STOP. Reset phase budget (ark budget --reset) or raise cap (ark budget --set-cap <bigger>)." ;;
  esac

  # Per-project notification file (SessionStart hook surfaces this)
  cat > "$PROJECT_DIR/.planning/budget-notification.md" <<EOF
# Budget Tier Change

**$(date -u +%Y-%m-%dT%H:%M:%SZ)**

Project: $(basename "$PROJECT_DIR")
Tier: **$old_tier → $new_tier**

## What This Means

$meaning

## Recommended Action

$recommendation
EOF
}

# === Detect and apply tier changes ===
check_and_notify() {
  local current_tier=$(compute_tier)
  local last_tier=$(python3 -c "
import json
with open('$BUDGET_FILE') as f:
    b = json.load(f)
print(b.get('current_tier', 'GREEN'))
")

  if [[ "$current_tier" != "$last_tier" ]]; then
    notify_tier_change "$last_tier" "$current_tier"
  fi
}

# === Get recommended model for current tier ===
recommend_model() {
  local task_type="${1:-default}"
  local tier=$(compute_tier)

  case "$tier" in
    GREEN)
      case "$task_type" in
        architect|complex|novel) echo "claude-opus-4-7" ;;
        code|engineering) echo "codex" ;;
        review|qc|security) echo "claude-sonnet-4-6" ;;
        synthesis|breadth) echo "gemini-2-5-pro" ;;
        *) echo "claude-haiku-4-5" ;;
      esac
      ;;
    YELLOW)
      # Demote Opus to Sonnet
      case "$task_type" in
        architect|complex|novel) echo "claude-sonnet-4-6" ;;
        code|engineering) echo "codex" ;;
        review|qc|security) echo "claude-sonnet-4-6" ;;
        synthesis|breadth) echo "gemini-2-5-pro" ;;
        *) echo "claude-haiku-4-5" ;;
      esac
      ;;
    ORANGE)
      # Free tier only
      case "$task_type" in
        code|engineering|architect|review|qc) echo "codex" ;;
        synthesis|breadth) echo "gemini-2-5-pro" ;;
        *) echo "codex" ;;
      esac
      ;;
    RED)
      # Local/cached only
      echo "regex-fallback"
      ;;
    BLACK)
      echo "BLOCKED"
      ;;
  esac
}

case "$ACTION" in
  set-cap)
    python3 -c "
import json
with open('$BUDGET_FILE') as f: b = json.load(f)
b['phase_cap_tokens'] = $CAP
with open('$BUDGET_FILE', 'w') as f: json.dump(b, f, indent=2)
print('✅ Phase cap: $CAP tokens')
"
    check_and_notify
    ;;

  set-monthly)
    python3 -c "
import json
with open('$BUDGET_FILE') as f: b = json.load(f)
b['monthly_cap_tokens'] = $MONTHLY
with open('$BUDGET_FILE', 'w') as f: json.dump(b, f, indent=2)
print('✅ Monthly cap: $MONTHLY tokens')
"
    check_and_notify
    ;;

  record)
    python3 -c "
import json, datetime
with open('$BUDGET_FILE') as f: b = json.load(f)
current_period = datetime.datetime.utcnow().strftime('%Y-%m')
if b.get('monthly_period') != current_period:
    b['monthly_period'] = current_period
    b['monthly_used'] = 0
b['phase_used'] = b.get('phase_used', 0) + $TOKENS
b['monthly_used'] = b.get('monthly_used', 0) + $TOKENS
b['history'].append({
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'tokens': $TOKENS,
    'model': '$MODEL'
})
b['history'] = b['history'][-200:]
with open('$BUDGET_FILE', 'w') as f: json.dump(b, f, indent=2)
"
    # Check tier change after recording
    check_and_notify
    ;;

  check)
    tier=$(compute_tier)
    case "$tier" in
      BLACK)
        echo "🛑 BUDGET EXHAUSTED — exit 1"
        exit 1
        ;;
      RED|ORANGE|YELLOW)
        echo "⚠️  Tier: $tier — agents should adjust"
        exit 0
        ;;
      GREEN)
        echo "✅ Tier: GREEN"
        exit 0
        ;;
    esac
    ;;

  tier)
    compute_tier
    ;;

  route)
    recommend_model "$TASK"
    ;;

  watch)
    echo "Watching budget tier (Ctrl+C to stop)..."
    last=$(compute_tier)
    while true; do
      current=$(compute_tier)
      if [[ "$current" != "$last" ]]; then
        echo "[$(date)] Tier changed: $last → $current"
        notify_tier_change "$last" "$current"
        last="$current"
      fi
      sleep 30
    done
    ;;

  reset)
    python3 -c "
import json
with open('$BUDGET_FILE') as f: b = json.load(f)
b['phase_used'] = 0
with open('$BUDGET_FILE', 'w') as f: json.dump(b, f, indent=2)
print('✅ Phase budget reset')
"
    check_and_notify
    ;;

  *)
    # Show state with tier
    python3 -c "
import json
with open('$BUDGET_FILE') as f:
    b = json.load(f)
phase_pct = (b['phase_used'] / b['phase_cap_tokens']) * 100 if b['phase_cap_tokens'] else 0
monthly_pct = (b['monthly_used'] / b['monthly_cap_tokens']) * 100 if b['monthly_cap_tokens'] else 0

emoji = {'GREEN': '🟢', 'YELLOW': '🟡', 'ORANGE': '🟠', 'RED': '🔴', 'BLACK': '⚫'}.get(b.get('current_tier', 'GREEN'), '?')

print(f'{emoji} Ark Budget — Tier: {b.get(\"current_tier\", \"GREEN\")}')
print('')
print(f'  Phase:    {b[\"phase_used\"]:>10,} / {b[\"phase_cap_tokens\"]:>10,} tokens ({phase_pct:.1f}%)')
print(f'  Monthly:  {b[\"monthly_used\"]:>10,} / {b[\"monthly_cap_tokens\"]:>10,} tokens ({monthly_pct:.1f}%)')
print(f'  Period:   {b[\"monthly_period\"]}')
print('')
print('Tier model routing:')
print('  GREEN   (<50%)   — all models (Opus, Sonnet, Haiku, Codex, Gemini)')
print('  YELLOW  (50-70%) — Opus → Sonnet (demote expensive)')
print('  ORANGE  (70-85%) — free tier only (Codex, Gemini)')
print('  RED     (85-95%) — fallback only (regex, cached)')
print('  BLACK   (95%+)   — hard stop, new dispatches blocked')
print('')
if b.get('tier_history'):
    print('Recent tier changes:')
    for h in b['tier_history'][-5:]:
        print(f'  {h[\"timestamp\"]}: {h[\"from\"]} → {h[\"to\"]}')
"
    # Recheck tier on every show
    check_and_notify >/dev/null 2>&1
    ;;
esac
