#!/usr/bin/env bash
# ark context — detect runtime environment + available AI dispatchers
#
# Outputs runtime state so other Ark scripts can choose the right dispatcher
# WITHOUT requiring user intervention.
#
# Usage:
#   ark-context.sh                     # human-readable
#   ark-context.sh --json              # JSON for programmatic use
#   ark-context.sh --primary           # output primary dispatcher name
#   ark-context.sh --can-dispatch CLI  # exit 0 if CLI is available + has quota
#
# Detects:
#   1. Running inside Claude Code session?  → claude-code-session is primary
#   2. Codex CLI quota status                → check via probe call
#   3. Gemini CLI quota status               → check via probe call
#   4. ANTHROPIC_API_KEY set?                → Haiku API available
#   5. Fallback: regex extraction always works

set -uo pipefail

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
QUOTA_CACHE="$VAULT_PATH/cache/dispatcher-quota.json"
mkdir -p "$(dirname "$QUOTA_CACHE")"

ACTION="${1:-show}"

# === Runtime detection ===
detect_claude_code() {
  # Multiple signals that we're inside Claude Code:
  [[ -n "${CLAUDE_PROJECT_DIR:-}" ]] && return 0
  [[ -n "${CLAUDE_IDE_SESSION_ID:-}" ]] && return 0
  [[ -n "${CLAUDE_CODE_SIMPLE:-}" ]] && return 0
  return 1
}

# === Quota probing ===
# Cache quota status to avoid probing on every call (expensive + lossy).
# Mark exhausted on probe-fail, reset after 6 hours.

probe_codex_quota() {
  if ! command -v codex >/dev/null 2>&1; then
    echo "missing"
    return
  fi
  # Quick probe: ask codex something trivial with short timeout
  local result
  result=$(echo "ok" | timeout 5 codex exec - 2>&1 | head -3 </dev/null || echo "")
  if [[ "$result" == *"hit your usage limit"* ]] || \
     [[ "$result" == *"quota"* ]] || \
     [[ "$result" == *"upgrade"* ]] || \
     [[ "$result" == *"Plan"* && "$result" == *"limit"* ]]; then
    echo "exhausted"
  elif [[ -z "$result" ]]; then
    echo "unreachable"
  else
    echo "available"
  fi
}

probe_gemini_quota() {
  if ! command -v gemini >/dev/null 2>&1; then
    echo "missing"
    return
  fi
  local result
  result=$(echo "ok" | timeout 5 gemini -p - 2>&1 | head -3 || echo "")
  if [[ "$result" == *"quota"* ]] || \
     [[ "$result" == *"capacity"* ]] || \
     [[ "$result" == *"TerminalQuotaError"* ]]; then
    echo "exhausted"
  elif [[ -z "$result" ]]; then
    echo "unreachable"
  else
    echo "available"
  fi
}

# Use cached probes if recent (< 6 hours old)
get_cached_or_probe() {
  local dispatcher="$1"
  local probe_fn="$2"

  if [[ -f "$QUOTA_CACHE" ]]; then
    local age
    age=$(( $(date +%s) - $(stat -f %m "$QUOTA_CACHE" 2>/dev/null || stat -c %Y "$QUOTA_CACHE" 2>/dev/null || echo 0) ))
    if [[ $age -lt 21600 ]]; then  # 6 hours
      python3 -c "
import json, sys
try:
    d = json.load(open('$QUOTA_CACHE'))
    print(d.get('$dispatcher', 'unknown'))
except: print('unknown')
" 2>/dev/null
      return
    fi
  fi

  # Fresh probe
  $probe_fn
}

update_cache() {
  local codex_status="$1"
  local gemini_status="$2"
  python3 -c "
import json, datetime
data = {
    'codex': '$codex_status',
    'gemini': '$gemini_status',
    'last_probed': datetime.datetime.utcnow().isoformat() + 'Z'
}
with open('$QUOTA_CACHE', 'w') as f:
    json.dump(data, f, indent=2)
"
}

# === Main detection logic ===
gather_state() {
  local in_claude_code="false"
  detect_claude_code && in_claude_code="true"

  local codex_status="$(get_cached_or_probe codex probe_codex_quota)"
  local gemini_status="$(get_cached_or_probe gemini probe_gemini_quota)"

  local haiku_available="false"
  [[ -n "${ANTHROPIC_API_KEY:-}" ]] && haiku_available="true"

  # Determine primary dispatcher (priority order):
  # 1. claude-code-session (always available + most capable when in CC)
  # 2. codex (free if available)
  # 3. gemini (free if available)
  # 4. haiku-api (paid, ~$0.0003/task)
  # 5. regex-fallback (always works, no AI)
  local primary="regex-fallback"
  if [[ "$in_claude_code" == "true" ]]; then
    primary="claude-code-session"
  elif [[ "$codex_status" == "available" ]]; then
    primary="codex"
  elif [[ "$gemini_status" == "available" ]]; then
    primary="gemini"
  elif [[ "$haiku_available" == "true" ]]; then
    primary="haiku-api"
  fi

  # Update cache for future calls
  update_cache "$codex_status" "$gemini_status" >/dev/null 2>&1

  case "$ACTION" in
    --json)
      python3 -c "
import json
print(json.dumps({
    'in_claude_code': $([[ \"$in_claude_code\" == \"true\" ]] && echo 'True' || echo 'False'),
    'primary_dispatcher': '$primary',
    'dispatchers': {
        'claude-code-session': {'available': $([[ \"$in_claude_code\" == \"true\" ]] && echo 'True' || echo 'False')},
        'codex': {'status': '$codex_status'},
        'gemini': {'status': '$gemini_status'},
        'haiku-api': {'available': $([[ \"$haiku_available\" == \"true\" ]] && echo 'True' || echo 'False')},
        'regex-fallback': {'available': True}
    }
}, indent=2))
"
      ;;

    --primary)
      echo "$primary"
      ;;

    --can-dispatch)
      local cli="${2:-}"
      case "$cli" in
        codex) [[ "$codex_status" == "available" ]] ;;
        gemini) [[ "$gemini_status" == "available" ]] ;;
        haiku-api) [[ "$haiku_available" == "true" ]] ;;
        claude-code-session) [[ "$in_claude_code" == "true" ]] ;;
        regex-fallback) true ;;
        *) false ;;
      esac
      exit $?
      ;;

    show|*)
      echo "🚢 Ark Context"
      echo ""
      echo "  Runtime:"
      if [[ "$in_claude_code" == "true" ]]; then
        echo "    ✅ Inside Claude Code session — primary dispatcher: this session"
      else
        echo "    ⚠️  Headless shell — must use external CLIs"
      fi
      echo ""
      echo "  Dispatchers:"

      # Helper to format status with emoji
      format_status() {
        case "$1" in
          available) echo "✅ available" ;;
          exhausted) echo "🛑 quota exhausted" ;;
          missing) echo "❌ not installed" ;;
          unreachable) echo "⚠️  unreachable" ;;
          *) echo "$1" ;;
        esac
      }

      cc_status="❌ unavailable"
      [[ "$in_claude_code" == "true" ]] && cc_status="✅ active"
      printf "    %-22s %s\n" "claude-code-session" "$cc_status"
      printf "    %-22s %s\n" "codex" "$(format_status "$codex_status")"
      printf "    %-22s %s\n" "gemini" "$(format_status "$gemini_status")"

      haiku_label="⚠️  no API key"
      [[ "$haiku_available" == "true" ]] && haiku_label="✅ ANTHROPIC_API_KEY set"
      printf "    %-22s %s\n" "haiku-api" "$haiku_label"
      printf "    %-22s %s\n" "regex-fallback" "✅ always available"
      echo ""
      echo "  ➜ Primary dispatcher: $primary"
      echo ""
      ;;
  esac
}

gather_state
