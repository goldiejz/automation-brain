#!/usr/bin/env bash
# brain budget — token usage tracking and budget enforcement
#
# Usage:
#   brain budget                       # show current spend
#   brain budget --set-cap 50000       # set per-phase cap (tokens)
#   brain budget --set-monthly 1000000 # set monthly cap
#   brain budget --record <tokens> <model>  # record an API call (called by execute-phase)
#   brain budget --check               # exit 1 if over budget

set -uo pipefail

PROJECT_DIR="$(pwd)"
BUDGET_FILE="$PROJECT_DIR/.planning/budget.json"
ACTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --set-cap) ACTION="set-cap"; CAP="$2"; shift 2 ;;
    --set-monthly) ACTION="set-monthly"; MONTHLY="$2"; shift 2 ;;
    --record) ACTION="record"; TOKENS="$2"; MODEL="$3"; shift 3 ;;
    --check) ACTION="check"; shift ;;
    --reset) ACTION="reset"; shift ;;
    *) shift ;;
  esac
done

# Initialize if missing
if [[ ! -f "$BUDGET_FILE" ]]; then
  mkdir -p "$(dirname "$BUDGET_FILE")"
  cat > "$BUDGET_FILE" <<EOF
{
  "phase_cap_tokens": 50000,
  "monthly_cap_tokens": 1000000,
  "monthly_period": "$(date +%Y-%m)",
  "monthly_used": 0,
  "phase_used": 0,
  "history": []
}
EOF
fi

case "$ACTION" in
  set-cap)
    python3 -c "
import json
with open('$BUDGET_FILE') as f:
    b = json.load(f)
b['phase_cap_tokens'] = $CAP
with open('$BUDGET_FILE', 'w') as f:
    json.dump(b, f, indent=2)
print('✅ Per-phase cap set to $CAP tokens')
"
    ;;

  set-monthly)
    python3 -c "
import json
with open('$BUDGET_FILE') as f:
    b = json.load(f)
b['monthly_cap_tokens'] = $MONTHLY
with open('$BUDGET_FILE', 'w') as f:
    json.dump(b, f, indent=2)
print('✅ Monthly cap set to $MONTHLY tokens')
"
    ;;

  record)
    python3 -c "
import json, datetime
with open('$BUDGET_FILE') as f:
    b = json.load(f)

# Reset monthly if new period
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

# Keep only last 200 history entries
b['history'] = b['history'][-200:]

with open('$BUDGET_FILE', 'w') as f:
    json.dump(b, f, indent=2)
"
    ;;

  check)
    python3 -c "
import json, sys
with open('$BUDGET_FILE') as f:
    b = json.load(f)

phase_pct = (b['phase_used'] / b['phase_cap_tokens']) * 100 if b['phase_cap_tokens'] else 0
monthly_pct = (b['monthly_used'] / b['monthly_cap_tokens']) * 100 if b['monthly_cap_tokens'] else 0

if phase_pct >= 100:
    print(f'🛑 PHASE BUDGET EXCEEDED: {b[\"phase_used\"]:,} / {b[\"phase_cap_tokens\"]:,} tokens ({phase_pct:.1f}%)')
    sys.exit(1)
if monthly_pct >= 100:
    print(f'🛑 MONTHLY BUDGET EXCEEDED: {b[\"monthly_used\"]:,} / {b[\"monthly_cap_tokens\"]:,} tokens ({monthly_pct:.1f}%)')
    sys.exit(1)

if phase_pct >= 80:
    print(f'⚠️  Phase budget {phase_pct:.0f}% used: {b[\"phase_used\"]:,} / {b[\"phase_cap_tokens\"]:,}')
if monthly_pct >= 80:
    print(f'⚠️  Monthly budget {monthly_pct:.0f}% used: {b[\"monthly_used\"]:,} / {b[\"monthly_cap_tokens\"]:,}')

print('✅ Within budget')
"
    ;;

  reset)
    python3 -c "
import json
with open('$BUDGET_FILE') as f:
    b = json.load(f)
b['phase_used'] = 0
with open('$BUDGET_FILE', 'w') as f:
    json.dump(b, f, indent=2)
print('✅ Phase budget reset')
"
    ;;

  *)
    # Show current state
    python3 -c "
import json
with open('$BUDGET_FILE') as f:
    b = json.load(f)

phase_pct = (b['phase_used'] / b['phase_cap_tokens']) * 100 if b['phase_cap_tokens'] else 0
monthly_pct = (b['monthly_used'] / b['monthly_cap_tokens']) * 100 if b['monthly_cap_tokens'] else 0

print('💰 Brain Budget')
print('')
print(f'  Phase:    {b[\"phase_used\"]:>10,} / {b[\"phase_cap_tokens\"]:>10,} tokens ({phase_pct:.1f}%)')
print(f'  Monthly:  {b[\"monthly_used\"]:>10,} / {b[\"monthly_cap_tokens\"]:>10,} tokens ({monthly_pct:.1f}%)')
print(f'  Period:   {b[\"monthly_period\"]}')
print('')
if b.get('history'):
    print('Recent calls:')
    for h in b['history'][-5:]:
        print(f'  {h[\"timestamp\"]:<25} {h[\"tokens\"]:>6} tokens  {h[\"model\"]}')
"
    ;;
esac
