#!/usr/bin/env bash
# Ark SessionStart hook — auto-detect and sync brain when entering a project
#
# Behavior:
# - If CWD has .parent-automation/, auto-pull latest vault and refresh snapshot
# - If CWD doesn't have .parent-automation/ but has typical project markers
#   (package.json, .git, src/), suggest 'ark init'
# - Silent if CWD is not a project
#
# This makes brain a fundamental, automatic part of every Claude Code session.

# Optional diagnostic logging — only writes if log file already exists
LOG_FILE="$HOME/.claude/hooks/brain-hook-debug.log"
[[ -f "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] brain-session-start.sh fired (project: ${CLAUDE_PROJECT_DIR:-$(pwd)})" >> "$LOG_FILE"

# NOTE: deliberately NOT using 'set -e' — failed [[ checks would terminate
# the script and silently drop our context output before stdout flushes.

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"

# Resolve project dir: prefer Claude Code env var, fall back to pwd
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${CLAUDE_WORKING_DIR:-$(pwd)}}"

# Skip if vault doesn't exist
if [[ ! -d "$VAULT_PATH" ]]; then
  exit 0
fi

# Skip if we're inside the vault itself
if [[ "$PROJECT_DIR" == "$VAULT_PATH"* ]]; then
  exit 0
fi

# Detect project state
HAS_PARENT_AUTOMATION=false
HAS_PROJECT_MARKERS=false

if [[ -d "$PROJECT_DIR/.parent-automation" ]]; then
  HAS_PARENT_AUTOMATION=true
fi

if [[ -f "$PROJECT_DIR/package.json" ]] || [[ -f "$PROJECT_DIR/Cargo.toml" ]] || [[ -f "$PROJECT_DIR/pyproject.toml" ]] || [[ -f "$PROJECT_DIR/go.mod" ]] || [[ -d "$PROJECT_DIR/.git" ]]; then
  HAS_PROJECT_MARKERS=true
fi

# Helper: emit Claude Code SessionStart hook JSON with additionalContext
emit_context() {
  local context="$1"
  local visible="$2"
  # Use python3 for safe JSON escaping; emit both:
  #   - additionalContext: injected into model's context
  #   - systemMessage: visible to user in the UI
  python3 <<PYEOF
import json
context = """$context"""
visible = """$visible"""
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": context,
    },
    "systemMessage": visible,
}))
PYEOF
}

# Case 1: Has brain integration → silent sync (background, non-blocking)
if [[ "$HAS_PARENT_AUTOMATION" == "true" ]]; then
  # Quick sync in background, don't block session start
  (bash "$VAULT_PATH/scripts/brain-sync.sh" "$PROJECT_DIR" > /tmp/brain-sync-$$.log 2>&1 &) 2>/dev/null

  # Build status block
  SNAPSHOT_MANIFEST="$PROJECT_DIR/.parent-automation/ark-snapshot/SNAPSHOT-MANIFEST.json"
  if [[ -f "$SNAPSHOT_MANIFEST" ]]; then
    LESSONS=$(grep -o '"lessons":[ ]*[0-9]*' "$SNAPSHOT_MANIFEST" | head -1 | grep -o '[0-9]*')
    DECISIONS=0
    if [[ -f "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl" ]]; then
      DECISIONS=$(wc -l < "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl" | tr -d ' ')
    fi
    CONTEXT="=== BRAIN ACTIVE ===
Project: $(basename "$PROJECT_DIR")
Snapshot: $LESSONS lessons available (vault: $VAULT_PATH)
Decisions logged: $DECISIONS
Available commands: /ark status, /ark bootstrap, /ark insights, /brain scaffold, /ark dev
Vault syncing in background.
The brain provides cached templates, cross-project lessons, and intelligent model routing for this project."
    VISIBLE="🧠 Ark Active: $(basename "$PROJECT_DIR") · $LESSONS lessons · $DECISIONS decisions logged · /ark status, /ark bootstrap, /ark insights, /brain scaffold"
    emit_context "$CONTEXT" "$VISIBLE"
  fi
  exit 0
fi

# Case 2: Looks like a project but no brain → suggest init
if [[ "$HAS_PROJECT_MARKERS" == "true" ]]; then
  CONTEXT="=== BRAIN AVAILABLE ===
This project has no .parent-automation/ directory — brain integration not active.
To activate: invoke /ark init
Benefits: 70% token reduction via cached templates, access to 55+ cross-project lessons, automatic decision logging that improves the brain over time.
The user explicitly requested brain to be a fundamental part of every project workflow."
  VISIBLE="🧠 Ark Available — this project has no .parent-automation/. Run /ark init to activate (70% token reduction, 55+ cross-project lessons)"
  emit_context "$CONTEXT" "$VISIBLE"
  exit 0
fi

# Case 3: Not a project — silent
exit 0
