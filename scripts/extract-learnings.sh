#!/usr/bin/env bash
# Auto-extract learnings from a Claude Code session transcript
#
# Usage: extract-learnings.sh <transcript.jsonl> <project_dir> <session_id>
#
# Dispatches to cheapest available AI (priority order):
#   1. Multi-CLI Codex (Codex Free tier - $0)
#   2. Multi-CLI Gemini (Gemini Free tier - $0)
#   3. Haiku via Anthropic API (~$0.0003 per session)
#   4. Skip if no AI available
#
# Output: structured lesson written to vault/lessons/auto-captured/

set -uo pipefail

TRANSCRIPT="${1:?transcript path required}"
PROJECT_DIR="${2:-unknown}"
SESSION_ID="${3:-$(date +%s)}"

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
LESSONS_DIR="$VAULT_PATH/lessons/auto-captured"
mkdir -p "$LESSONS_DIR"

# Skip tiny sessions (no real work)
LINE_COUNT=$(wc -l < "$TRANSCRIPT" | tr -d ' ')
if [[ "$LINE_COUNT" -lt 5 ]]; then
  echo "Session too short ($LINE_COUNT lines), skipping extraction"
  exit 0
fi

# Build extraction prompt
PROMPT='Analyze this Claude Code session transcript and extract reusable lessons.

For each lesson found, output ONE markdown block in this exact format:

---
title: <one-line title>
type: <bugfix|pattern|gotcha|workflow>
project: '"$(basename "$PROJECT_DIR")"'
session: '"$SESSION_ID"'
date: '"$(date -u +%Y-%m-%d)"'
---

## Rule
<the lesson as a rule, e.g. "Always X" or "Never Y">

## Why
<the cost of ignoring it — reference the bug or symptom that surfaced it>

## Trigger
<when does this apply — what file/command/pattern reveals it>

## Code Example
<minimal code snippet if relevant>

---

ONLY output lessons that are non-obvious and reusable across projects.
Skip routine actions, file edits without errors, simple commands.
Output between 0 and 5 lessons total.
If no lessons found, output: NO_LESSONS

Transcript follows:'

# Read transcript content (last 200 lines to stay under context limits)
TRANSCRIPT_CONTENT=$(tail -200 "$TRANSCRIPT" 2>/dev/null | head -c 50000)

# Try Codex first (free)
if command -v codex >/dev/null 2>&1; then
  echo "Using Codex (free) for extraction..."
  EXTRACTED=$(echo -e "$PROMPT\n\n$TRANSCRIPT_CONTENT" | timeout 60 codex exec - 2>/dev/null || echo "")
fi

# Fall back to Gemini if Codex failed/unavailable
if [[ -z "${EXTRACTED:-}" ]] && command -v gemini >/dev/null 2>&1; then
  echo "Using Gemini for extraction..."
  EXTRACTED=$(echo -e "$PROMPT\n\n$TRANSCRIPT_CONTENT" | timeout 60 gemini -p - 2>/dev/null || echo "")
fi

# Fall back to Haiku via curl if API key set
if [[ -z "${EXTRACTED:-}" ]] && [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "Using Haiku API for extraction..."
  EXTRACTED=$(curl -s -X POST https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    --data "$(python3 -c "
import json, sys
print(json.dumps({
    'model': 'claude-haiku-4-5-20251001',
    'max_tokens': 2000,
    'messages': [{'role': 'user', 'content': '''$PROMPT

$TRANSCRIPT_CONTENT'''}]
}))" 2>/dev/null)" 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('content', [{}])[0].get('text', ''))
except: pass
" 2>/dev/null || echo "")
fi

# If no AI extracted lessons, fall back to regex pattern extraction
if [[ -z "${EXTRACTED:-}" ]] || [[ "$EXTRACTED" == *"NO_LESSONS"* ]]; then
  echo "No AI available — using regex pattern fallback"
  EXTRACTOR="regex-fallback"
  EXTRACTED=$(python3 <<PYEOF
import re
with open("$TRANSCRIPT") as f:
    content = f.read()

# Patterns indicating lessons
patterns = [
    (r"(?:always|never)\s+(?:[a-z]\w*\s+){2,15}", "rule"),
    (r"(?:fix(?:ed)?|fixing)\s+(?:[a-z]\w*\s+){2,20}", "fix"),
    (r"(?:lesson|gotcha|learning):?\s+([^\n.]{10,200})", "lesson"),
    (r"(?:bug|issue):?\s+([^\n.]{10,200})", "bug"),
    (r"(?:pattern|approach):?\s+([^\n.]{10,200})", "pattern"),
]

found = set()
for pattern, kind in patterns:
    for match in re.finditer(pattern, content, re.IGNORECASE):
        text = match.group(0).strip()
        if 20 < len(text) < 250 and text not in found:
            found.add(text)

if not found:
    print("NO_LESSONS")
else:
    for i, text in enumerate(list(found)[:5], 1):
        print(f"---")
        print(f"title: Auto-extracted #{i}")
        print(f"type: pattern")
        print(f"---")
        print(f"")
        print(f"## Rule")
        print(f"{text}")
        print(f"")
        print(f"## Source")
        print(f"Regex extracted from session")
        print(f"")
PYEOF
)
fi

# Final check — if still nothing, exit silently
if [[ -z "${EXTRACTED:-}" ]] || [[ "$EXTRACTED" == *"NO_LESSONS"* ]]; then
  echo "No lessons extracted from this session"
  exit 0
fi

# Write extracted lessons
LESSON_FILE="$LESSONS_DIR/auto-${SESSION_ID}-$(date -u +%Y%m%d-%H%M%S).md"
{
  echo "# Auto-captured lessons from session $SESSION_ID"
  echo ""
  echo "**Project:** $(basename "$PROJECT_DIR")"
  echo "**Source:** $TRANSCRIPT"
  echo "**Extracted:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "---"
  echo ""
  echo "$EXTRACTED"
} > "$LESSON_FILE"

echo "✅ Wrote lessons to $LESSON_FILE"

# Trigger Phase 6 to integrate new lessons
if [[ -f "$VAULT_PATH/observability/phase-6-daemon.ts" ]]; then
  cd "$VAULT_PATH"
  nohup npx ts-node observability/phase-6-daemon.ts > /dev/null 2>&1 &
  disown 2>/dev/null || true
fi

# Auto-commit to vault if it's a git repo
if [[ -d "$VAULT_PATH/.git" ]]; then
  cd "$VAULT_PATH"
  git add lessons/auto-captured/ 2>/dev/null
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "Auto-captured lessons from session $SESSION_ID

Project: $(basename "$PROJECT_DIR")
Extracted via: ${EXTRACTOR:-AI}
" --quiet 2>/dev/null
    git push origin main --quiet 2>/dev/null || true
  fi
fi

exit 0
