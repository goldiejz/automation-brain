#!/usr/bin/env bash
# ark validate — drift detection for cached templates
#
# Periodically re-runs cached prompts through current AI to detect drift.
# If output diverges significantly from cached, flags template as stale.
#
# Usage:
#   ark validate              # quick check (sample 3 cached templates)
#   ark validate --full       # validate all cache entries
#   ark validate --query <id> # validate specific cached query

set -uo pipefail

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
CACHE_DIR="$VAULT_PATH/cache/query-responses"
DRIFT_LOG="$VAULT_PATH/observability/template-drift.md"

MODE="quick"
QUERY_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) MODE="full"; shift ;;
    --query) QUERY_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "🔍 Ark Validate — Template Drift Detection"
echo ""

# Initialize drift log
mkdir -p "$(dirname "$DRIFT_LOG")"
cat > "$DRIFT_LOG" <<EOF
# Template Drift Log

**Last validated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

| Query ID | Last Validated | Drift Score | Status |
|----------|----------------|-------------|--------|
EOF

validate_template() {
  local query_id="$1"
  local cache_file="$CACHE_DIR/$query_id.md"

  if [[ ! -f "$cache_file" ]]; then
    return
  fi

  # Extract the original prompt from frontmatter
  local original_prompt=$(awk '/^---$/{count++; if(count==1) inblock=1; else if(count==2) inblock=0} inblock && /^optimized_prompt:/,/^[a-z_]+:/' "$cache_file" 2>/dev/null | head -20)

  if [[ -z "$original_prompt" ]]; then
    echo "  ⏭ $query_id: no prompt in frontmatter"
    return
  fi

  # Get current response from AI
  local current_response=""
  if command -v codex >/dev/null 2>&1; then
    current_response=$(echo "$original_prompt" | codex exec - 2>/dev/null </dev/null | head -200 || echo "")
  fi

  if [[ -z "$current_response" ]]; then
    echo "  ⚠️  $query_id: no AI available, can't validate"
    return
  fi

  # Compare cached vs current (simple word-level overlap heuristic)
  local cached_content=$(awk '/^## Answer/,/^## /' "$cache_file" 2>/dev/null | head -100)

  local drift_score=$(python3 -c "
import sys
cached = '''$cached_content'''
current = '''$current_response'''

# Simple Jaccard similarity on words
cached_words = set(cached.lower().split())
current_words = set(current.lower().split())
if not cached_words or not current_words:
    print('1.0')
else:
    overlap = cached_words & current_words
    union = cached_words | current_words
    similarity = len(overlap) / len(union) if union else 0
    drift = 1.0 - similarity
    print(f'{drift:.2f}')
" 2>/dev/null || echo "0.0")

  local status
  if (( $(echo "$drift_score > 0.5" | bc -l 2>/dev/null || echo 0) )); then
    status="🚨 HIGH DRIFT"
    echo "| $query_id | $(date -u +%Y-%m-%d) | $drift_score | $status |" >> "$DRIFT_LOG"
  elif (( $(echo "$drift_score > 0.3" | bc -l 2>/dev/null || echo 0) )); then
    status="⚠️ MEDIUM DRIFT"
    echo "| $query_id | $(date -u +%Y-%m-%d) | $drift_score | $status |" >> "$DRIFT_LOG"
  else
    status="✅ STABLE"
    echo "| $query_id | $(date -u +%Y-%m-%d) | $drift_score | $status |" >> "$DRIFT_LOG"
  fi

  echo "  $status — $query_id (drift: $drift_score)"
}

# Determine which templates to validate
if [[ -n "$QUERY_ID" ]]; then
  validate_template "$QUERY_ID"
elif [[ "$MODE" == "full" ]]; then
  for cache_file in "$CACHE_DIR"/*.md; do
    [[ ! -f "$cache_file" ]] && continue
    qid=$(basename "$cache_file" .md)
    validate_template "$qid"
  done
else
  # Quick: sample 3 random templates
  ls "$CACHE_DIR"/*.md 2>/dev/null | sort -R | head -3 | while read cache_file; do
    qid=$(basename "$cache_file" .md)
    validate_template "$qid"
  done
fi

echo ""
echo "Drift log: $DRIFT_LOG"
echo ""
echo "Templates with HIGH drift should be regenerated:"
grep "🚨" "$DRIFT_LOG" 2>/dev/null | head -5
