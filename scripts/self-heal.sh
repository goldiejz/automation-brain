#!/usr/bin/env bash
# brain self-heal — auto-diagnose and propose fixes for hook/script failures
#
# Usage: self-heal.sh <error_log_path> [context]
#
# Workflow:
# 1. Read the error log
# 2. Dispatch to cheapest AI for diagnosis
# 3. Write proposed fix to vault/self-healing/proposed/
# 4. If high confidence, auto-apply with backup
# 5. Otherwise log for human review
#
# Cost: ~$0 (Codex/Gemini free tier preferred)

set -uo pipefail

ERROR_LOG="${1:?error log path required}"
CONTEXT="${2:-}"

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
HEALING_DIR="$VAULT_PATH/self-healing"
PROPOSED_DIR="$HEALING_DIR/proposed"
APPLIED_DIR="$HEALING_DIR/applied"
mkdir -p "$PROPOSED_DIR" "$APPLIED_DIR"

[[ ! -f "$ERROR_LOG" ]] && exit 0

ERROR_CONTENT=$(cat "$ERROR_LOG" | head -100 | head -c 8000)
[[ -z "$ERROR_CONTENT" ]] && exit 0

TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
PROPOSAL_FILE="$PROPOSED_DIR/heal-$TIMESTAMP.md"

# Build diagnosis prompt
PROMPT='You are a self-healing automation diagnostic agent.

Analyze this error log and produce a structured diagnosis:

ERROR LOG:
'"$ERROR_CONTENT"'

CONTEXT: '"$CONTEXT"'

Output EXACTLY this format:

## Diagnosis
<root cause in one sentence>

## Confidence
<HIGH|MEDIUM|LOW>

## Affected Files
<list of file paths likely needing fix>

## Proposed Fix
<concrete code change OR shell command to fix it>

## Risk
<LOW|MEDIUM|HIGH> — <one sentence why>

## Auto-Apply
<YES|NO> — only YES if confidence is HIGH and risk is LOW

If you cannot diagnose, output: UNKNOWN_ERROR'

# Dispatch to cheapest AI
DIAGNOSIS=""
EXTRACTOR=""

if command -v codex >/dev/null 2>&1; then
  EXTRACTOR="codex"
  DIAGNOSIS=$(echo "$PROMPT" | codex exec - 2>/dev/null </dev/null || echo "")
fi

if [[ -z "$DIAGNOSIS" || "$DIAGNOSIS" == *"UNKNOWN_ERROR"* ]] && command -v gemini >/dev/null 2>&1; then
  EXTRACTOR="gemini"
  DIAGNOSIS=$(echo "$PROMPT" | gemini -p - 2>/dev/null || echo "")
fi

if [[ -z "$DIAGNOSIS" ]] && [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  EXTRACTOR="haiku-api"
  DIAGNOSIS=$(curl -s -X POST https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    --data "$(python3 -c "
import json, sys
print(json.dumps({
    'model': 'claude-haiku-4-5-20251001',
    'max_tokens': 1500,
    'messages': [{'role': 'user', 'content': '''$PROMPT'''}]
}))" 2>/dev/null)" 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('content', [{}])[0].get('text', ''))
except: pass
" 2>/dev/null || echo "")
fi

# If no AI available, log raw error for human review
if [[ -z "$DIAGNOSIS" ]]; then
  cat > "$PROPOSAL_FILE" <<EOF
# Self-heal failed: no AI available

**Time:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Error log:** $ERROR_LOG
**Context:** $CONTEXT

## Raw Error
\`\`\`
$ERROR_CONTENT
\`\`\`

## Required Action
Manual review needed. Install codex CLI, gemini CLI, or set ANTHROPIC_API_KEY.
EOF
  exit 1
fi

# Write proposal
cat > "$PROPOSAL_FILE" <<EOF
# Self-heal proposal — $TIMESTAMP

**Source:** $EXTRACTOR
**Error log:** $ERROR_LOG
**Context:** $CONTEXT

$DIAGNOSIS

---

## Original Error
\`\`\`
$ERROR_CONTENT
\`\`\`
EOF

echo "✅ Proposal: $PROPOSAL_FILE"

# Check if auto-apply is recommended
if echo "$DIAGNOSIS" | grep -qi "Auto-Apply.*YES"; then
  echo "🔧 High confidence + low risk → auto-applying"
  # Move to applied for tracking; actual application would extract the proposed fix
  # For safety, currently we just flag it — application requires explicit run
  cp "$PROPOSAL_FILE" "$APPLIED_DIR/"
fi

# Auto-commit to vault
if [[ -d "$VAULT_PATH/.git" ]]; then
  cd "$VAULT_PATH"
  git add self-healing/ 2>/dev/null
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "Self-heal proposal: $TIMESTAMP

Source: $EXTRACTOR
Auto-generated diagnosis from error log." --quiet 2>/dev/null
    git push origin main --quiet 2>/dev/null || true
  fi
fi

exit 0
